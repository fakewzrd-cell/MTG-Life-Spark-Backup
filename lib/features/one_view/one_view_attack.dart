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
import '../../shared/utils/profile_avatar_storage.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/motion_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/team_colors.dart';
import 'one_view_chrome.dart';

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

/// Claimed opponents a drag has reached, in the order the finger entered them.
///
/// [samples] are the seats under the finger after the drag has traveled far
/// enough to count as an attack. Null samples, [from], and empty seats are
/// skipped. A seat is listed once, the first time the finger enters it.
List<int> oneViewAttackTargets({
  required int from,
  required Iterable<int?> samples,
  required int seatCount,
  required bool Function(int index) isClaimed,
}) {
  final targets = <int>[];
  for (final sample in samples) {
    if (sample == null || sample == from) continue;
    if (sample < 0 || sample >= seatCount) continue;
    if (!isClaimed(sample)) continue;
    if (targets.contains(sample)) continue;
    targets.add(sample);
  }
  return targets;
}

/// Narrowest attack card that still has room for a name and a tap.
const double oneViewAttackMinCardWidth = 96;

/// Columns and rows for the attack popup. One row while each card stays
/// wide enough to tap. A narrow portrait board wraps the rest into two
/// shorter rows so nothing scrolls off the screen.
({int columns, int rows}) oneViewAttackGrid({
  required int count,
  required double maxWidth,
}) {
  if (count <= 1) return (columns: 1, rows: 1);
  const gap = LayoutTokens.gr2;
  final across = (maxWidth - gap * (count - 1)) / count;
  if (across >= oneViewAttackMinCardWidth) {
    return (columns: count, rows: 1);
  }
  final columns = (count + 1) ~/ 2;
  final rows = (count + columns - 1) ~/ columns;
  return (columns: columns, rows: rows);
}

/// Card height that fills the leftover space without running past it.
double oneViewAttackCardHeight({
  required int count,
  required int rows,
  required double cardWidth,
  required double maxHeight,
}) {
  const gap = LayoutTokens.gr2;
  final room =
      maxHeight.isFinite
          ? math.max(0.0, (maxHeight - gap * (rows - 1)) / rows)
          : cardWidth;
  if (count <= 1) return math.min(room, 360);
  return math.min(room, cardWidth * 1.35);
}

enum OneViewStrikeKind { life, commander }

/// The players a drag reached, turned to face the attacker.
/// Choose damage or commander damage once, then tap each card per point.
class OneViewAttackOverlay extends ConsumerStatefulWidget {
  const OneViewAttackOverlay({
    super.key,
    required this.attackerIndex,
    required this.defenderIndexes,
    required this.faceAttackerUpsideDown,
    required this.onDismiss,
  });

  final int attackerIndex;
  final List<int> defenderIndexes;
  final bool faceAttackerUpsideDown;
  final VoidCallback onDismiss;

  @override
  ConsumerState<OneViewAttackOverlay> createState() =>
      _OneViewAttackOverlayState();
}

