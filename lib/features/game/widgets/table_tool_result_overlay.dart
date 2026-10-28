import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/game/game_providers.dart';
import '../../../core/game/game_session_events.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/tokens/color_tokens.dart';
import '../../../ui/tokens/font_tokens.dart';
import '../../../ui/tokens/layout_tokens.dart';
import '../../../ui/tokens/opacity_tokens.dart';
import '../../../ui/tokens/radius_tokens.dart';
import '../../../ui/tokens/motion_tokens.dart';
import 'game_colors.dart';

/// Full-screen shared dice / coin result. Tap or wait [autoDismiss] to clear.
class TableToolResultOverlay extends ConsumerStatefulWidget {
  const TableToolResultOverlay({
    super.key,
    required this.announcement,
    this.autoDismiss = const Duration(seconds: 5),
  });

  final TableToolAnnouncement announcement;
  final Duration autoDismiss;

  @override
  ConsumerState<TableToolResultOverlay> createState() =>
      _TableToolResultOverlayState();
}

class _TableToolResultOverlayState extends ConsumerState<TableToolResultOverlay>
    with TickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _spin;
  late final AnimationController _land;
  final _rand = math.Random();
  late int _shownFace;
  var _settled = false;
  DateTime? _lastFaceAt;

  @override
  void initState() {
    super.initState();
    _shownFace = _finalFace;
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _land = AnimationController(vsync: this, duration: MotionTokens.slow);
    _spin.addListener(_tickFace);
    _armTimer();
    _play();
  }

  @override
  void didUpdateWidget(covariant TableToolResultOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.announcement.id != widget.announcement.id) {
      _armTimer();
      _play();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _spin.removeListener(_tickFace);
    _spin.dispose();
    _land.dispose();
    super.dispose();
  }

  int get _finalFace {
    final a = widget.announcement;
    return switch (a.kind) {
      TableToolKind.coin => (a.coinHeads ?? false) ? 1 : 0,
      TableToolKind.d20 => (a.dieValue ?? 1).clamp(1, 20),
      TableToolKind.d6 => (a.dieValue ?? 1).clamp(1, 6),
    };
  }

  void _play() {
    _settled = false;
    _lastFaceAt = null;
    _shownFace = switch (widget.announcement.kind) {
      TableToolKind.coin => _rand.nextBool() ? 1 : 0,
      TableToolKind.d20 => _rand.nextInt(20) + 1,
      TableToolKind.d6 => _rand.nextInt(6) + 1,
    };
    _land.value = 0;
    _spin.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _settled = true;
        _shownFace = _finalFace;
      });
      _land.forward(from: 0);
    });
  }

  void _tickFace() {
    if (_settled || !mounted) return;
    final now = DateTime.now();
    if (_lastFaceAt != null &&
        now.difference(_lastFaceAt!) < const Duration(milliseconds: 70)) {
      return;
    }
    _lastFaceAt = now;
    final next = switch (widget.announcement.kind) {
      TableToolKind.coin => _rand.nextBool() ? 1 : 0,
      TableToolKind.d6 => _rand.nextInt(6) + 1,
      TableToolKind.d20 => _rand.nextInt(20) + 1,
    };
    if (next == _shownFace) return;
    setState(() => _shownFace = next);
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(widget.autoDismiss, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    ref.read(gameProvider.notifier).dismissTableToolAnnouncement();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final a = widget.announcement;
    final headline = a.localizedHeadline(l10n);

    return Positioned.fill(
      child: Semantics(
        button: true,
        label: l10n.tableToolDismissA11y(headline),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _dismiss,
          child: ColoredBox(
            color: colors.backgroundPrimary.withValues(
              alpha: OpacityTokens.strong,
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: LayoutTokens.gr5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primaryAccent,
                    borderRadius: RadiusTokens.radiusXl,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: LayoutTokens.gr5,
                      vertical: LayoutTokens.gr5,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          a.localizedToolLabel(l10n).toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onAccent.withValues(alpha: 0.85),
                            fontSize: FontTokens.caption,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: LayoutTokens.gr3),
                        _RollingProp(
                          kind: a.kind,
                          face: _settled ? _finalFace : _shownFace,
                          spin: _spin,
                          land: _land,
                          settled: _settled,
                          headsLabel: l10n.tableToolHeads,
                          tailsLabel: l10n.tableToolTails,
                          dieColor: ColorTokens.lightSurface,
                          pipColor: ColorTokens.lightTextPrimary,
                          coinColor: colors.emphasis,
                          coinInk: colors.backgroundPrimary,
                        ),
                        SizedBox(height: LayoutTokens.gr3),
                        Text(
                          headline,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onAccent,
                            fontSize: FontTokens.title,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        SizedBox(height: LayoutTokens.gr2),
                        Text(
                          l10n.tableToolTapToDismiss,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onAccent.withValues(alpha: 0.85),
                            fontSize: FontTokens.body,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RollingProp extends StatelessWidget {
  const _RollingProp({
    required this.kind,
    required this.face,
    required this.spin,
    required this.land,
    required this.settled,
    required this.headsLabel,
    required this.tailsLabel,
    required this.dieColor,
    required this.pipColor,
    required this.coinColor,
    required this.coinInk,
  });

  final TableToolKind kind;
  final int face;
  final Animation<double> spin;
  final Animation<double> land;
  final bool settled;
  final String headsLabel;
  final String tailsLabel;
  final Color dieColor;
  final Color pipColor;
  final Color coinColor;
  final Color coinInk;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([spin, land]),
      builder: (context, _) {
        final t = spin.value;
        final spinning = !settled;
        final scale = settled ? 0.92 + 0.08 * land.value : 1.0;
        final transform = Matrix4.identity()..setEntry(3, 2, 0.0014);
        if (kind == TableToolKind.coin) {
          final angle = spinning ? t * math.pi * 6 : 0.0;
          final showHeads = !spinning ? face == 1 : math.cos(angle) >= 0;
          var display = angle;
          if (spinning && !showHeads) display -= math.pi;
          transform.rotateX(display);
          return Transform(
            alignment: Alignment.center,
            transform: transform,
            child: Transform.scale(
              scale: scale,
              child: _CoinFace(
                label: showHeads ? headsLabel : tailsLabel,
                fill: coinColor,
                ink: coinInk,
              ),
            ),
          );
        }
        final flip =
            spinning ? math.cos(t * math.pi * 8).abs().clamp(0.12, 1.0) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scaleByDouble(flip, 1, 1, 1),
            child: _FlatDie(label: '$face', fill: dieColor, ink: pipColor),
          ),
        );
      },
    );
  }
}

class _FlatDie extends StatelessWidget {
  const _FlatDie({required this.label, required this.fill, required this.ink});

  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: RadiusTokens.radiusMd,
        border: Border.all(color: ink.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ink,
          fontSize: FontTokens.displayCommander,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

class _CoinFace extends StatelessWidget {
  const _CoinFace({required this.label, required this.fill, required this.ink});

  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: ink.withValues(alpha: 0.35), width: 6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
