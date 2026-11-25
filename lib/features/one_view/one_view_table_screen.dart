import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/one_view/one_view_sit_code.dart';
import '../../core/one_view/one_view_state.dart';
import '../../core/persistence/providers.dart';
import '../../features/game/widgets/game_modal_chrome.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/app_router.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import 'one_view_deck_picker.dart';

/// Shared-phone tabletop: rotated seats, life +/- , claim, center tools.
class OneViewTableScreen extends ConsumerStatefulWidget {
  const OneViewTableScreen({super.key});

  @override
  ConsumerState<OneViewTableScreen> createState() => _OneViewTableScreenState();
}

class _OneViewTableScreenState extends ConsumerState<OneViewTableScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    // Prefer landscape for the shared table.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
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
    ref.read(oneViewProvider.notifier).reset();
    if (!mounted) return;
    context.go(AppRoutes.lobby);
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

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _SeatLayout(
                seats: state.seats,
                onSeatTap: (i) => _onSeatTap(i, state.seats[i]),
                onLifeDelta: (i, d) {
                  ref.read(oneViewProvider.notifier).adjustLife(i, d);
                },
              ),
            ),
            _CenterTools(
              onResetLife: () {
                ref.read(oneViewProvider.notifier).resetLifeTotals();
              },
              onAddSeat: () {
                ref.read(oneViewProvider.notifier).addSeats(1);
              },
              onMenu: () => _showMenu(l10n),
              onLeave: _leave,
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
      builder: (ctx) {
        return GameSheetBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GameSheetHeader(title: l10n.oneViewClaimSeatTitle),
              SizedBox(height: LayoutTokens.gr2),
              ListTile(
                leading: Icon(Icons.person_rounded, color: colors.primaryAccent),
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
            decoration: InputDecoration(hintText: l10n.oneViewGuestNameHint),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        );
      },
    );
    controller.dispose();
    if (!mounted) return;
    ref.read(oneViewProvider.notifier).claimAsGuest(seatIndex, name: name);
  }

  Future<void> _scanSitCode(int seatIndex) async {
    final l10n = AppLocalizations.of(context);
    final parsed = await Navigator.of(context).push<
      ({String playerId, String username, String? avatarUrl})
    >(
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
  }

  Future<void> _showSeatTools(int index, OneViewSeat seat) async {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final notifier = ref.read(oneViewProvider.notifier);
    await showGameBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return GameSheetBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GameSheetHeader(title: seat.displayName),
              SizedBox(height: LayoutTokens.gr2),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        notifier.adjustPoison(index, -1);
                      },
                      child: Text(l10n.oneViewPoisonMinus),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: LayoutTokens.gr2),
                    child: Text(
                      l10n.oneViewPoisonCount(seat.poison),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        notifier.adjustPoison(index, 1);
                      },
                      child: Text(l10n.oneViewPoisonPlus),
                    ),
                  ),
                ],
              ),
              SizedBox(height: LayoutTokens.gr2),
              if (!seat.isGuest)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.style),
                  title: Text(l10n.oneViewChangeDeck),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await showOneViewDeckPicker(context, ref, index);
                  },
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout_rounded, color: colors.error),
                title: Text(
                  l10n.oneViewClearSeat,
                  style: TextStyle(color: colors.error),
                ),
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
  }

  Future<void> _showMenu(AppLocalizations l10n) async {
    final colors = AppColorTokens.of(context);
    await showGameBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return GameSheetBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GameSheetHeader(title: l10n.oneViewTableMenu),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: Text(l10n.oneViewResetLife),
                onTap: () {
                  ref.read(oneViewProvider.notifier).resetLifeTotals();
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_rounded),
                title: Text(l10n.oneViewAddSeat),
                onTap: () {
                  ref.read(oneViewProvider.notifier).addSeats(1);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Icon(Icons.exit_to_app_rounded, color: colors.error),
                title: Text(
                  l10n.oneViewEndTableConfirm,
                  style: TextStyle(color: colors.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _leave();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CenterTools extends StatelessWidget {
  const _CenterTools({
    required this.onResetLife,
    required this.onAddSeat,
    required this.onMenu,
    required this.onLeave,
  });

  final VoidCallback onResetLife;
  final VoidCallback onAddSeat;
  final VoidCallback onMenu;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: colors.surface,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: LayoutTokens.gr2,
          vertical: LayoutTokens.gr1,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: l10n.oneViewResetLife,
              onPressed: onResetLife,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
            IconButton(
              tooltip: l10n.oneViewAddSeat,
              onPressed: onAddSeat,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
            const Spacer(),
            IconButton(
              tooltip: l10n.oneViewTableMenu,
              onPressed: onMenu,
              icon: const Icon(Icons.menu_rounded),
            ),
            IconButton(
              tooltip: l10n.oneViewEndTableConfirm,
              onPressed: onLeave,
              icon: Icon(Icons.close_rounded, color: colors.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeatLayout extends StatelessWidget {
  const _SeatLayout({
    required this.seats,
    required this.onSeatTap,
    required this.onLifeDelta,
  });

  final List<OneViewSeat> seats;
  final ValueChanged<int> onSeatTap;
  final void Function(int index, int delta) onLifeDelta;

  @override
  Widget build(BuildContext context) {
    final n = seats.length;
    return switch (n) {
      1 => _SeatTile(
        seat: seats[0],
        rotate180: false,
        onTap: () => onSeatTap(0),
        onLifeDelta: (d) => onLifeDelta(0, d),
      ),
      2 => Column(
        children: [
          Expanded(
            child: _SeatTile(
              seat: seats[0],
              rotate180: true,
              onTap: () => onSeatTap(0),
              onLifeDelta: (d) => onLifeDelta(0, d),
            ),
          ),
          Expanded(
            child: _SeatTile(
              seat: seats[1],
              rotate180: false,
              onTap: () => onSeatTap(1),
              onLifeDelta: (d) => onLifeDelta(1, d),
            ),
          ),
        ],
      ),
      3 => Row(
        children: [
          Expanded(
            child: _SeatTile(
              seat: seats[0],
              rotate180: false,
              onTap: () => onSeatTap(0),
              onLifeDelta: (d) => onLifeDelta(0, d),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _SeatTile(
                    seat: seats[1],
                    rotate180: true,
                    onTap: () => onSeatTap(1),
                    onLifeDelta: (d) => onLifeDelta(1, d),
                  ),
                ),
                Expanded(
                  child: _SeatTile(
                    seat: seats[2],
                    rotate180: false,
                    onTap: () => onSeatTap(2),
                    onLifeDelta: (d) => onLifeDelta(2, d),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      4 => Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _SeatTile(
                    seat: seats[0],
                    rotate180: true,
                    onTap: () => onSeatTap(0),
                    onLifeDelta: (d) => onLifeDelta(0, d),
                  ),
                ),
                Expanded(
                  child: _SeatTile(
                    seat: seats[1],
                    rotate180: true,
                    onTap: () => onSeatTap(1),
                    onLifeDelta: (d) => onLifeDelta(1, d),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _SeatTile(
                    seat: seats[2],
                    rotate180: false,
                    onTap: () => onSeatTap(2),
                    onLifeDelta: (d) => onLifeDelta(2, d),
                  ),
                ),
                Expanded(
                  child: _SeatTile(
                    seat: seats[3],
                    rotate180: false,
                    onTap: () => onSeatTap(3),
                    onLifeDelta: (d) => onLifeDelta(3, d),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      5 => Column(
        children: [
          Expanded(
            child: Row(
              children: [
                for (final i in [0, 1])
                  Expanded(
                    child: _SeatTile(
                      seat: seats[i],
                      rotate180: true,
                      onTap: () => onSeatTap(i),
                      onLifeDelta: (d) => onLifeDelta(i, d),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (final i in [2, 3, 4])
                  Expanded(
                    child: _SeatTile(
                      seat: seats[i],
                      rotate180: false,
                      onTap: () => onSeatTap(i),
                      onLifeDelta: (d) => onLifeDelta(i, d),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      _ => Column(
        children: [
          Expanded(
            child: Row(
              children: [
                for (final i in [0, 1, 2])
                  Expanded(
                    child: _SeatTile(
                      seat: seats[i],
                      rotate180: true,
                      onTap: () => onSeatTap(i),
                      onLifeDelta: (d) => onLifeDelta(i, d),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (final i in [3, 4, 5])
                  Expanded(
                    child: _SeatTile(
                      seat: seats[i],
                      rotate180: false,
                      onTap: () => onSeatTap(i),
                      onLifeDelta: (d) => onLifeDelta(i, d),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    };
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.seat,
    required this.rotate180,
    required this.onTap,
    required this.onLifeDelta,
  });

  final OneViewSeat seat;
  final bool rotate180;
  final VoidCallback onTap;
  final ValueChanged<int> onLifeDelta;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final child = Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RadiusTokens.radiusXl,
          side: BorderSide(
            color: seat.seatColor.withValues(alpha: OpacityTokens.half),
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (seat.commanderImageUrl != null &&
                  seat.commanderImageUrl!.isNotEmpty)
                Opacity(
                  opacity: 0.22,
                  child: Image.network(
                    seat.commanderImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      LayoutTokens.gr2,
                      LayoutTokens.gr1,
                      LayoutTokens.gr2,
                      0,
                    ),
                    child: Text(
                      seat.isEmpty
                          ? l10n.oneViewEmptySeat
                          : seat.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: FontTokens.caption,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _LifeEdge(
                          label: '−',
                          onTap: () => onLifeDelta(-1),
                          enabled: seat.isClaimed,
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              seat.isEmpty ? '—' : '${seat.life}',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 42,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _LifeEdge(
                          label: '+',
                          onTap: () => onLifeDelta(1),
                          enabled: seat.isClaimed,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!rotate180) return child;
    return RotatedBox(quarterTurns: 2, child: child);
  }
}

class _LifeEdge extends StatelessWidget {
  const _LifeEdge({
    required this.label,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return SizedBox(
      width: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color:
                    enabled
                        ? colors.primaryAccent
                        : colors.textSecondary.withValues(
                          alpha: OpacityTokens.half,
                        ),
                fontSize: 32,
                fontWeight: FontWeight.w600,
              ),
            ),
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
Future<void> showOneViewSitCodeSheet(BuildContext context, WidgetRef ref) async {
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