class _OneViewAttackOverlayState extends ConsumerState<OneViewAttackOverlay>
    with TickerProviderStateMixin {
  static const Duration _idleLimit = Duration(seconds: 5);

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
  final Map<int, int> _hits = {};
  int? _floatIndex;
  int? _floatDelta;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: MotionTokens.standard);
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
          end: 1.025,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.025,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 60,
      ),
    ]).animate(_pulse);
    _flashOpacity = Tween<double>(
      begin: 0.06,
      end: 0,
    ).animate(CurvedAnimation(parent: _flash, curve: Curves.easeOut));
    _enter.forward();
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
    if (MediaQuery.accessibleNavigationOf(context)) return;
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
    _idleTimer?.cancel();
    setState(() {
      if (_kind != kind) {
        _kind = kind;
        _hits.clear();
        _floatIndex = null;
        _floatDelta = null;
      }
    });
    context.gameHapticSelection();
  }

  void _hit(int defenderIndex) {
    if (!mounted || _closing) return;
    final kind = _kind;
    if (kind == null) return;
    final table = ref.read(oneViewProvider);
    if (defenderIndex < 0 ||
        defenderIndex >= table.seats.length ||
        widget.attackerIndex < 0 ||
        widget.attackerIndex >= table.seats.length) {
      _close();
      return;
    }
    final before = table.seats[defenderIndex];
    if (before.isEmpty) {
      _close();
      return;
    }
    final notifier = ref.read(oneViewProvider.notifier);
    if (kind == OneViewStrikeKind.life) {
      notifier.adjustLife(defenderIndex, -1);
    } else {
      notifier.adjustCommanderDamage(
        targetSeatIndex: defenderIndex,
        fromSeatIndex: widget.attackerIndex,
        delta: 1,
      );
    }
    final after = ref.read(oneViewProvider).seats[defenderIndex];
    final fromAttacker = after.commanderDamageFrom[widget.attackerIndex] ?? 0;
    final hits = (_hits[defenderIndex] ?? 0) + 1;
    final heavy =
        after.life <= 10 ||
        (kind == OneViewStrikeKind.commander &&
            fromAttacker >= GameConstants.commanderDamageKo);
    setState(() {
      _hits[defenderIndex] = hits;
      final coalesce =
          _floatIndex == defenderIndex &&
          _floatDelta != null &&
          _float.isAnimating &&
          _float.value < 0.5;
      _floatIndex = defenderIndex;
      _floatDelta = coalesce ? _floatDelta! - 1 : -1;
    });
    _float.forward(from: 0);
    if (!MediaQuery.disableAnimationsOf(context)) {
      _pulse.forward(from: 0);
      _flash.forward(from: 0);
    }
    if (heavy) {
      context.gameHapticHeavy();
    } else if (hits >= 3) {
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
    final indexes = <int>[];
    for (final index in widget.defenderIndexes) {
      if (index < 0 || index >= table.seats.length) continue;
      if (table.seats[index].isEmpty) continue;
      if (indexes.contains(index)) continue;
      indexes.add(index);
    }
    if (indexes.isEmpty) {
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
    final landscape = width > height;
    final boardW = math.min(width * 0.94, landscape ? 880.0 : 520.0);
    final boardH = height * 0.9;
    final enter = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);

    return FadeTransition(
      opacity:
          MediaQuery.disableAnimationsOf(context)
              ? const AlwaysStoppedAnimation(1.0)
              : enter,
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
              scale:
                  MediaQuery.disableAnimationsOf(context)
                      ? const AlwaysStoppedAnimation(1.0)
                      : Tween<double>(begin: 0.98, end: 1).animate(enter),
              child: RotatedBox(
                quarterTurns: widget.faceAttackerUpsideDown ? 2 : 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: boardW,
                    maxHeight: boardH,
                  ),
                  child: Material(
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: RadiusTokens.radiusXl,
                      side: BorderSide(color: colors.borderSubtle),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(LayoutTokens.gr3),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.oneViewAttackHint,
                                  style: OneViewChrome.dialogBodyStyle(context),
                                ),
                              ),
                              TextButton(
                                onPressed: _close,
                                child: Text(l10n.oneViewDone),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _StrikeChoice(
                                label: l10n.oneViewAttackDamage,
                                selected: _kind == OneViewStrikeKind.life,
                                onTap: () => _choose(OneViewStrikeKind.life),
                              ),
                              const SizedBox(width: 8),
                              _StrikeChoice(
                                label: l10n.oneViewCommanderDamageLabel,
                                selected: _kind == OneViewStrikeKind.commander,
                                onTap:
                                    () => _choose(OneViewStrikeKind.commander),
                              ),
                            ],
                          ),
                          const SizedBox(height: LayoutTokens.gr3),
                          Flexible(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return _AttackBoard(
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight,
                                  indexes: indexes,
                                  seats: table.seats,
                                  teamsEnabled: table.config.teamsEnabled,
                                  kindSelected: _kind != null,
                                  floatIndex: _floatIndex,
                                  floatDelta: _floatDelta,
                                  flash: _flashOpacity,
                                  pulse: _pulseScale,
                                  floatFade: _floatFade,
                                  floatSlide:
                                      MediaQuery.disableAnimationsOf(context)
                                          ? const AlwaysStoppedAnimation(
                                            Offset.zero,
                                          )
                                          : _floatSlide,
                                  onTap: _hit,
                                );
                              },
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
        ],
      ),
    );
  }
}

class _AttackBoard extends StatelessWidget {
  const _AttackBoard({
    required this.maxWidth,
    required this.maxHeight,
    required this.indexes,
    required this.seats,
    required this.teamsEnabled,
    required this.kindSelected,
    required this.floatIndex,
    required this.floatDelta,
    required this.flash,
    required this.pulse,
    required this.floatFade,
    required this.floatSlide,
    required this.onTap,
  });

  final double maxWidth;
  final double maxHeight;
  final List<int> indexes;
  final List<OneViewSeat> seats;
  final bool teamsEnabled;
  final bool kindSelected;
  final int? floatIndex;
  final int? floatDelta;
  final Animation<double> flash;
  final Animation<double> pulse;
  final Animation<double> floatFade;
  final Animation<Offset> floatSlide;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final count = indexes.length;
    if (count == 0 || maxWidth <= 0) return const SizedBox.shrink();
    const gap = LayoutTokens.gr2;
    final grid = oneViewAttackGrid(count: count, maxWidth: maxWidth);
    final rawWidth =
        count == 1
            ? math.min(maxWidth, 320.0)
            : (maxWidth - gap * (grid.columns - 1)) / grid.columns;
    // Floor so a row of equal cards cannot spill a fraction of a pixel.
    final cardW = math.max(0.0, rawWidth.floorToDouble());
    final cardH = oneViewAttackCardHeight(
      count: count,
      rows: grid.rows,
      cardWidth: cardW,
      maxHeight: maxHeight,
    );

