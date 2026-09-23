import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/constants/app_icons.dart';
import '../../../shared/utils/game_haptics.dart';
import '../../../ui/tokens/font_tokens.dart';
import '../../../ui/tokens/layout_tokens.dart';
import '../../../ui/tokens/opacity_tokens.dart';
import 'card_lookup_sheet.dart';
import 'game_colors.dart';

/// Asset for the Play tab (fanned cards) — replaces generic controller icon.
const String kGamePlayTabIconAsset = AppIcons.playTabCards;

/// Play · Stack · Lookup row — use inside [GameHudHeader].
///
/// Play and Stack stay icon-only; Lookup is labeled Rules.
/// Lookup is a utility action (opens a sheet), not a peer tab.
/// History lives on Table overview (sheet), not in this strip.
class GameMainTabBarStrip extends StatelessWidget {
  const GameMainTabBarStrip({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.accentColor,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Color? accentColor;

  static const double iconSize = 22;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final dividerColor = colors.textSecondary.withValues(alpha: 0.12);
    final resolvedAccent = accentColor ?? colors.primaryAccent;
    final segments = <_GameMainTabSpec>[
      _GameMainTabSpec(
        index: 0,
        label: l10n.gameTabPlay,
        iconAsset: kGamePlayTabIconAsset,
      ),
      _GameMainTabSpec(
        index: 1,
        label: l10n.gameTabStack,
        icon: Icons.layers_rounded,
      ),
    ];

    Widget tab(_GameMainTabSpec segment) => Expanded(
      child: _GameMainTab(
        label: segment.label,
        icon: segment.icon,
        iconAsset: segment.iconAsset,
        selected: selectedIndex == segment.index,
        accentColor: resolvedAccent,
        onTap: () {
          if (selectedIndex == segment.index) return;
          context.gameHapticSelection();
          onSelected(segment.index);
        },
      ),
    );

    Widget divider() =>
        VerticalDivider(width: 1, thickness: 1, color: dividerColor);

    return SizedBox(
      height: LayoutTokens.minTapTarget,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tab(segments[0]), // Play
          divider(),
          tab(segments[1]), // Stack
          divider(),
          const Expanded(child: _CardLookupTabAction()),
        ],
      ),
    );
  }
}

/// Opens Scryfall card lookup without changing the selected main tab.
class _CardLookupTabAction extends StatelessWidget {
  const _CardLookupTabAction();

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final fg = colors.textSecondary;

    return Semantics(
      button: true,
      label: l10n.gameTabLookupSemantics,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            context.gameHapticSelection();
            showCardLookupSheet(context);
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.menu_book_outlined, size: 18, color: fg),
                const SizedBox(height: 2),
                Text(
                  l10n.gameTabLookup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: FontTokens.hudXs,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameMainTabSpec {
  const _GameMainTabSpec({
    required this.index,
    required this.label,
    this.icon,
    this.iconAsset,
  });

  final int index;
  final String label;
  final IconData? icon;
  final String? iconAsset;
}

class _GameMainTab extends StatelessWidget {
  const _GameMainTab({
    required this.label,
    this.icon,
    this.iconAsset,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final String? iconAsset;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  Widget _buildIcon(Color fg) {
    final asset = iconAsset;
    final size = GameMainTabBarStrip.iconSize;
    if (asset != null) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: fg,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
      );
    }
    return Icon(icon ?? Icons.help_outline, size: size, color: fg);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final fg = selected
        ? accentColor
        : colors.textSecondary.withValues(alpha: OpacityTokens.mutedTextMin);
    final bg = selected
        ? accentColor.withValues(alpha: OpacityTokens.soft)
        : Colors.transparent;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: bg,
        child: InkWell(
          onTap: onTap,
          child: Center(child: _buildIcon(fg)),
        ),
      ),
    );
  }
}
