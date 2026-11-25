import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/game/game_constants.dart';
import '../../core/one_view/one_view_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/game_haptics.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/motion_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/team_colors.dart';

/// A seat is tall enough for the vertical − / + edges.
bool oneViewSeatIsTall(double maxWidth, double maxHeight) =>
    maxHeight > maxWidth * 1.2;

/// Height (tall) or width (wide) of one life-step band.
double oneViewLifeBand({
  required bool tall,
  required double maxWidth,
  required double maxHeight,
}) {
  if (tall) return (maxHeight * 0.18).clamp(44.0, 72.0);
  return (maxWidth * 0.16).clamp(40.0, 64.0);
}

/// How far a finger must travel before a drag counts as an attack.
const double oneViewAttackMinTravel = 48;

/// The middle of a card, inset by the − / + bands, in the card's own
/// coordinates. A drag that starts here can deal damage. A drag that
/// starts on a band stays a life-button press.
Rect oneViewAttackCenter(Size size) {
  if (size.isEmpty) return Rect.zero;
  final tall = oneViewSeatIsTall(size.width, size.height);
  final band = oneViewLifeBand(
    tall: tall,
    maxWidth: size.width,
    maxHeight: size.height,
  );
  if (tall) {
    final inset = math.min(band, size.height / 2);
    return Rect.fromLTRB(
      0,
      inset,
      size.width,
      math.max(inset, size.height - inset),
    );
  }
  final inset = math.min(band, size.width / 2);
  return Rect.fromLTRB(
    inset,
    0,
    math.max(inset, size.width - inset),
    size.height,
  );
}

enum OneViewStrikeKind { life, commander }

/// The defender's card, turned to face the attacker.
/// Choose damage or commander damage, then tap once per point.
class OneViewAttackOverlay extends ConsumerStatefulWidget {
  const OneViewAttackOverlay({
    super.key,
    required this.attackerIndex,
    required this.defenderIndex,
    required this.faceAttackerUpsideDown,
    required this.onDismiss,
  });

  final int attackerIndex;
  final int defenderIndex;
  final bool faceAttackerUpsideDown;
  final VoidCallback onDismiss;

  @override
  ConsumerState<OneViewAttackOverlay> createState() =>
      _OneViewAttackOverlayState();
}

