import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../ui/tokens/font_tokens.dart';
import '../../../core/game/gameplay_dial_ids.dart';
import '../../../core/game/player_game_state.dart';
import '../../../l10n/app_localizations.dart';
import 'game_colors.dart';
import '../../../ui/theme/app_color_tokens.dart';
import 'game_modal_chrome.dart';
import '../../../ui/components/ui_snack_bar.dart';
import '../../../shared/widgets/d20_icon.dart';
import '../../../shared/widgets/game_icon.dart';
import '../../../shared/utils/game_haptics.dart';
import '../../../ui/tokens/layout_tokens.dart';
import '../../../ui/tokens/opacity_tokens.dart';
import '../../../ui/tokens/motion_tokens.dart';
import '../../../ui/tokens/radius_tokens.dart';
import 'counter_adjust_sheet.dart';

/// Counter frames — modest rounding (not stadium pills).
const double _kDialPillCornerRadius = RadiusTokens.xl;

/// Icon + number. Tall enough to tap, short enough to sit under the life total.
const double _kCounterChipHeight = LayoutTokens.minTapTarget;

const double _kCounterIconSize = 24;

/// Modular preset counters. Each one is a short frame; tap it to adjust.

///
/// Only dials listed on [PlayerGameState.visibleGameplayDials] render on the
/// strip; use **Add** to pick core/preset trackers as needed.
class GameplayDialsStripWidget extends StatelessWidget {
  final PlayerGameState Function() getPlayer;
  final bool isEliminated;
  final void Function(String field, int delta) onAdjustCounter;
  final bool Function(String field) onAddDialToStrip;
  final void Function(String field) onRemoveDialFromStrip;

  const GameplayDialsStripWidget({
    super.key,
    required this.getPlayer,
    required this.isEliminated,
    required this.onAdjustCounter,
    required this.onAddDialToStrip,
    required this.onRemoveDialFromStrip,
    this.compactVertical = false,
  });

  final bool compactVertical;

  static const Set<String> _coreFields = {
    'poison',
    'energy',
    'experience',
    'rad',
  };

  static IconData _iconForField(String field) {
    return switch (field) {
      'poison' => Icons.coronavirus_outlined,
      'energy' => Icons.bolt_rounded,
      'experience' => Icons.auto_graph_rounded,
      'rad' => Icons.warning_amber_rounded,
      GameplayDialIds.blood => Icons.water_drop_rounded,
      GameplayDialIds.clue => Icons.search_rounded,
      GameplayDialIds.map => Icons.map_rounded,
      GameplayDialIds.treasure => Icons.stars_rounded,
      GameplayDialIds.devotion => Icons.auto_awesome_rounded,
      GameplayDialIds.creatures => Icons.pets_rounded,
      GameplayDialIds.enchantments => Icons.auto_fix_high_rounded,
      GameplayDialIds.artifacts => Icons.handyman_rounded,
      GameplayDialIds.graveyardCreatures => Icons.layers_rounded,
      GameplayDialIds.exile => Icons.output_rounded,
      _ => Icons.tune_rounded,
    };
  }

  static Color _listIconColor(AppColorTokens colors) =>
      colors.textSecondary.withValues(alpha: 0.95);

  /// Visual scale per counter artwork so mixed aspect ratios read evenly.
  static double _glyphVisualScale(String field) => switch (field) {
    'poison' => 1.08,
    'energy' => 1.0,
    'experience' => 0.94,
    _ => 1.0,
  };

  /// Counter artwork accepts [tintColor]; strip/list default to secondary text.
  static Widget _leadingGlyph(
    String field,
    double size,
    AppColorTokens colors, {
    Color? tintColor,
  }) {
    final tone = tintColor ?? _listIconColor(colors);
    final iconSize = size * _glyphVisualScale(field);
    return switch (field) {
      'poison' => GameIcon.poison(size: iconSize, color: tone),
      'energy' => GameIcon.energy(size: iconSize, color: tone),
      'experience' => GameIcon.experience(size: iconSize, color: tone),
      'rad' => GameIcon.radiation(size: iconSize, color: tone),
      GameplayDialIds.treasure => GameIcon.treasure(
        size: iconSize,
        color: tone,
      ),
      _ => Icon(_iconForField(field), size: iconSize, color: tone),
    };
  }

  PlayerGameState get player => getPlayer();

  static void _showStripLimitSnack(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showUiSnackBar(
      context,
      l10n.dialsStripLimitSnack(GameplayDialIds.maxStripDials),
    );
  }

