import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/game/game_constants.dart';
import '../../core/game/game_format.dart';
import '../../core/game/game_session_events.dart';
import '../../core/game/progression_service.dart';
import '../../core/one_view/one_view_layout.dart';
import '../../core/one_view/one_view_match_recording.dart';
import '../../core/one_view/one_view_orientation.dart';
import '../../core/one_view/one_view_sit_code.dart';
import '../../core/one_view/one_view_state.dart';
import '../../core/one_view/one_view_xp_claim.dart';
import '../../core/persistence/providers.dart';
import '../../features/game/widgets/game_modal_chrome.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/app_router.dart';
import '../../shared/utils/game_haptics.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/motion_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/life_counter_widget.dart';
import '../game/widgets/team_colors.dart';
import 'one_view_art_picker.dart';
import 'one_view_attack.dart';
import 'one_view_deck_picker.dart';
import 'one_view_layout_picker.dart';
import 'one_view_table_tools.dart';
import 'one_view_xp_claim_ui.dart';

/// Shared-phone tabletop: life +/- , claim, center tools.
/// Far-side seats turn 180° so the player across the table can read them.
class OneViewTableScreen extends ConsumerStatefulWidget {
  const OneViewTableScreen({super.key});

  @override
  ConsumerState<OneViewTableScreen> createState() => _OneViewTableScreenState();
}