    final gridRows = <Widget>[];
    for (var row = 0; row < grid.rows; row++) {
      if (row > 0) gridRows.add(const SizedBox(height: gap));
      final cells = <Widget>[];
      for (var col = 0; col < grid.columns; col++) {
        final n = row * grid.columns + col;
        if (n >= count) break;
        if (cells.isNotEmpty) cells.add(const SizedBox(width: gap));
        final index = indexes[n];
        final active = floatIndex == index;
        cells.add(
          SizedBox(
            width: cardW,
            height: cardH,
            child: _AttackTargetCard(
              seat: seats[index],
              showTeam: teamsEnabled,
              kindSelected: kindSelected,
              lifeDelta: active ? floatDelta : null,
              flash: flash,
              pulse: pulse,
              floatFade: floatFade,
              floatSlide: floatSlide,
              onTap: () => onTap(index),
            ),
          ),
        );
      }
      gridRows.add(
        Row(mainAxisAlignment: MainAxisAlignment.center, children: cells),
      );
    }

    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: gridRows),
    );
  }
}

class _AttackTargetCard extends StatelessWidget {
  const _AttackTargetCard({
    required this.seat,
    required this.showTeam,
    required this.kindSelected,
    required this.lifeDelta,
    required this.flash,
    required this.pulse,
    required this.floatFade,
    required this.floatSlide,
    required this.onTap,
  });

  final OneViewSeat seat;
  final bool showTeam;
  final bool kindSelected;
  final int? lifeDelta;
  final Animation<double> flash;
  final Animation<double> pulse;
  final Animation<double> floatFade;
  final Animation<Offset> floatSlide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final artUrl = seat.cardArtUrl;
    final lifeColor =
        seat.life <= 5
            ? colors.error
            : seat.life <= 10
            ? colors.emphasis
            : colors.textPrimary;
    final statusParts = <String>[
      if (seat.poison > 0) l10n.oneViewPoisonCount(seat.poison),
      if (seat.commanderDamageTotal > 0)
        l10n.oneViewCommanderDamageCount(seat.commanderDamageTotal),
    ];

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: RadiusTokens.radiusLg,
        side: BorderSide(
          color: kindSelected ? colors.primaryAccent : colors.borderSubtle,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 160;
            final lifeSize = (constraints.maxHeight * 0.38).clamp(
              compact ? 22.0 : 36.0,
              96.0,
            );
            final nameSize =
                compact
                    ? FontTokens.hudSm
                    : constraints.maxWidth < 220
                    ? FontTokens.body
                    : FontTokens.headline;
            final pad = compact ? LayoutTokens.gr1 : LayoutTokens.gr2;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (artUrl != null) _AttackArt(url: artUrl),
                if (lifeDelta != null)
                  IgnorePointer(
                    child: FadeTransition(
                      opacity: flash,
                      child: ColoredBox(color: colors.primaryAccent),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (showTeam && seat.teamIndex > 0) ...[
                            Container(
                              width: 16,
                              height: 16,
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
                                animation: pulse,
                                builder: (context, child) {
                                  return Transform.scale(
                                    scale: lifeDelta == null ? 1 : pulse.value,
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
                              if (lifeDelta != null)
                                IgnorePointer(
                                  child: FadeTransition(
                                    opacity: floatFade,
                                    child: SlideTransition(
                                      position: floatSlide,
                                      child: Text(
                                        '$lifeDelta',
                                        style: GoogleFonts.barlowCondensed(
                                          color: colors.error,
                                          fontSize: (lifeSize * 0.28).clamp(
                                            18.0,
                                            36.0,
                                          ),
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
                      ),
                      if (statusParts.isNotEmpty)
                        Text(
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
                    ],
                  ),
                ),
              ],
            );
          },
        ),
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
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gr2),
              child: Center(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lato(
                    color: ink,
                    fontSize: FontTokens.body,
                    fontWeight: FontWeight.w700,
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

/// Card or profile picture. Network URLs and saved profile photos both work.
class OneViewArtImage extends StatelessWidget {
  const OneViewArtImage({
    super.key,
    required this.url,
    required this.cacheWidth,
  });

  final String url;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final local = localFileFromRef(url);
    if (local != null) {
      return Image.file(
        local,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      memCacheWidth: cacheWidth,
      fadeInDuration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
      errorWidget: (_, _, _) => const SizedBox.shrink(),
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