  static String _labelFor(
    AppLocalizations l10n,
    PlayerGameState p,
    String field,
  ) {
    switch (field) {
      case 'poison':
        return l10n.dialsLabelPoison;
      case 'energy':
        return l10n.dialsLabelEnergy;
      case 'experience':
        return l10n.dialsLabelExp;
      case 'rad':
        return l10n.dialsLabelRad;
      default:
        return p.customDialLabels[field] ??
            switch (field) {
              GameplayDialIds.blood => l10n.dialsLabelBlood,
              GameplayDialIds.clue => l10n.dialsLabelClue,
              GameplayDialIds.map => l10n.dialsLabelMap,
              GameplayDialIds.treasure => l10n.dialsLabelTreasure,
              GameplayDialIds.devotion => l10n.dialsLabelDevotion,
              GameplayDialIds.creatures => l10n.dialsLabelCreatures,
              GameplayDialIds.enchantments => l10n.dialsLabelEnchant,
              GameplayDialIds.artifacts => l10n.dialsLabelArtifacts,
              GameplayDialIds.graveyardCreatures => l10n.dialsLabelGy,
              GameplayDialIds.exile => l10n.dialsLabelExile,
              _ => field,
            };
    }
  }

  static int _valueOf(PlayerGameState p, String field) => switch (field) {
    'poison' => p.poison,
    'energy' => p.energy,
    'experience' => p.experience,
    'rad' => p.rad,
    _ => p.extraDials[field] ?? 0,
  };

  static bool _fieldKnown(PlayerGameState p, String field) =>
      _coreFields.contains(field) ||
      GameplayDialIds.presets.contains(field) ||
      p.customDialLabels.containsKey(field);

  /// Strip dial tiles shown (same ordering as the strip widget).
  static int orderedStripFieldCount(PlayerGameState p) {
    final seen = <String>{};
    var n = 0;
    for (final f in p.visibleGameplayDials) {
      if (_fieldKnown(p, f) && seen.add(f)) n++;
    }
    return n;
  }

  /// Approximate vertical space for the counter row (planning Play tab layout).
  ///
  /// Frames hug their icon and number, so a narrow phone wraps a full strip
  /// plus Add across more than one row.
  static double estimatedStripHeight(
    BuildContext context, {
    bool compactVertical = false,
    bool hasVisibleDials = true,
  }) {
    if (!hasVisibleDials) return 0;
    const chipW = 88.0;
    const gap = LayoutTokens.gr1;
    final contentW = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - 2 * LayoutTokens.shellPageInset,
    );
    final perRow = math.max(1, ((contentW + gap) / (chipW + gap)).floor());
    const slots = GameplayDialIds.maxStripDials + 1;
    final rows = (slots / perRow).ceil();
    final verticalPad = compactVertical ? LayoutTokens.gr0 : LayoutTokens.gr1;
    return rows * _kCounterChipHeight + (rows - 1) * gap + verticalPad;
  }

  List<String> _orderedStripFields() {
    final seen = <String>{};
    final out = <String>[];
    for (final f in player.visibleGameplayDials) {
      if (_fieldKnown(player, f) && seen.add(f)) {
        out.add(f);
      }
    }
    return out;
  }

  void _showAdjust(
    BuildContext context,
    String field,
    String title,
    int current,
  ) {
    if (isEliminated) return;
    final isCustom = getPlayer().customDialLabels.containsKey(field);
    showCounterAdjustSheet(
      context,
      title: title,
      current: current,
      confirmReset: !isCustom,
      onChanged: (delta) => onAdjustCounter(field, delta),
      onRemove: () => onRemoveDialFromStrip(field),
    );
  }

  Future<void> _showAddChooser(BuildContext context) async {
    if (isEliminated) return;
    if (!GameplayDialLimits.canAddDialToStrip(getPlayer())) {
      _showStripLimitSnack(context);
      return;
    }
    context.gameHapticLight();
    final visible = getPlayer().visibleGameplayDials.toSet();
    final coreOrdered = ['poison', 'energy', 'experience', 'rad'];

    await showGameBottomSheet<void>(
      context: context,
      builder: (sheetCtx) {
        void pick(String field) {
          context.gameHapticSelection();
          final added = onAddDialToStrip(field);
          Navigator.pop(sheetCtx);
          if (!added && context.mounted) {
            _showStripLimitSnack(context);
          }
        }

        return _AddCounterSheetScaffold(
          player: getPlayer(),
          visible: visible,
          coreOrdered: coreOrdered,
          onPick: pick,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final fields = _orderedStripFields();
    final livePlayer = getPlayer();
    final showAddButton = GameplayDialLimits.showAddCounterTile(
      livePlayer,
      isEliminated: isEliminated,
    );
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.only(
        top: compactVertical ? LayoutTokens.gr0 : LayoutTokens.gr1,
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: LayoutTokens.gr1,
        runSpacing: LayoutTokens.gr1,
        children: [
          for (final field in fields)
            _CounterChip(
              label: _labelFor(l10n, livePlayer, field),
              value: _valueOf(livePlayer, field).clamp(0, 9999),
              enabled: !isEliminated,
              icon: _leadingGlyph(
                field,
                _kCounterIconSize,
                colors,
                tintColor:
                    isEliminated ? colors.textSecondary : colors.primaryAccent,
              ),
              onTap:
                  () => _showAdjust(
                    context,
                    field,
                    '${_labelFor(l10n, livePlayer, field)} counters',
                    _valueOf(livePlayer, field),
                  ),
            ),
          if (showAddButton)
            _AddCounterPillTile(
              isEliminated: isEliminated,
              onTap: () => _showAddChooser(context),
            ),
        ],
      ),
    );
  }
}

/// Content-sized add-counter sheet (caps tall lists; no forced empty band).
class _AddCounterSheetScaffold extends StatelessWidget {
  const _AddCounterSheetScaffold({
    required this.player,
    required this.visible,
    required this.coreOrdered,
    required this.onPick,
  });

  final PlayerGameState player;
  final Set<String> visible;
  final List<String> coreOrdered;
  final void Function(String field) onPick;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: _AddCounterChooserSheet(
        player: player,
        visible: visible,
        coreOrdered: coreOrdered,
        onPick: onPick,
        maxHeight: maxH,
      ),
    );
  }
}