class _OneViewTableScreenState extends ConsumerState<OneViewTableScreen>
    with WidgetsBindingObserver {
  TableToolAnnouncement? _diceAnnouncement;
  final List<GlobalKey> _seatCardKeys = [];
  ({int from, int to, bool faceDown})? _attack;
  int? _dragFrom;
  Offset? _dragOrigin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _applyTableOrientation(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    OneViewOrientation.restoreAppDefault();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _applyTableOrientation();
  }

  void _applyTableOrientation() {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    OneViewOrientation.lockForTable(size);
  }

  /// Keep the hub on a seam, not on top of a life total.
  /// One seat has no seam, so the hub sits low.
  Alignment _hubAlignment(int seatCount) {
    if (seatCount <= 1) return const Alignment(0, 0.72);
    return Alignment.center;
  }

  /// Full tables have a smaller gap, so the hub shrinks with the crowd.
  double _hubSize(int seatCount) {
    if (seatCount <= 2) return 64;
    if (seatCount <= 4) return 56;
    return 44;
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.oneViewEndTableTitle),
            content: Text(l10n.oneViewEndTableBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.oneViewEndTableConfirm),
              ),
            ],
          ),
    );
    if (leave != true || !mounted) return;

    final oneView = ref.read(oneViewProvider);
    final profile = ref.read(profileRepositoryProvider).getProfile();
    final claimed = oneView.seats.where((s) => s.isClaimed).toList();

    String? winnerPlayerId;
    if (claimed.length >= 2) {
      final pick = await _pickWinner(claimed);
      if (!mounted) return;
      // Cancel aborts the whole end-table flow (table stays open).
      if (pick == null) return;
      winnerPlayerId = pick.winnerPlayerId;
    }

    // One match id shared by host recording + friend claim QRs.
    final matchId = DateTime.now().millisecondsSinceEpoch.toString();
    final snapshots = oneViewRecordingSnapshots(
      oneView: oneView,
      localPlayerId: profile?.playerId,
      winnerPlayerId: winnerPlayerId,
    );

    var recordedXp = 0;
    if (snapshots != null && snapshots.game.localPlayerId.isNotEmpty) {
      final result = await ref
          .read(progressionServiceProvider)
          .recordMatch(
            finalState: snapshots.game,
            lobbyState: snapshots.lobby,
            startTime: oneView.startTime ?? DateTime.now(),
            matchId: matchId,
          );
      bumpProfileRevision(ref);
      bumpDeckListRevision(ref);
      if (result.awardsProgression && result.xpGained > 0) {
        recordedXp = result.xpGained;
      }
    }

    // Cross-phone XP only when the table itself would award progression.
    final claimSeats =
        claimed.length >= 2
            ? oneViewXpClaimSeats(
              oneView: oneView,
              localPlayerId: profile?.playerId,
            )
            : const <OneViewSeat>[];
    if (mounted && claimSeats.isNotEmpty) {
      final start = oneView.startTime ?? DateTime.now();
      final durationSeconds = DateTime.now().difference(start).inSeconds;
      final claims =
          claimSeats.map((seat) {
            final opponents =
                claimed
                    .where((s) => s.playerId != seat.playerId)
                    .map((s) => s.displayName)
                    .toList();
            return (
              seat: seat,
              payload: OneViewXpClaim.build(
                matchId: matchId,
                playerId: seat.playerId!,
                username: seat.displayName,
                won: winnerPlayerId != null && winnerPlayerId == seat.playerId,
                playerCount: claimed.length,
                format: oneView.config.format.displayName,
                startingLife: oneView.config.startingLife,
                commanderName: seat.commanderName,
                opponentNames: opponents,
                durationSeconds: durationSeconds,
              ),
            );
          }).toList();
      await showOneViewXpClaimHandoffSheet(context: context, claims: claims);
    }

    if (mounted && recordedXp > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.oneViewMatchRecorded(recordedXp))),
      );
    }

    ref.read(oneViewProvider.notifier).reset();
    if (!mounted) return;
    context.go(AppRoutes.lobby);
  }

  /// Picks a winner, or skip (no winner). Returns null when the user cancels
  /// (abort end-table).
  Future<({String? winnerPlayerId})?> _pickWinner(
    List<OneViewSeat> claimed,
  ) async {
    final l10n = AppLocalizations.of(context);
    return showDialog<({String? winnerPlayerId})>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.oneViewPickWinnerTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.oneViewPickWinnerBody),
                const SizedBox(height: 12),
                for (final seat in claimed)
                  ListTile(
                    title: Text(seat.displayName),
                    onTap:
                        () =>
                            Navigator.pop(ctx, (winnerPlayerId: seat.playerId)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, (winnerPlayerId: null)),
              child: Text(l10n.oneViewPickWinnerSkip),
            ),
          ],
        );
      },
    );
  }

  void _syncSeatKeys(int count) {
    while (_seatCardKeys.length < count) {
      _seatCardKeys.add(GlobalKey());
    }
    if (_seatCardKeys.length > count) {
      _seatCardKeys.removeRange(count, _seatCardKeys.length);
    }
  }

  void _clearAttackDrag() {
    _dragFrom = null;
    _dragOrigin = null;
  }

  void _onTablePointerDown(PointerDownEvent event) {
    final table = ref.read(oneViewProvider);
    if (!table.config.attackSwipeEnabled ||
        _attack != null ||
        _diceAnnouncement != null) {
      _clearAttackDrag();
      return;
    }
    _dragOrigin = event.position;
    _dragFrom = _seatAt(event.position, centerOnly: true);
  }

  void _onTablePointerUp(PointerUpEvent event) {
    final from = _dragFrom;
    final origin = _dragOrigin;
    _clearAttackDrag();
    if (from == null || origin == null || _attack != null) return;
    if ((event.position - origin).distance < oneViewAttackMinTravel) return;
    final table = ref.read(oneViewProvider);
    final seats = table.seats;
    if (from >= seats.length || !seats[from].isClaimed) return;
    final to = _seatAt(event.position, centerOnly: false);
    if (to == null || to == from || !seats[to].isClaimed) return;
    final layout =
        table.layout.fits(seats.length)
            ? table.layout
            : OneViewSeatLayout.defaultFor(seats.length);
    setState(
      () =>
          _attack = (
            from: from,
            to: to,
            faceDown: oneViewSeatUpsideDown(layout.split, from),
          ),
    );
  }

  void _onTablePointerCancel(PointerCancelEvent event) {
    _clearAttackDrag();
  }

  /// [centerOnly] keeps the drag off the − / + bands. The release can land
  /// anywhere on the other card.
  int? _seatAt(Offset global, {required bool centerOnly}) {
    final seats = ref.read(oneViewProvider).seats;
    final count = math.min(seats.length, _seatCardKeys.length);
    for (var i = 0; i < count; i++) {
      if (!seats[i].isClaimed) continue;
      final render = _seatCardKeys[i].currentContext?.findRenderObject();
      if (render is! RenderBox || !render.attached || !render.hasSize) {
        continue;
      }
      final local = render.globalToLocal(global);
      final rect =
          centerOnly
              ? oneViewAttackCenter(render.size)
              : Offset.zero & render.size;
      if (rect.contains(local)) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(oneViewProvider);

    if (!state.started || state.seats.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(AppRoutes.oneViewSetup);
      });
      return Scaffold(
        backgroundColor: colors.backgroundPrimary,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    _syncSeatKeys(state.seats.length);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      // Sheets lift themselves. Resizing the table under the keyboard
      // overflowed the seats and closed the field the player had just tapped.
      resizeToAvoidBottomInset: false,
      // Inset seats from status / nav / cutout so +/- and life never sit
      // under system chrome. No reserved tool bar — only system SafeArea.
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              onPointerDown: _onTablePointerDown,
              onPointerUp: _onTablePointerUp,
              onPointerCancel: _onTablePointerCancel,
              child: _SeatLayout(
                seats: state.seats,
                layout: state.layout,
                teamsEnabled: state.config.teamsEnabled,
                cardKeys: _seatCardKeys,
                onSeatTap: (i) => _onSeatTap(i, state.seats[i]),
                onLifeDelta: (i, d) {
                  ref.read(oneViewProvider.notifier).adjustLife(i, d);
                },
              ),
            ),
            Align(
              alignment: _hubAlignment(state.seats.length),
              child: _CenterHub(
                size: _hubSize(state.seats.length),
                onOpen: () => _showHubMenu(l10n),
              ),
            ),
            if (_diceAnnouncement != null)
              Positioned.fill(
                child: OneViewDiceOverlay(
                  announcement: _diceAnnouncement!,
                  onDismiss: () => setState(() => _diceAnnouncement = null),
                ),
              ),
            if (_attack != null)
              Positioned.fill(
                child: OneViewAttackOverlay(
                  attackerIndex: _attack!.from,
                  defenderIndex: _attack!.to,
                  faceAttackerUpsideDown: _attack!.faceDown,
                  onDismiss: () {
                    if (!mounted) return;
                    setState(() => _attack = null);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSeatTap(int index, OneViewSeat seat) async {
    if (seat.isEmpty) {
      await _showClaimSheet(index);
      return;
    }
    await _showSeatTools(index, seat);
  }

  Future<void> _showClaimSheet(int seatIndex) async {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    await showGameBottomSheet<void>(
      context: context,
      enableDrag: false,
      builder: (ctx) {
        return GameSheetBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GameSheetHeader(title: l10n.oneViewClaimSeatTitle),
              SizedBox(height: LayoutTokens.gr2),
              ListTile(
                leading: Icon(
                  Icons.person_rounded,
                  color: colors.primaryAccent,
                ),
                title: Text(l10n.oneViewSitAsMe),
                subtitle: Text(l10n.oneViewSitAsMeSubtitle),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = ref
                      .read(oneViewProvider.notifier)
                      .claimAsMe(seatIndex);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.oneViewSitBlocked)),
                    );
                    return;
                  }
                  if (!mounted) return;
                  await showOneViewDeckPicker(context, ref, seatIndex);
                  await _promptSeatArt(seatIndex);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: colors.primaryAccent,
                ),
                title: Text(l10n.oneViewLoadViaQr),
                subtitle: Text(l10n.oneViewLoadViaQrSubtitle),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _scanSitCode(seatIndex);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.person_outline_rounded,
                  color: colors.textSecondary,
                ),
                title: Text(l10n.oneViewSitAsGuest),
                subtitle: Text(l10n.oneViewSitAsGuestSubtitle),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _guestNameThenClaim(seatIndex);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _guestNameThenClaim(int seatIndex) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return GameFormDialog(
          title: l10n.oneViewGuestNameTitle,
          submitLabel: l10n.oneViewSitAsGuest,
          onSubmit: () => Navigator.pop(ctx, controller.text),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: l10n.oneViewGuestNameHint),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        );
      },
    );
    // Dispose after the dialog route finishes tearing down — disposing
    // immediately races the exit animation and red-screens the table.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    // Cancel / dismiss must not claim a seat.
    if (!mounted || name == null) return;
    ref.read(oneViewProvider.notifier).claimAsGuest(seatIndex, name: name);
    await _promptSeatArt(seatIndex);
  }

  /// A new player is asked for a picture when the seat does not have one yet.
  Future<void> _promptSeatArt(int seatIndex) async {
    if (!mounted) return;
    final seats = ref.read(oneViewProvider).seats;
    if (seatIndex < 0 || seatIndex >= seats.length) return;
    final url = seats[seatIndex].commanderImageUrl?.trim();
    if (url != null && url.isNotEmpty) return;
    await showOneViewArtPicker(context, ref, seatIndex);
  }

  Future<void> _scanSitCode(int seatIndex) async {
    final l10n = AppLocalizations.of(context);
    final parsed = await Navigator.of(
      context,
    ).push<({String playerId, String username, String? avatarUrl})>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _SitCodeScannerPage(),
      ),
    );
    if (parsed == null || !mounted) return;
    final ok = ref
        .read(oneViewProvider.notifier)
        .claimFromSitCode(
          seatIndex: seatIndex,
          playerId: parsed.playerId,
          username: parsed.username,
          avatarUrl: parsed.avatarUrl,
        );
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.oneViewSitBlocked)));
      return;
    }
    await showOneViewDeckPicker(context, ref, seatIndex);
    await _promptSeatArt(seatIndex);
  }

  Future<void> _showSeatTools(int index, OneViewSeat seat) async {
    final l10n = AppLocalizations.of(context);
    await showGameBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final live = ref.watch(
              oneViewProvider.select(
                (s) => s.seats.firstWhere((x) => x.index == index),
              ),
            );
            final allSeats = ref.watch(oneViewProvider.select((s) => s.seats));
            final colors = AppColorTokens.of(context);
            final notifier = ref.read(oneViewProvider.notifier);
            final others = allSeats.where(
              (s) => s.index != index && s.isClaimed,
            );
            return GameSheetBody(
              scrollable: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GameSheetHeader(title: live.displayName),
                  const SizedBox(height: LayoutTokens.gr2),
                  _SeatMenuLabel(l10n.oneViewMenuCounters),
                  _SeatCounterRow(
                    label: l10n.oneViewPoisonLabel,
                    value: live.poison,
                    lethal: live.poison >= GameConstants.poisonKo,
                    minusLabel: l10n.oneViewPoisonMinus,
                    plusLabel: l10n.oneViewPoisonPlus,
                    onMinus: () => notifier.adjustPoison(index, -1),
                    onPlus: () => notifier.adjustPoison(index, 1),
                  ),
                  const SizedBox(height: LayoutTokens.gr2),
                  _SeatMenuLabel(l10n.oneViewCommanderDamageLabel),
                  if (others.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: LayoutTokens.gr2,
                        top: 4,
                      ),
                      child: Text(
                        l10n.oneViewCommanderDamageEmpty,
                        style: GoogleFonts.lato(
                          color: colors.textSecondary,
                          fontSize: FontTokens.hudSm,
                          height: 1.3,
                        ),
                      ),
                    )
                  else
                    for (final from in others)
                      Padding(
                        padding: const EdgeInsets.only(left: LayoutTokens.gr2),
                        child: _SeatCounterRow(
                          label: from.displayName,
                          value: live.commanderDamageFrom[from.index] ?? 0,
                          lethal:
                              (live.commanderDamageFrom[from.index] ?? 0) >=
                              GameConstants.commanderDamageKo,
                          minusLabel: l10n.lifeA11yDecrease,
                          plusLabel: l10n.lifeA11yIncrease,
                          onMinus:
                              () => notifier.adjustCommanderDamage(
                                targetSeatIndex: index,
                                fromSeatIndex: from.index,
                                delta: -1,
                              ),
                          onPlus:
                              () => notifier.adjustCommanderDamage(
                                targetSeatIndex: index,
                                fromSeatIndex: from.index,
                                delta: 1,
                              ),
                        ),
                      ),
                  const SizedBox(height: LayoutTokens.gr3),
                  _SeatMenuLabel(l10n.oneViewMenuSeat),
                  _SeatActionRow(
                    icon: Icons.image_outlined,
                    label: l10n.oneViewCardArt,
                    detail:
                        live.commanderName?.trim().isNotEmpty == true
                            ? live.commanderName!.trim()
                            : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await showOneViewArtPicker(context, ref, index);
                    },
                  ),
                  if (!live.isGuest)
                    _SeatActionRow(
                      icon: Icons.style_outlined,
                      label: l10n.oneViewChangeDeck,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await showOneViewDeckPicker(context, ref, index);
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: LayoutTokens.gr1,
                    ),
                    child: Divider(height: 1, color: colors.borderSubtle),
                  ),
                  _SeatActionRow(
                    icon: Icons.logout_rounded,
                    label: l10n.oneViewClearSeat,
                    color: colors.error,
                    onTap: () {
                      notifier.clearSeat(index);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showHubMenu(AppLocalizations l10n) async {
    final colors = AppColorTokens.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.72;
        Widget row({
          required IconData icon,
          required String label,
          required VoidCallback onTap,
          Color? color,
        }) {
          final ink = color ?? colors.textPrimary;
          return InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LayoutTokens.gr2,
                vertical: LayoutTokens.gr3,
              ),
              child: Row(
                children: [
                  Icon(icon, color: ink, size: 28),
                  const SizedBox(width: LayoutTokens.gr2),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: ink,
                        fontSize: FontTokens.headline,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return AlertDialog(
          backgroundColor: colors.surface,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: LayoutTokens.gr4,
            vertical: LayoutTokens.gr4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: RadiusTokens.radiusXl,
            side: BorderSide(color: colors.borderSubtle),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            LayoutTokens.gr3,
            LayoutTokens.gr3,
            LayoutTokens.gr2,
            0,
          ),
          title: GameDialogTitleRow(
            titleWidget: Text(
              l10n.oneViewTableMenu,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: FontTokens.headline,
                fontWeight: FontWeight.w700,
              ),
            ),
            onClose: () => Navigator.pop(ctx),
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            LayoutTokens.gr1,
            LayoutTokens.gr2,
            LayoutTokens.gr1,
            LayoutTokens.gr2,
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  row(
                    icon: Icons.casino_rounded,
                    label: l10n.tableToolsTitle,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final profile =
                          ref.read(profileRepositoryProvider).getProfile();
                      final roll = await showOneViewDiceSheet(
                        context,
                        rollerName: profile?.username ?? 'Table',
                      );
                      if (roll != null && mounted) {
                        setState(() => _diceAnnouncement = roll);
                      }
                    },
                  ),
                  if (ref.read(oneViewProvider).config.teamsEnabled)
                    row(
                      icon: Icons.palette_rounded,
                      label: l10n.oneViewColorsTitle,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await showOneViewColorsSheet(context, ref);
                      },
                    ),
                  row(
                    icon: Icons.tune_rounded,
                    label: l10n.oneViewMidGameSettings,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await showOneViewSettingsSheet(context, ref);
                    },
                  ),
                  row(
                    icon: Icons.restart_alt_rounded,
                    label: l10n.oneViewResetLife,
                    onTap: () {
                      ref.read(oneViewProvider.notifier).resetLifeTotals();
                      Navigator.pop(ctx);
                    },
                  ),
                  row(
                    icon: Icons.groups_rounded,
                    label: l10n.oneViewPlayerCountTitle,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await showOneViewPlayerCountSheet(context, ref);
                    },
                  ),
                  row(
                    icon: Icons.grid_view_rounded,
                    label: l10n.oneViewLayoutTitle,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await showOneViewLayoutPicker(context, ref);
                    },
                  ),
                  row(
                    icon: Icons.exit_to_app_rounded,
                    label: l10n.oneViewEndTableConfirm,
                    color: colors.error,
                    onTap: () {
                      Navigator.pop(ctx);
                      _leave();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small floating hub at the table center — tools open on tap, no bottom bar.
class _SeatMenuLabel extends StatelessWidget {
  const _SeatMenuLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: LayoutTokens.gr0),
      child: Text(
        text,
        style: GoogleFonts.lato(
          color: colors.textSecondary,
          fontSize: FontTokens.caption,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          height: 1.2,
        ),
      ),
    );
  }
}