class _OneViewAttackOverlayState extends ConsumerState<OneViewAttackOverlay>
    with TickerProviderStateMixin {
  static const Duration _idleLimit = Duration(seconds: 3);

  late final AnimationController _enter;
  late final AnimationController _flash;
  late final Animation<double> _flashOpacity;
  late final AnimationController _pulse;
  late final Animation<double> _pulseScale;
  late final AnimationController _float;
  late final Animation<double> _floatFade;
  late final Animation<Offset> _floatSlide;

  Timer? _idleTimer;
  OneViewStrikeKind? _kind;
  var _hits = 0;
  int? _floatDelta;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: MotionTokens.slow);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..value = 1;
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _float = AnimationController(vsync: this, duration: MotionTokens.lifeDelta);
    const holdThenMove = Interval(0.5, 1.0, curve: Curves.easeOut);
    _floatFade = Tween<double>(
      begin: 1,
      end: 0,
    ).animate(CurvedAnimation(parent: _float, curve: holdThenMove));
    _floatSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -1.4),
    ).animate(CurvedAnimation(parent: _float, curve: holdThenMove));
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.06,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 60,
      ),
    ]).animate(_pulse);
    _flashOpacity = Tween<double>(
      begin: OpacityTokens.moderate,
      end: 0,
    ).animate(CurvedAnimation(parent: _flash, curve: Curves.easeOut));
    _enter.forward();
    _armIdle();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _enter.dispose();
    _flash.dispose();
    _pulse.dispose();
    _float.dispose();
    super.dispose();
  }

  void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleLimit, _close);
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _idleTimer?.cancel();
    _enter.reverse().then((_) {
      if (mounted) widget.onDismiss();
    }, onError: (_) {});
  }

  void _choose(OneViewStrikeKind kind) {
    if (_closing) return;
    setState(() {
      if (_kind != kind) {
        _kind = kind;
        _hits = 0;
        _floatDelta = null;
      }
    });
    context.gameHapticSelection();
    _armIdle();
  }

  void _hit() {
    if (!mounted || _closing) return;
    final kind = _kind;
    if (kind == null) return;
    final table = ref.read(oneViewProvider);
    if (widget.defenderIndex < 0 ||
        widget.defenderIndex >= table.seats.length ||
        widget.attackerIndex < 0 ||
        widget.attackerIndex >= table.seats.length) {
      _close();
      return;
    }
    final before = table.seats[widget.defenderIndex];
    if (before.isEmpty) {
      _close();
      return;
    }
    final notifier = ref.read(oneViewProvider.notifier);
    if (kind == OneViewStrikeKind.life) {
      notifier.adjustLife(widget.defenderIndex, -1);
    } else {
      notifier.adjustCommanderDamage(
        targetSeatIndex: widget.defenderIndex,
        fromSeatIndex: widget.attackerIndex,
        delta: 1,
      );
    }
    final after = ref.read(oneViewProvider).seats[widget.defenderIndex];
    final fromAttacker = after.commanderDamageFrom[widget.attackerIndex] ?? 0;
    final heavy =
        after.life <= 10 ||
        (kind == OneViewStrikeKind.commander &&
            fromAttacker >= GameConstants.commanderDamageKo);
    setState(() {
      _hits += 1;
      final coalesce =
          _floatDelta != null && _float.isAnimating && _float.value < 0.5;
      _floatDelta = coalesce ? _floatDelta! - 1 : -1;
    });
    _float.forward(from: 0);
    _pulse.forward(from: 0);
    _flash.forward(from: 0);
    if (heavy) {
      context.gameHapticHeavy();
    } else if (_hits >= 3) {
      context.gameHapticMedium();
    } else {
      context.gameHapticLight();
    }
    _armIdle();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final table = ref.watch(oneViewProvider);
    final seat =
        widget.defenderIndex >= 0 && widget.defenderIndex < table.seats.length
            ? table.seats[widget.defenderIndex]
            : null;
    if (seat == null || seat.isEmpty) {
      if (!_closing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _close();
        });
      }
      return const SizedBox.shrink();
    }

    final screen = MediaQuery.sizeOf(context);
    final inset = MediaQuery.viewPaddingOf(context);
    final width = math.max(0.0, screen.width - inset.horizontal);
    final height = math.max(0.0, screen.height - inset.vertical);
    final cardW = math.min(width * 0.92, height * 0.74);
    final cardH = math.min(height * 0.82, width * 1.08);
    final lifeSize = (cardH * 0.34).clamp(56.0, 140.0);
    final lifeColor =
        seat.life <= 5
            ? colors.error
            : seat.life <= 10
            ? colors.emphasis
            : colors.textPrimary;
    final showTeam = table.config.teamsEnabled && seat.teamIndex > 0;
    final hasArt =
        seat.commanderImageUrl != null && seat.commanderImageUrl!.isNotEmpty;
    final statusParts = <String>[
      if (seat.poison > 0) l10n.oneViewPoisonCount(seat.poison),
      if (seat.commanderDamageTotal > 0)
        l10n.oneViewCommanderDamageCount(seat.commanderDamageTotal),
    ];
    final enter = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);

    return FadeTransition(
      opacity: enter,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: _close,
            behavior: HitTestBehavior.opaque,
            child: ColoredBox(
              color: colors.backgroundPrimary.withValues(
                alpha: OpacityTokens.strong,
              ),
            ),
          ),
          Center(
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(enter),
              child: RotatedBox(
                quarterTurns: widget.faceAttackerUpsideDown ? 2 : 0,
                child: SizedBox(
                  width: cardW,
                  height: cardH,
                  child: Material(
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: RadiusTokens.radiusBento,
                      side: BorderSide(color: colors.borderSubtle),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (_kind == null || _closing) return;
                            _hit();
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (hasArt)
                                _AttackArt(url: seat.commanderImageUrl!),
                              IgnorePointer(
                                child: FadeTransition(
                                  opacity: _flashOpacity,
                                  child: ColoredBox(
                                    color: colors.primaryAccent,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  LayoutTokens.gr3,
                                  LayoutTokens.gr4,
                                  LayoutTokens.gr3,
                                  LayoutTokens.gr3 +
                                      LayoutTokens.minTapTarget +
                                      LayoutTokens.gr2,
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (showTeam) ...[
                                          Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: teamColor(seat.teamIndex),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(
                                            width: LayoutTokens.gr1,
                                          ),
                                        ],
                                        Flexible(
                                          child: Text(
                                            seat.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.lato(
                                              color: colors.textPrimary,
                                              fontSize: FontTokens.headline,
                                              fontWeight: FontWeight.w600,
                                              height: 1.1,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          alignment: Alignment.center,
                                          children: [
                                            AnimatedBuilder(
                                              animation: _pulse,
                                              builder: (context, child) {
                                                return Transform.scale(
                                                  scale: _pulseScale.value,
                                                  child: child,
                                                );
                                              },
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  '${seat.life}',
                                                  style: GoogleFonts.barlowCondensed(
                                                    color: lifeColor,
                                                    fontSize: lifeSize,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: -0.5,
                                                    height: 0.9,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (_floatDelta != null)
                                              IgnorePointer(
                                                child: FadeTransition(
                                                  opacity: _floatFade,
                                                  child: SlideTransition(
                                                    position: _floatSlide,
                                                    child: Transform.translate(
                                                      offset: Offset(
                                                        0,
                                                        -(lifeSize * 0.42),
                                                      ),
                                                      child: Text(
                                                        '$_floatDelta',
                                                        style:
                                                            GoogleFonts.barlowCondensed(
                                                              color:
                                                                  colors.error,
                                                              fontSize:
                                                                  (lifeSize *
                                                                          0.28)
                                                                      .clamp(
                                                                        18.0,
                                                                        36.0,
                                                                      ),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
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
                                    ),
                                    if (statusParts.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: LayoutTokens.gr1,
                                        ),
                                        child: Text(
                                          statusParts.join(' · '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.lato(
                                            color: colors.emphasis,
                                            fontSize: FontTokens.hudSm,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    if (_kind != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: LayoutTokens.gr2,
                                        ),
                                        child: Text(
                                          _hits > 0
                                              ? '${l10n.oneViewAttackTap}  $_hits'
                                              : l10n.oneViewAttackTap,
                                          style: GoogleFonts.lato(
                                            color:
                                                _hits > 0
                                                    ? colors.primaryAccent
                                                    : colors.textSecondary,
                                            fontSize: FontTokens.caption,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: LayoutTokens.gr3,
                          right: LayoutTokens.gr3,
                          bottom: LayoutTokens.gr3,
                          child: Row(
                            children: [
                              _StrikeChoice(
                                label: l10n.oneViewAttackDamage,
                                selected: _kind == OneViewStrikeKind.life,
                                onTap: () => _choose(OneViewStrikeKind.life),
                              ),
                              const SizedBox(width: LayoutTokens.gr1),
                              _StrikeChoice(
                                label: l10n.oneViewCommanderDamageLabel,
                                selected: _kind == OneViewStrikeKind.commander,
                                onTap:
                                    () => _choose(OneViewStrikeKind.commander),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrikeChoice extends StatelessWidget {
  const _StrikeChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final ink = selected ? colors.primaryAccent : colors.textPrimary;
    return Expanded(
      child: Material(
        color:
            selected
                ? colors.primaryAccent.withValues(alpha: OpacityTokens.subtle)
                : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: RadiusTokens.radiusLg,
          side: BorderSide(
            color: selected ? colors.primaryAccent : colors.borderSubtle,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: LayoutTokens.minTapTarget,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gr1),
              child: Center(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lato(
                    color: ink,
                    fontSize: FontTokens.caption,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
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

class _AttackArt extends StatelessWidget {
  const _AttackArt({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final veil = AppColorTokens.of(context).surface;
    final cacheW = (MediaQuery.sizeOf(context).shortestSide *
            MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(480, 1080);
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
            errorWidget: (_, _, _) => const SizedBox.shrink(),
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