/// Scrollable add-counter list with scrollbar and bottom fade when more items exist.
class _AddCounterChooserSheet extends StatefulWidget {
  const _AddCounterChooserSheet({
    required this.player,
    required this.visible,
    required this.coreOrdered,
    required this.onPick,
    required this.maxHeight,
  });

  final PlayerGameState player;
  final Set<String> visible;
  final List<String> coreOrdered;
  final void Function(String field) onPick;
  final double maxHeight;

  @override
  State<_AddCounterChooserSheet> createState() =>
      _AddCounterChooserSheetState();
}

class _AddCounterChooserSheetState extends State<_AddCounterChooserSheet> {
  final _scrollController = ScrollController();
  double _bottomFadeOpacity = 0;

  /// Platform scroll feel only — never [AlwaysScrollableScrollPhysics], or the
  /// list steals swipe-down and the sheet cannot dismiss when content fits.
  ScrollPhysics get _listPhysics {
    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => const BouncingScrollPhysics(),
      _ => const ClampingScrollPhysics(),
    };
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncScrollAffordance);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncScrollAffordance(),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncScrollAffordance);
    _scrollController.dispose();
    super.dispose();
  }

  void _syncScrollAffordance() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final canScrollList = pos.maxScrollExtent > 12;
    final notAtBottom = pos.pixels < pos.maxScrollExtent - 12;
    final opacity = canScrollList && notAtBottom ? 1.0 : 0.0;
    if ((opacity - _bottomFadeOpacity).abs() > 0.02 && mounted) {
      setState(() => _bottomFadeOpacity = opacity);
    }
  }

  Widget _section(AppColorTokens colors, String title, List<String> ids) {
    final choices = ids
        .where((id) => !widget.visible.contains(id))
        .toList(growable: false);
    if (choices.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            LayoutTokens.gr3,
            LayoutTokens.gr2,
            LayoutTokens.gr3,
            LayoutTokens.gr1,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: FontTokens.hudXs,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: colors.textSecondary.withValues(alpha: 0.75),
            ),
          ),
        ),
        ...choices.map(
          (id) => ListTile(
            leading: SizedBox(
              width: 36,
              height: 28,
              child: Center(
                child: GameplayDialsStripWidget._leadingGlyph(
                  id,
                  20,
                  colors,
                  tintColor: GameplayDialsStripWidget._listIconColor(colors),
                ),
              ),
            ),
            title: Text(
              GameplayDialsStripWidget._labelFor(
                AppLocalizations.of(context),
                widget.player,
                id,
              ),
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => widget.onPick(id),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final addableBuiltIn =
        [
          ...widget.coreOrdered,
          ...GameplayDialIds.presets,
        ].where((id) => !widget.visible.contains(id)).length;
    final fadePad = _bottomFadeOpacity > 0.02 ? 28.0 : 0.0;
    // Handle + title + subtitle stay outside the ListView so swipe-down
    // dismisses like card lookup.
    const chromeReserve = 148.0;
    final maxListH = (widget.maxHeight - chromeReserve).clamp(
      120.0,
      widget.maxHeight,
    );

    return LimitedBox(
      maxHeight: widget.maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              LayoutTokens.gr3,
              LayoutTokens.gr2,
              LayoutTokens.gr3,
              LayoutTokens.gr1,
            ),
            child: const Center(child: GameSheetHandle()),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              LayoutTokens.gr3,
              LayoutTokens.gr1,
              LayoutTokens.gr3,
              LayoutTokens.gr1,
            ),
            child: Text(
              l10n.dialsAddCounterTitle,
              style: GameModalChrome.sheetTitleStyle(context),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: LayoutTokens.gr3),
            child: Text(
              l10n.dialsAddCounterBody(GameplayDialIds.maxStripDials),
              style: TextStyle(
                fontSize: FontTokens.hudSm,
                height: 1.35,
                color: colors.textSecondary.withValues(alpha: 0.88),
              ),
            ),
          ),
          SizedBox(height: LayoutTokens.gr2),
          LimitedBox(
            maxHeight: maxListH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  radius: const Radius.circular(RadiusTokens.sm),
                  child: ListView(
                    controller: _scrollController,
                    shrinkWrap: true,
                    physics: _listPhysics,
                    padding: EdgeInsets.only(
                      bottom: bottomPad + LayoutTokens.gr2 + fadePad,
                    ),
                    children: [
                      _section(
                        colors,
                        l10n.dialsSectionCommon,
                        widget.coreOrdered,
                      ),
                      _section(colors, l10n.dialsSectionTokensZones, [
                        ...GameplayDialIds.presets,
                      ]),
                      if (addableBuiltIn == 0)
                        Padding(
                          padding: EdgeInsets.all(LayoutTokens.gr3),
                          child: Text(
                            l10n.dialsAllBuiltInsOnStrip,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary.withValues(
                                alpha: 0.75,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomPad,
                  height: 52,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _bottomFadeOpacity,
                      duration: MotionTokens.standard,
                      curve: MotionTokens.easeOut,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.surface.withValues(alpha: 0),
                              colors.surface.withValues(alpha: 0.92),
                              colors.surface,
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomPad + 6,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _bottomFadeOpacity,
                      duration: MotionTokens.standard,
                      curve: MotionTokens.easeOut,
                      child: Center(
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: colors.textSecondary.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCounterPillTile extends StatelessWidget {
  final bool isEliminated;
  final VoidCallback onTap;

  const _AddCounterPillTile({required this.isEliminated, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final scheme = Theme.of(context).colorScheme;
    final tone =
        isEliminated
            ? colors.textSecondary
            : (light ? scheme.onPrimaryContainer : colors.onEmphasis);
    final radius = BorderRadius.circular(_kDialPillCornerRadius);
    return Semantics(
      button: true,
      enabled: !isEliminated,
      label: l10n.dialsAddCounterTooltip,
      child: Tooltip(
        message: l10n.dialsAddCounterTooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isEliminated ? null : onTap,
            borderRadius: radius,
            child: Ink(
              height: _kCounterChipHeight,
              decoration: BoxDecoration(
                color:
                    isEliminated
                        ? colors.surface.withValues(alpha: 0.55)
                        : (light ? scheme.primaryContainer : colors.emphasis),
                borderRadius: radius,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutTokens.gr2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    D20Icon(size: _kCounterIconSize, color: tone),
                    const SizedBox(width: 4),
                    Text(
                      l10n.dialsAddCounterChip,
                      style: TextStyle(
                        fontSize: FontTokens.bodyLg,
                        fontWeight: FontWeight.w700,
                        color: tone,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CounterChip extends StatelessWidget {
  const _CounterChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final int value;
  final Widget icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final radius = BorderRadius.circular(_kDialPillCornerRadius);
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label $value',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: Ink(
            height: _kCounterChipHeight,
            decoration: BoxDecoration(
              color:
                  enabled
                      ? Color.alphaBlend(
                        colors.primaryAccent.withValues(
                          alpha: OpacityTokens.soft,
                        ),
                        colors.surface,
                      )
                      : colors.surface.withValues(alpha: 0.55),
              borderRadius: radius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gr2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 4),
                  Text(
                    '$value',
                    style: TextStyle(
                      fontSize: FontTokens.bodyLg,
                      fontWeight: FontWeight.w700,
                      color:
                          enabled ? colors.primaryAccent : colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