/// One counter that can change or end the life total: a label and − / +.
class _SeatCounterRow extends StatelessWidget {
  const _SeatCounterRow({
    required this.label,
    required this.value,
    required this.lethal,
    required this.minusLabel,
    required this.plusLabel,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final bool lethal;
  final String minusLabel;
  final String plusLabel;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return SizedBox(
      height: LayoutTokens.minTapTarget,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.lato(
                color: colors.textPrimary,
                fontSize: FontTokens.body,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          _SeatStepButton(
            icon: Icons.remove_rounded,
            tooltip: minusLabel,
            onPressed: onMinus,
          ),
          SizedBox(
            width: LayoutTokens.gr5,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlowCondensed(
                color: lethal ? colors.error : colors.textPrimary,
                fontSize: FontTokens.headline,
                fontWeight: FontWeight.w600,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _SeatStepButton(
            icon: Icons.add_rounded,
            tooltip: plusLabel,
            onPressed: onPlus,
          ),
        ],
      ),
    );
  }
}

class _SeatStepButton extends StatelessWidget {
  const _SeatStepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: LayoutTokens.minTapTarget,
        height: LayoutTokens.minTapTarget,
      ),
      onPressed: () {
        context.gameHapticLight();
        onPressed();
      },
      icon: Icon(icon, size: 22, color: colors.primaryAccent),
    );
  }
}

