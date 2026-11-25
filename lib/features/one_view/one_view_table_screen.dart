import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/game/game_constants.dart';
import '../../core/game/game_format.dart';
import '../../core/game/game_session_events.dart';
import '../../core/game/progression_service.dart';
import '../../core/one_view/one_view_keyboard.dart';
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
import 'one_view_qr_scanner.dart';
import 'one_view_chrome.dart';

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
  ({int from, List<int> targets, bool faceDown})? _attack;
  int? _dragPointer;
  int? _dragFrom;
  Offset? _dragOrigin;
  final List<int?> _dragSamples = [];
  int? _dragHover;
  final Set<int> _dragReached = <int>{};
  Size? _displaySize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    unawaited(OneViewKeyboardLayout.hold());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _applyTableOrientation(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    unawaited(OneViewKeyboardLayout.release());
    OneViewOrientation.restoreAppDefault();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    // The keyboard changes window insets, not the physical display.
    // Re-locking orientation on that callback shifts the seats.
    final display = View.of(context).display.size;
    final previous = _displaySize;
    _displaySize = display;
    if (previous != null &&
        previous.width == display.width &&
        previous.height == display.height) {
      return;
    }
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
    return 48;
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    final leave = await showOneViewDialog<bool>(
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
    return showOneViewDialog<({String? winnerPlayerId})>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return OneViewMenuDialog(
          title: l10n.oneViewPickWinnerTitle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.oneViewPickWinnerBody,
                style: OneViewChrome.dialogBodyStyle(ctx),
              ),
              const SizedBox(height: 12),
              for (final seat in claimed)
                OneViewMenuAction(
                  icon: Icons.person_outline_rounded,
                  leading: OneViewPortrait(url: seat.cardArtUrl, size: 36),
                  label: seat.displayName,
                  onTap:
                      () => Navigator.pop(ctx, (winnerPlayerId: seat.playerId)),
                ),
              const Divider(height: 24),
              OneViewMenuAction(
                icon: Icons.remove_rounded,
                label: l10n.oneViewPickWinnerSkip,
                onTap: () => Navigator.pop(ctx, (winnerPlayerId: null)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.commonCancel),
              ),
            ],
          ),
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
    _dragPointer = null;
    _dragFrom = null;
    _dragOrigin = null;
    _dragSamples.clear();
    _dragHover = null;
    _dragReached.clear();
  }

  void _onTablePointerDown(PointerDownEvent event) {
    // One finger owns the slide. A second finger on a shared phone must not
    // steal it or start a second attack.
    if (_dragPointer != null) return;
    final table = ref.read(oneViewProvider);
    if (!table.config.attackSwipeEnabled ||
        _attack != null ||
        _diceAnnouncement != null) {
      return;
    }
    _dragPointer = event.pointer;
    _dragOrigin = event.position;
    _dragFrom = _seatAt(event.position, centerOnly: true);
  }

  void _onTablePointerMove(PointerMoveEvent event) {
    if (event.pointer != _dragPointer) return;
    final from = _dragFrom;
    final origin = _dragOrigin;
    if (from == null || origin == null || _attack != null) return;
    final traveled =
        (event.position - origin).distance >= oneViewAttackMinTravel;
    if (!traveled && _dragSamples.isEmpty) return;
    final seat = _seatAt(event.position, centerOnly: false);
    if (traveled) _dragSamples.add(seat);
    final hover = _opponentSeat(seat, from);
    final entered = hover != null && !_dragReached.contains(hover);
    if (hover == _dragHover && !entered) return;
    setState(() {
      _dragHover = hover;
      if (hover != null) _dragReached.add(hover);
    });
    if (entered) context.gameHapticSelection();
  }

  /// A claimed opponent. The attacker's own card and empty seats stay plain.
  int? _opponentSeat(int? seat, int from) {
    if (seat == null || seat == from) return null;
    final seats = ref.read(oneViewProvider).seats;
    if (seat < 0 || seat >= seats.length || !seats[seat].isClaimed) {
      return null;
    }
    return seat;
  }

  void _onTablePointerUp(PointerUpEvent event) {
    if (event.pointer != _dragPointer) return;
    final from = _dragFrom;
    final origin = _dragOrigin;
    final samples = List<int?>.of(_dragSamples);
    final marked = _dragHover != null || _dragReached.isNotEmpty;
    _clearAttackDrag();
    void settle() {
      if (marked && mounted) setState(() {});
    }

    if (from == null || origin == null || _attack != null) {
      settle();
      return;
    }
    final table = ref.read(oneViewProvider);
    final seats = table.seats;
    if (from >= seats.length || !seats[from].isClaimed) {
      settle();
      return;
    }
    final traveled =
        (event.position - origin).distance >= oneViewAttackMinTravel;
    final release = _seatAt(
      event.position,
      centerOnly: false,
      includeEmpty: true,
    );
    bool claimed(int index) => seats[index].isClaimed;
    // Samples exist only after the finger has already traveled far enough.
    // Ending back on your own card must still count the players you crossed.
    final alongThePath = oneViewAttackTargets(
      from: from,
      samples: samples,
      seatCount: seats.length,
      isClaimed: claimed,
    );
    if (!traveled && alongThePath.isEmpty) {
      settle();
      return;
    }
    final targets = oneViewAttackTargets(
      from: from,
      samples: [...samples, release],
      seatCount: seats.length,
      isClaimed: claimed,
    );
    if (targets.isEmpty) {
      if (release != null && seats[release].isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).oneViewAttackNeedsPlayer,
              ),
              duration: const Duration(seconds: 2),
            ),
          );
      }
      settle();
      return;
    }
    final layout =
        table.layout.fits(seats.length)
            ? table.layout
            : OneViewSeatLayout.defaultFor(seats.length);
    setState(
      () =>
          _attack = (
            from: from,
            targets: targets,
            faceDown: oneViewSeatUpsideDown(layout.split, from),
          ),
    );
  }

  void _onTablePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _dragPointer) return;
    final marked = _dragHover != null || _dragReached.isNotEmpty;
    _clearAttackDrag();
    if (marked && mounted) setState(() {});
  }

  /// [centerOnly] keeps the drag off the − / + bands. The release can land
  /// anywhere on the other card.
  int? _seatAt(
    Offset global, {
    required bool centerOnly,
    bool includeEmpty = false,
  }) {
    final seats = ref.read(oneViewProvider).seats;
    final count = math.min(seats.length, _seatCardKeys.length);
    for (var i = 0; i < count; i++) {
      if (!includeEmpty && !seats[i].isClaimed) continue;
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
      // The activity keeps its size while this route is open. Menus lift
      // themselves. The table must not reflow when the keyboard appears.
      resizeToAvoidBottomInset: false,
      // Inset seats from status / nav / cutout so +/- and life never sit
      // under system chrome. No reserved tool bar — only system SafeArea.
      body: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: SafeArea(
          maintainBottomViewPadding: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                onPointerDown: _onTablePointerDown,
                onPointerMove: _onTablePointerMove,
                onPointerUp: _onTablePointerUp,
                onPointerCancel: _onTablePointerCancel,
                child: _SeatLayout(
                  seats: state.seats,
                  layout: state.layout,
                  teamsEnabled: state.config.teamsEnabled,
                  cardKeys: _seatCardKeys,
                  attackHover: _dragHover,
                  attackReached: _dragReached,
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
                    defenderIndexes: _attack!.targets,
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
    await showOneViewDialog<void>(
      context: context,
      builder: (ctx) {
        return OneViewMenuDialog(
          title: l10n.oneViewClaimSeatTitle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OneViewMenuAction(
                icon: Icons.person_rounded,
                label: l10n.oneViewSitAsMe,
                subtitle:
                    ref.read(profileRepositoryProvider).getProfile() == null
                        ? l10n.oneViewSitAsMeSubtitle
                        : l10n.oneViewUseProfile(
                          ref
                              .read(profileRepositoryProvider)
                              .getProfile()!
                              .username,
                        ),
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
                },
              ),
              OneViewMenuAction(
                icon: Icons.qr_code_scanner_rounded,
                label: l10n.oneViewLoadViaQr,
                subtitle: l10n.oneViewLoadViaQrSubtitle,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _scanSitCode(seatIndex);
                },
              ),
              OneViewMenuAction(
                icon: Icons.person_outline_rounded,
                label: l10n.oneViewSitAsGuest,
                subtitle: l10n.oneViewSitAsGuestSubtitle,
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
    final name = await showOneViewDialog<String>(
      context: context,
      builder: (ctx) {
        return OneViewFormDialog(
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
  }

  Future<void> _renameSeat(int seatIndex, {required bool faceDown}) async {
    final l10n = AppLocalizations.of(context);
    final seat = ref.read(oneViewProvider).seats[seatIndex];
    if (seat.isEmpty) return;
    final controller = TextEditingController(text: seat.displayName);
    final name = await showOneViewDialog<String>(
      context: context,
      builder: (ctx) {
        return RotatedBox(
          quarterTurns: faceDown ? 2 : 0,
          child: OneViewFormDialog(
            title: l10n.oneViewRename,
            submitLabel: l10n.commonSave,
            onSubmit: () => Navigator.pop(ctx, controller.text),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: l10n.oneViewRenameHint),
              onSubmitted: (value) => Navigator.pop(ctx, value),
            ),
          ),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (!mounted || name == null) return;
    await ref.read(oneViewProvider.notifier).renameSeat(seatIndex, name);
  }

  Future<void> _scanSitCode(int seatIndex) async {
    final l10n = AppLocalizations.of(context);
    final parsed = await Navigator.of(
      context,
    ).push<({String playerId, String username, String? avatarUrl})>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder:
            (_) => OneViewQrScanner<
              ({String playerId, String username, String? avatarUrl})
            >(
              title: l10n.oneViewScanSitCode,
              hint: l10n.oneViewScanProfileHint,
              invalidMessage: l10n.oneViewInvalidProfileQr,
              parse: OneViewSitCode.parse,
            ),
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
    // Local decks belong to this phone's profile. Another player's code
    // already brought their photo.
    final localId = ref.read(profileRepositoryProvider).getProfile()?.playerId;
    final seatedId = ref.read(oneViewProvider).seats[seatIndex].playerId;
    if (localId != null && seatedId == localId && mounted) {
      await showOneViewDeckPicker(context, ref, seatIndex);
    }
  }

  Future<void> _showSeatTools(int index, OneViewSeat seat) async {
    final l10n = AppLocalizations.of(context);
    final table = ref.read(oneViewProvider);
    final layout =
        table.layout.fits(table.seats.length)
            ? table.layout
            : OneViewSeatLayout.defaultFor(table.seats.length);
    final faceDown = oneViewSeatUpsideDown(layout.split, index);
    await showOneViewDialog<void>(
      context: context,
      builder: (ctx) {
        return RotatedBox(
          quarterTurns: faceDown ? 2 : 0,
          child: Consumer(
            builder: (context, ref, _) {
              final live = ref.watch(
                oneViewProvider.select(
                  (s) => s.seats.firstWhere((x) => x.index == index),
                ),
              );
              final allSeats = ref.watch(
                oneViewProvider.select((s) => s.seats),
              );
              final colors = AppColorTokens.of(context);
              final notifier = ref.read(oneViewProvider.notifier);
              final others = allSeats.where(
                (s) => s.index != index && s.isClaimed,
              );
              return OneViewMenuDialog(
                maxWidth: 560,
                titleWidget: Text(
                  live.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OneViewChrome.dialogTitleStyle(context),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    const SizedBox(height: LayoutTokens.gr4),
                    _SeatMenuLabel(l10n.oneViewCommanderDamageLabel),
                    if (others.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: LayoutTokens.gr1,
                          bottom: LayoutTokens.gr2,
                        ),
                        child: Text(
                          l10n.oneViewCommanderDamageEmpty,
                          style: OneViewChrome.dialogBodyStyle(context),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              allSeats.length >= 5
                                  ? math.min(
                                    216,
                                    MediaQuery.sizeOf(context).height * 0.3,
                                  )
                                  : double.infinity,
                        ),
                        child: SingleChildScrollView(
                          primary: false,
                          child: Column(
                            children: [
                              for (final from in others)
                                _SeatCounterRow(
                                  label: from.displayName,
                                  portraitUrl: from.cardArtUrl,
                                  showPortrait: true,
                                  value:
                                      live.commanderDamageFrom[from.index] ?? 0,
                                  lethal:
                                      (live.commanderDamageFrom[from.index] ??
                                          0) >=
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
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: LayoutTokens.gr3),
                    _SeatMenuLabel(l10n.oneViewMenuSeat),
                    OneViewMenuAction(
                      icon: Icons.edit_outlined,
                      label: l10n.oneViewRename,
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _renameSeat(index, faceDown: faceDown);
                      },
                    ),
                    OneViewMenuAction(
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
                      OneViewMenuAction(
                        icon: Icons.style_outlined,
                        label: l10n.oneViewChangeDeck,
                        onTap: () async {
                          Navigator.pop(ctx);
                          await showOneViewDeckPicker(context, ref, index);
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: LayoutTokens.gr2,
                      ),
                      child: Divider(height: 1, color: colors.borderSubtle),
                    ),
                    OneViewMenuAction(
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
          ),
        );
      },
    );
  }

  Future<void> _showHubMenu(AppLocalizations l10n) async {
    final colors = AppColorTokens.of(context);
    await showOneViewDialog<void>(
      context: context,
      builder: (ctx) {
        final landscape =
            MediaQuery.sizeOf(ctx).width > MediaQuery.sizeOf(ctx).height;
        Widget action({
          required IconData icon,
          required String label,
          required VoidCallback onTap,
          Color? color,
        }) {
          return OneViewMenuAction(
            icon: icon,
            label: label,
            onTap: onTap,
            color: color,
          );
        }

        final entries = <Widget>[
          action(
            icon: Icons.casino_rounded,
            label: l10n.tableToolsTitle,
            onTap: () async {
              Navigator.pop(ctx);
              final profile = ref.read(profileRepositoryProvider).getProfile();
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
            action(
              icon: Icons.palette_rounded,
              label: l10n.oneViewColorsTitle,
              onTap: () async {
                Navigator.pop(ctx);
                await showOneViewColorsSheet(context, ref);
              },
            ),
          action(
            icon: Icons.tune_rounded,
            label: l10n.oneViewMidGameSettings,
            onTap: () async {
              Navigator.pop(ctx);
              await showOneViewSettingsSheet(context, ref);
            },
          ),
          action(
            icon: Icons.groups_rounded,
            label: l10n.oneViewPlayerCountTitle,
            onTap: () async {
              Navigator.pop(ctx);
              await showOneViewPlayerCountSheet(context, ref);
            },
          ),
          action(
            icon: Icons.grid_view_rounded,
            label: l10n.oneViewLayoutTitle,
            onTap: () async {
              Navigator.pop(ctx);
              await showOneViewLayoutPicker(context, ref);
            },
          ),
        ];
        final resetLife = action(
          icon: Icons.restart_alt_rounded,
          label: l10n.oneViewResetLife,
          onTap: () async {
            Navigator.pop(ctx);
            final confirmed = await showOneViewDialog<bool>(
              context: context,
              builder:
                  (dialogContext) => OneViewFormDialog(
                    title: l10n.oneViewResetLife,
                    submitLabel: l10n.oneViewResetLife,
                    onSubmit: () => Navigator.pop(dialogContext, true),
                    content: Text(
                      l10n.oneViewResetLifeBody(
                        ref.read(oneViewProvider).config.startingLife,
                      ),
                      style: OneViewChrome.dialogBodyStyle(dialogContext),
                    ),
                  ),
            );
            if (confirmed == true && mounted) {
              ref.read(oneViewProvider.notifier).resetLifeTotals();
            }
          },
        );
        final endTable = action(
          icon: Icons.exit_to_app_rounded,
          label: l10n.oneViewEndTableConfirm,
          color: colors.error,
          onTap: () {
            Navigator.pop(ctx);
            _leave();
          },
        );

        const columnGap = SizedBox(width: LayoutTokens.gr3);
        const rowGap = SizedBox(height: LayoutTokens.gr2);
        final rule = Padding(
          padding: const EdgeInsets.symmetric(vertical: LayoutTokens.gr2),
          child: Divider(height: 1, color: colors.borderSubtle),
        );

        Widget body;
        if (landscape) {
          final rows = <Widget>[];
          for (var i = 0; i < entries.length; i += 2) {
            if (rows.isNotEmpty) rows.add(rowGap);
            final right = i + 1 < entries.length ? entries[i + 1] : null;
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: entries[i]),
                    columnGap,
                    Expanded(child: right ?? const SizedBox.shrink()),
                  ],
                ),
              ),
            );
          }
          body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [...rows, rule, resetLife, endTable],
          );
        } else {
          body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [...entries, rule, resetLife, endTable],
          );
        }

        return OneViewMenuDialog(title: l10n.oneViewTableMenu, child: body);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: LayoutTokens.gr1),
      child: Text(text, style: OneViewChrome.menuSectionStyle(context)),
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
    this.portraitUrl,
    this.showPortrait = false,
  });

  final String? portraitUrl;
  final bool showPortrait;
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          if (showPortrait) ...[
            OneViewPortrait(url: portraitUrl, size: 28),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: OneViewChrome.menuLabelStyle(context),
            ),
          ),
          const SizedBox(width: 8),
          _SeatStepButton(
            icon: Icons.remove_rounded,
            tooltip: minusLabel,
            onPressed: onMinus,
          ),
          const SizedBox(width: LayoutTokens.gr1),
          SizedBox(
            width: 48,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlowCondensed(
                color: lethal ? colors.error : colors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w600,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: LayoutTokens.gr1),
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
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: colors.primaryAccent.withValues(
          alpha: OpacityTokens.subtle,
        ),
        foregroundColor: colors.primaryAccent,
        fixedSize: const Size(48, 48),
        shape: const CircleBorder(),
      ),
      onPressed: () {
        context.gameHapticLight();
        onPressed();
      },
      icon: Icon(icon, size: 28, color: colors.primaryAccent),
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
              Icons.tune_rounded,
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
    required this.attackHover,
    required this.attackReached,
    required this.onSeatTap,
    required this.onLifeDelta,
  });

  final List<OneViewSeat> seats;
  final OneViewSeatLayout layout;
  final bool teamsEnabled;
  final List<GlobalKey> cardKeys;
  final int? attackHover;
  final Set<int> attackReached;
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
            attackHover: attackHover == i,
            attackReached: attackReached.contains(i),
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
    required this.attackHover,
    required this.attackReached,
    required this.onTap,
    required this.onLifeDelta,
  });

  final OneViewSeat seat;
  final GlobalKey cardKey;
  final bool upsideDown;
  final bool teamsEnabled;
  final bool attackHover;
  final bool attackReached;
  final VoidCallback onTap;
  final ValueChanged<int> onLifeDelta;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final artUrl = seat.cardArtUrl;
    final hover = attackHover && seat.isClaimed;
    final reached = attackReached && seat.isClaimed;
    final marked = hover || reached;
    final card = Padding(
      padding: const EdgeInsets.all(LayoutTokens.gr0),
      child: Material(
        key: cardKey,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RadiusTokens.radiusBento,
          side: BorderSide(
            color:
                hover
                    ? colors.primaryAccent
                    : reached
                    ? colors.primaryAccent.withValues(alpha: 0.7)
                    : colors.borderSubtle,
            width:
                hover
                    ? 3
                    : reached
                    ? 2
                    : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                if (artUrl != null) _SeatArt(url: artUrl),
                if (marked)
                  IgnorePointer(
                    child: ColoredBox(
                      color: colors.primaryAccent.withValues(
                        alpha:
                            hover
                                ? OpacityTokens.subtle
                                : OpacityTokens.subtle * 0.45,
                      ),
                    ),
                  ),
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
    final facing = upsideDown ? RotatedBox(quarterTurns: 2, child: card) : card;
    // Scale is paint-only. Hit testing stays on the card's real rect, so a
    // lifted card does not steal the next player's + or −.
    return TweenAnimationBuilder<double>(
      tween: Tween(
        end: hover && !MediaQuery.disableAnimationsOf(context) ? 1.04 : 1,
      ),
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : MotionTokens.standard,
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(
          key: ValueKey('one-view-attack-scale-${seat.index}'),
          scale: scale,
          alignment: Alignment.center,
          transformHitTests: false,
          child: child,
        );
      },
      child: facing,
    );
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
          OneViewArtImage(url: url, cacheWidth: cacheW),
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
    final badge = compact ? 36.0 : 48.0;
    final title = label;
    final titleStyle = GoogleFonts.lato(
      color: colors.textSecondary,
      fontSize: compact ? 14 : 16,
      fontWeight: FontWeight.w600,
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
  late final AnimationController _bump;
  late final Animation<double> _bumpScale;

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
  }

  @override
  void didUpdateWidget(covariant _ClaimedSeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    final delta = widget.seat.life - oldWidget.seat.life;
    if (delta != 0) {
      _noteDelta(delta);
      _playBump();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _deltaAnim.dispose();
    _bump.dispose();
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
    if (MediaQuery.disableAnimationsOf(context)) return;
    _bump.forward(from: 0);
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
    final result = await showOneViewDialog<int>(
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
    final lifeSize = math.min(
      (clusterWidth * 0.65).clamp(32.0, 120.0),
      // Header, status and padding have fixed space. The life total gets
      // everything else, including the space formerly reserved for a delta.
      math.max(24.0, (freeHeight - 88) / 0.9),
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
                Semantics(
                  button: true,
                  label: l10n.oneViewPlayerMenu(seat.displayName),
                  child: InkWell(
                    onTap: widget.onOpenTools,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
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
                          const SizedBox(width: 4),
                          Icon(
                            Icons.more_horiz_rounded,
                            size: 18,
                            color: colors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: shortSide < 150 ? 4 : LayoutTokens.gr1),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Semantics(
                          label: l10n.lifeA11yLifeTotal('${seat.life}'),
                          child: AnimatedBuilder(
                            animation: _bump,
                            builder:
                                (context, child) => Transform.scale(
                                  scale:
                                      MediaQuery.disableAnimationsOf(context)
                                          ? 1
                                          : _bumpScale.value,
                                  child: child,
                                ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('${seat.life}', style: lifeStyle),
                            ),
                          ),
                        ),
                      ),
                      if (_lastDelta != null)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: FadeTransition(
                              opacity: Tween(
                                begin: 1.0,
                                end: 0.0,
                              ).animate(_deltaFade),
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
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 20,
                  child: Text(
                    statusParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(
                      color: colors.emphasis,
                      fontSize: (nameSize - 2).clamp(12.0, 14.0),
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ),
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

/// Swipe up/down to change life in either orientation. Sideways swipes
/// remain available too. Crossing onto another seat is an attack.
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
  Offset? _lastGlobal;
  var _leftCard = false;
  Offset? _originLocal;
  Offset? _lastLocal;
  Axis? _axis;

  void _start(Offset local) {
    _cancel();
    _originLocal = local;
    _lastLocal = local;
  }

  void _cancel() {
    _accum = 0;
    _lastGlobal = null;
    _leftCard = false;
    _originLocal = null;
    _lastLocal = null;
    _axis = null;
  }

  void _drag(DragUpdateDetails details) {
    _lastGlobal = details.globalPosition;
    if (!_onCard(details.globalPosition)) _leftCard = true;
    final travel =
        details.localPosition - (_originLocal ?? details.localPosition);
    _axis ??=
        travel.dy.abs() >= travel.dx.abs() ? Axis.vertical : Axis.horizontal;
    final delta = details.localPosition - (_lastLocal ?? details.localPosition);
    _lastLocal = details.localPosition;
    _accum += _axis == Axis.vertical ? -delta.dy : delta.dx;
    // An attack slide crosses this card on the way out. Hold the steps until
    // the finger lifts, so life does not tick and then jump back.
    if (_attackSwipeEnabled()) return;
    _applyStride();
  }

  void _applyStride() {
    while (_accum >= _stride) {
      _accum -= _stride;
      widget.onLifeDelta(1);
      context.gameHapticLight();
    }
    while (_accum <= -_stride) {
      _accum += _stride;
      widget.onLifeDelta(-1);
      context.gameHapticLight();
    }
  }

  /// A drag that leaves the card is an attack. The − / + edges only count
  /// when the finger starts on them, so this center swipe changes life only
  /// if it ends on the same card.
  void _end() {
    final accum = _accum;
    final global = _lastGlobal;
    final leftCard = _leftCard;
    _cancel();
    if (!mounted || global == null || !_attackSwipeEnabled()) return;
    // Leaving the card, even if the finger comes back, is an attack slide.
    if (leftCard || !_onCard(global)) return;
    var steps = 0;
    var left = accum;
    while (left >= _stride) {
      left -= _stride;
      steps += 1;
    }
    while (left <= -_stride) {
      left += _stride;
      steps -= 1;
    }
    if (steps == 0) return;
    widget.onLifeDelta(steps);
    context.gameHapticLight();
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
    if (card == null || !card.attached) return false;
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
        onPanDown: (details) => _start(details.localPosition),
        onPanUpdate: _drag,
        onPanEnd: (_) => _end(),
        onPanCancel: _cancel,
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