class _SeatActionRow extends StatelessWidget {
  const _SeatActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.color,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final ink = color ?? colors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: LayoutTokens.minTapTarget,
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? colors.primaryAccent),
            const SizedBox(width: LayoutTokens.gr2),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lato(
                  color: ink,
                  fontSize: FontTokens.body,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: LayoutTokens.gr2),
              Flexible(
                child: Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.lato(
                    color: colors.textSecondary,
                    fontSize: FontTokens.hudSm,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CenterHub extends StatelessWidget {
  const _CenterHub({required this.size, required this.onOpen});

  final double size;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    // Avoid Tooltip here — long-press/tap races on the center hub crash
    // RawTooltipState (SingleTickerProvider) in debug on this screen.
    return Semantics(
      button: true,
      label: l10n.oneViewTableMenu,
      child: Material(
        color: colors.surfaceElevated,
        elevation: 2,
        shadowColor: const Color(0x66000000),
        shape: CircleBorder(
          side: BorderSide(
            color: colors.primaryAccent.withValues(
              alpha: OpacityTokens.moderate,
            ),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onOpen,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: colors.primaryAccent,
              size: size * 0.44,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatLayout extends StatelessWidget {
  const _SeatLayout({
    required this.seats,
    required this.layout,
    required this.teamsEnabled,
    required this.cardKeys,
    required this.onSeatTap,
    required this.onLifeDelta,
  });

  final List<OneViewSeat> seats;
  final OneViewSeatLayout layout;
  final bool teamsEnabled;
  final List<GlobalKey> cardKeys;
  final ValueChanged<int> onSeatTap;
  final void Function(int index, int delta) onLifeDelta;

  @override
  Widget build(BuildContext context) {
    final split =
        layout.fits(seats.length)
            ? layout.split
            : OneViewSeatLayout.defaultFor(seats.length).split;
    return buildOneViewSeatSplit(
      split: split,
      tile:
          (i, upsideDown) => _SeatTile(
            seat: seats[i],
            cardKey: cardKeys[i],
            upsideDown: upsideDown,
            teamsEnabled: teamsEnabled,
            onTap: () => onSeatTap(i),
            onLifeDelta: (d) => onLifeDelta(i, d),
          ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.seat,
    required this.cardKey,
    required this.upsideDown,
    required this.teamsEnabled,
    required this.onTap,
    required this.onLifeDelta,
  });

  final OneViewSeat seat;
  final GlobalKey cardKey;
  final bool upsideDown;
  final bool teamsEnabled;
  final VoidCallback onTap;
  final ValueChanged<int> onLifeDelta;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final hasArt =
        seat.commanderImageUrl != null && seat.commanderImageUrl!.isNotEmpty;
    final child = Padding(
      padding: const EdgeInsets.all(LayoutTokens.gr0),
      child: Material(
        key: cardKey,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RadiusTokens.radiusBento,
          side: BorderSide(color: colors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                if (hasArt) _SeatArt(url: seat.commanderImageUrl!),
                if (seat.isEmpty)
                  InkWell(
                    onTap: onTap,
                    child: _EmptySeat(
                      label: l10n.oneViewEmptySeat,
                      maxWidth: constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                    ),
                  )
                else
                  _ClaimedSeat(
                    seat: seat,
                    teamsEnabled: teamsEnabled,
                    maxWidth: constraints.maxWidth,
                    maxHeight: constraints.maxHeight,
                    onLifeDelta: onLifeDelta,
                    onOpenTools: onTap,
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (!upsideDown) return child;
    return RotatedBox(quarterTurns: 2, child: child);
  }
}

/// Commander or card art, with a light veil so the name, life total,
/// and − / + edges stay readable without hiding the picture.
class _SeatArt extends StatelessWidget {
  const _SeatArt({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final veil = AppColorTokens.of(context).surface;
    final cacheW = (MediaQuery.sizeOf(context).shortestSide *
            MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(320, 720);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            memCacheWidth: cacheW,
            fadeInDuration: const Duration(milliseconds: 150),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.05,
                colors: [
                  veil.withValues(alpha: 0.90),
                  veil.withValues(alpha: 0.52),
                  veil.withValues(alpha: 0.36),
                ],
                stops: const [0.0, 0.42, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _asSentence(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

/// Quiet sit prompt: a small brand badge and a two-line label, centered.
class _EmptySeat extends StatelessWidget {
  const _EmptySeat({
    required this.label,
    required this.maxWidth,
    required this.maxHeight,
  });

  final String label;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final compact = maxWidth < 150 || maxHeight < 150;
    final badge = compact ? 48.0 : 72.0;
    final parts = label.split(' — ');
    final title = parts.first;
    final hint = parts.length > 1 ? _asSentence(parts[1]) : null;
    final titleStyle = GoogleFonts.lato(
      color: colors.textSecondary,
      fontSize: compact ? FontTokens.body : FontTokens.headline,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    final hintStyle = GoogleFonts.lato(
      color: colors.textSecondary,
      fontSize: compact ? FontTokens.hudSm : FontTokens.body,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gr2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primaryAccent.withValues(
                  alpha: OpacityTokens.faint,
                ),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: badge,
                height: badge,
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: colors.primaryAccent,
                  size: badge * 0.46,
                ),
              ),
            ),
            SizedBox(height: compact ? LayoutTokens.gr0 : LayoutTokens.gr2),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
            if (hint != null) ...[
              const SizedBox(height: LayoutTokens.gr1),
              Text(
                hint,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: hintStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Name, life total, and steppers. The card stays still; only the number moves.
class _ClaimedSeat extends StatefulWidget {
  const _ClaimedSeat({
    required this.seat,
    required this.teamsEnabled,
    required this.maxWidth,
    required this.maxHeight,
    required this.onLifeDelta,
    required this.onOpenTools,
  });

  final OneViewSeat seat;
  final bool teamsEnabled;
  final double maxWidth;
  final double maxHeight;
  final ValueChanged<int> onLifeDelta;
  final VoidCallback onOpenTools;

  @override
  State<_ClaimedSeat> createState() => _ClaimedSeatState();
}

class _ClaimedSeatState extends State<_ClaimedSeat>
    with TickerProviderStateMixin {
  late final AnimationController _deltaAnim;
  late final Animation<double> _deltaFade;
  late final Animation<Offset> _deltaSlide;
  late final AnimationController _bump;
  late final Animation<double> _bumpScale;
  late final AnimationController _danger;
  late final Animation<double> _dangerScale;

  int? _lastDelta;
  Timer? _holdTimer;
  var _holding = false;

  @override
  void initState() {
    super.initState();
    _deltaAnim = AnimationController(
      vsync: this,
      duration: MotionTokens.lifeDelta,
    );
    const holdThenMove = Interval(0.5, 1.0, curve: Curves.easeOut);
    _deltaFade = CurvedAnimation(parent: _deltaAnim, curve: holdThenMove);
    _deltaSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -1.4),
    ).animate(CurvedAnimation(parent: _deltaAnim, curve: holdThenMove));
    _bump = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _bumpScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 60,
      ),
    ]).animate(_bump);
    _bump.addStatusListener((status) {
      if (status == AnimationStatus.completed) _syncDanger();
    });
    _danger = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _dangerScale = Tween<double>(
      begin: 1.0,
      end: 1.045,
    ).animate(CurvedAnimation(parent: _danger, curve: Curves.easeInOut));
    _syncDanger();
  }

  @override
  void didUpdateWidget(covariant _ClaimedSeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    final delta = widget.seat.life - oldWidget.seat.life;
    if (delta != 0) {
      _noteDelta(delta);
      _playBump();
    } else {
      _syncDanger();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _deltaAnim.dispose();
    _bump.dispose();
    _danger.dispose();
    super.dispose();
  }

  void _noteDelta(int delta) {
    final coalesce =
        _lastDelta != null &&
        (_holding ||
            (_deltaAnim.status != AnimationStatus.dismissed &&
                _deltaAnim.value < 1.0));
    // Already rebuilding from the life change. setState here is illegal.
    _lastDelta = coalesce ? _lastDelta! + delta : delta;
    if (_holding) {
      _deltaAnim.stop();
      _deltaAnim.value = 0;
    } else {
      _deltaAnim.forward(from: 0);
    }
  }

  void _playBump() {
    _danger.stop();
    _danger.value = 0;
    _bump.forward(from: 0);
  }

  void _syncDanger() {
    if (!mounted) return;
    if (widget.seat.life > 10) {
      _danger.stop();
      _danger.value = 0;
      return;
    }
    if (_bump.isAnimating) return;
    if (!_danger.isAnimating) _danger.repeat(reverse: true);
  }

  void _startHold(int direction) {
    _holding = true;
    _holdTimer?.cancel();
    _holdTimer = Timer(MotionTokens.lifeHoldStep, () {
      if (!_holding || !mounted) return;
      widget.onLifeDelta(direction * 5);
      context.gameHapticLight();
      _holdTimer = Timer.periodic(MotionTokens.lifeHoldStep, (_) {
        if (!_holding || !mounted) {
          _holdTimer?.cancel();
          return;
        }
        widget.onLifeDelta(direction * 5);
        context.gameHapticLight();
      });
    });
  }

  void _stopHold() {
    final wasHolding = _holding;
    _holding = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (wasHolding && _lastDelta != null && mounted) {
      _deltaAnim.forward(from: 0);
    }
  }

  Future<void> _showNumberPad() async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => LifeInputDialog(currentLife: widget.seat.life),
    );
    if (result == null || !mounted) return;
    final delta = result - widget.seat.life;
    if (delta != 0) widget.onLifeDelta(delta);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final seat = widget.seat;
    final tall = oneViewSeatIsTall(widget.maxWidth, widget.maxHeight);
    final band = oneViewLifeBand(
      tall: tall,
      maxWidth: widget.maxWidth,
      maxHeight: widget.maxHeight,
    );
    final shortSide = math.min(widget.maxWidth, widget.maxHeight);
    final nameSize = (shortSide * 0.11).clamp(12.0, FontTokens.headline);
    final clusterWidth = math.max(
      48.0,
      tall ? widget.maxWidth - LayoutTokens.gr3 : widget.maxWidth - band * 2,
    );
    final freeHeight = math.max(32.0, widget.maxHeight - (tall ? band * 2 : 0));
    final lifeSize = (math.min(clusterWidth, freeHeight) * 0.52).clamp(
      32.0,
      120.0,
    );
    final lifeColor =
        seat.life <= 5
            ? colors.error
            : seat.life <= 10
            ? colors.emphasis
            : colors.textPrimary;
    final lifeStyle = GoogleFonts.barlowCondensed(
      color: lifeColor,
      fontSize: lifeSize,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 0.9,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final showTeam = widget.teamsEnabled && seat.teamIndex > 0;
    final dot = (nameSize * 0.75).clamp(10.0, 16.0);
    final statusParts = <String>[
      if (seat.poison > 0) l10n.oneViewPoisonCount(seat.poison),
      if (seat.commanderDamageTotal > 0)
        l10n.oneViewCommanderDamageCount(seat.commanderDamageTotal),
    ];
    final iconSize = (band * 0.46).clamp(22.0, 28.0);
    final decrease = _LifeStepStrip(
      icon: Icons.remove_rounded,
      label: l10n.lifeA11yDecrease,
      vertical: tall,
      extent: band,
      iconSize: iconSize,
      onTap: () => widget.onLifeDelta(-1),
      onHoldStart: () => _startHold(-1),
      onHoldEnd: _stopHold,
    );
    final increase = _LifeStepStrip(
      icon: Icons.add_rounded,
      label: l10n.lifeA11yIncrease,
      vertical: tall,
      extent: band,
      iconSize: iconSize,
      onTap: () => widget.onLifeDelta(1),
      onHoldStart: () => _startHold(1),
      onHoldEnd: _stopHold,
    );
    final deltaSize = (lifeSize * 0.28).clamp(16.0, 28.0);
    final cluster = _LifeGesture(
      tall: tall,
      onLifeDelta: widget.onLifeDelta,
      onOpenTools: widget.onOpenTools,
      onDoubleTap: _showNumberPad,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: clusterWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LayoutTokens.gr2,
              vertical: LayoutTokens.gr1,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showTeam) ...[
                      Container(
                        width: dot,
                        height: dot,
                        decoration: BoxDecoration(
                          color: teamColor(seat.teamIndex),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: LayoutTokens.gr1),
                    ],
                    Flexible(
                      child: Text(
                        seat.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lato(
                          color: colors.textPrimary,
                          fontSize: nameSize,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: shortSide < 150 ? 4 : LayoutTokens.gr1),
                Semantics(
                  label: l10n.lifeA11yLifeTotal('${seat.life}'),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: Listenable.merge([_bump, _danger]),
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _bumpScale.value * _dangerScale.value,
                            child: child,
                          );
                        },
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('${seat.life}', style: lifeStyle),
                        ),
                      ),
                      if (_lastDelta != null)
                        IgnorePointer(
                          child: FadeTransition(
                            opacity: Tween(
                              begin: 1.0,
                              end: 0.0,
                            ).animate(_deltaFade),
                            child: SlideTransition(
                              position: _deltaSlide,
                              child: Transform.translate(
                                offset: Offset(0, -(lifeSize * 0.55)),
                                child: Text(
                                  _lastDelta! > 0
                                      ? '+$_lastDelta'
                                      : '$_lastDelta',
                                  style: GoogleFonts.barlowCondensed(
                                    color:
                                        _lastDelta! > 0
                                            ? colors.success
                                            : colors.error,
                                    fontSize: deltaSize,
                                    fontWeight: FontWeight.w700,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (statusParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    statusParts.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(
                      color: colors.emphasis,
                      fontSize: (nameSize - 2).clamp(11.0, FontTokens.hudSm),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (tall) {
      return Column(children: [increase, Expanded(child: cluster), decrease]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [decrease, Expanded(child: cluster), increase],
    );
  }
}

/// Swipe toward + gains life. Swipe toward − loses it.
/// Tall seats swipe vertically. Wide seats swipe horizontally.
/// A long-press opens seat tools. A double-tap opens the keypad.
class _LifeGesture extends StatefulWidget {
  const _LifeGesture({
    required this.tall,
    required this.onLifeDelta,
    required this.onOpenTools,
    required this.onDoubleTap,
    required this.child,
  });

  final bool tall;
  final ValueChanged<int> onLifeDelta;
  final VoidCallback onOpenTools;
  final VoidCallback onDoubleTap;
  final Widget child;

  @override
  State<_LifeGesture> createState() => _LifeGestureState();
}

class _LifeGestureState extends State<_LifeGesture> {
  static const double _stride = 36;

  double _accum = 0;
  int _applied = 0;
  Offset? _lastGlobal;

  void _start() {
    _accum = 0;
    _applied = 0;
    _lastGlobal = null;
  }

  void _drag(DragUpdateDetails details) {
    _lastGlobal = details.globalPosition;
    final delta = widget.tall ? -details.delta.dy : details.delta.dx;
    _accum += delta;
    while (_accum >= _stride) {
      _accum -= _stride;
      _applied += 1;
      widget.onLifeDelta(1);
      context.gameHapticLight();
    }
    while (_accum <= -_stride) {
      _accum += _stride;
      _applied -= 1;
      widget.onLifeDelta(-1);
      context.gameHapticLight();
    }
  }

  /// A drag that leaves the card is an attack, not a life swipe.
  /// Put back the life this gesture already changed.
  void _end() {
    final applied = _applied;
    final global = _lastGlobal;
    _accum = 0;
    _applied = 0;
    _lastGlobal = null;
    if (!mounted || applied == 0 || global == null) return;
    if (!_attackSwipeEnabled() || _onCard(global)) return;
    widget.onLifeDelta(-applied);
  }

  bool _attackSwipeEnabled() {
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(oneViewProvider).config.attackSwipeEnabled;
    } on StateError {
      return false;
    }
  }

  bool _onCard(Offset global) {
    RenderBox? box;
    context.visitAncestorElements((ancestor) {
      if (ancestor.widget is Material) {
        final render = ancestor.renderObject;
        if (render is RenderBox && render.hasSize) box = render;
        return false;
      }
      return true;
    });
    final card = box;
    if (card == null || !card.attached) return true;
    final local = card.globalToLocal(global);
    return (Offset.zero & card.size).inflate(LayoutTokens.gr0).contains(local);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      hint: l10n.oneViewSeatTools,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: widget.onOpenTools,
        onDoubleTap: widget.onDoubleTap,
        onVerticalDragStart: widget.tall ? (_) => _start() : null,
        onVerticalDragUpdate: widget.tall ? _drag : null,
        onVerticalDragEnd: widget.tall ? (_) => _end() : null,
        onVerticalDragCancel: widget.tall ? _end : null,
        onHorizontalDragStart: widget.tall ? null : (_) => _start(),
        onHorizontalDragUpdate: widget.tall ? null : _drag,
        onHorizontalDragEnd: widget.tall ? null : (_) => _end(),
        onHorizontalDragCancel: widget.tall ? null : _end,
        child: widget.child,
      ),
    );
  }
}

/// Flat − / + band. Same press treatment as the Own View life counter.
/// A tap steps by 1. A hold steps by 5.
class _LifeStepStrip extends StatefulWidget {
  const _LifeStepStrip({
    required this.icon,
    required this.label,
    required this.vertical,
    required this.extent,
    required this.iconSize,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final IconData icon;
  final String label;
  final bool vertical;
  final double extent;
  final double iconSize;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  State<_LifeStepStrip> createState() => _LifeStepStripState();
}

class _LifeStepStripState extends State<_LifeStepStrip> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: () {
          context.gameHapticLight();
          widget.onTap();
        },
        onLongPressStart: (_) {
          _setPressed(true);
          widget.onHoldStart();
        },
        onLongPressEnd: (_) {
          _setPressed(false);
          widget.onHoldEnd();
        },
        onLongPressCancel: () {
          _setPressed(false);
          widget.onHoldEnd();
        },
        child: AnimatedContainer(
          duration: MotionTokens.fast,
          curve: Curves.easeOut,
          alignment: Alignment.center,
          width: widget.vertical ? double.infinity : widget.extent,
          height: widget.vertical ? widget.extent : null,
          color:
              _pressed
                  ? colors.primaryAccent.withValues(alpha: OpacityTokens.soft)
                  : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: colors.primaryAccent,
          ),
        ),
      ),
    );
  }
}

class _SitCodeScannerPage extends StatefulWidget {
  const _SitCodeScannerPage();

  @override
  State<_SitCodeScannerPage> createState() => _SitCodeScannerPageState();
}

class _SitCodeScannerPageState extends State<_SitCodeScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: Text(l10n.oneViewScanSitCode),
        backgroundColor: colors.backgroundPrimary,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw == null) continue;
            final parsed = OneViewSitCode.parse(raw);
            if (parsed == null) continue;
            _handled = true;
            Navigator.pop(context, parsed);
            return;
          }
        },
      ),
    );
  }
}

/// Shows the local profile sit code QR (Profile → Show sit code).
Future<void> showOneViewSitCodeSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final profile = ref.read(profileRepositoryProvider).getProfile();
  final l10n = AppLocalizations.of(context);
  final colors = AppColorTokens.of(context);
  if (profile == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.hostCreateProfileFirst)));
    return;
  }
  final payload = OneViewSitCode.build(
    playerId: profile.playerId,
    username: profile.username,
    avatarUrl: profile.profileAvatarImageUrl,
  );
  await showGameBottomSheet<void>(
    context: context,
    builder: (ctx) {
      return GameSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GameSheetHeader(title: l10n.oneViewShowSitCode),
            SizedBox(height: LayoutTokens.gr2),
            Text(
              l10n.oneViewShowSitCodeBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            SizedBox(height: LayoutTokens.gr3),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: RadiusTokens.radiusXl,
              ),
              child: QrImageView(
                data: payload,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            SizedBox(height: LayoutTokens.gr2),
            Text(
              profile.username,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    },
  );
}
