import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/one_view/one_view_layout.dart';
import '../../core/one_view/one_view_state.dart';
import '../../features/game/widgets/game_modal_chrome.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';

/// Centered picker. Options are only the arrangements for the current count.
Future<void> showOneViewLayoutPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context);
  final colors = AppColorTokens.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.72;
      return Consumer(
        builder: (context, ref, _) {
          final count = ref.watch(
            oneViewProvider.select((s) => s.seats.length),
          );
          final selected = ref.watch(oneViewProvider.select((s) => s.layout));
          final options = OneViewSeatLayout.optionsFor(count);
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
                l10n.oneViewLayoutTitle,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: FontTokens.headline,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onClose: () => Navigator.pop(ctx),
            ),
            contentPadding: const EdgeInsets.fromLTRB(
              LayoutTokens.gr3,
              LayoutTokens.gr3,
              LayoutTokens.gr3,
              LayoutTokens.gr4,
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: LayoutTokens.gr3,
                  runSpacing: LayoutTokens.gr3,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final option in options)
                      _LayoutChoice(
                        layout: option,
                        label: oneViewLayoutLabel(l10n, option),
                        selected: option == selected,
                        onTap: () {
                          ref.read(oneViewProvider.notifier).setLayout(option);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

String oneViewLayoutLabel(AppLocalizations l10n, OneViewSeatLayout layout) {
  return switch (layout) {
    OneViewSeatLayout.full => l10n.oneViewLayoutFull,
    OneViewSeatLayout.stacked => l10n.oneViewLayoutStacked,
    OneViewSeatLayout.sideBySide => l10n.oneViewLayoutSideBySide,
    OneViewSeatLayout.oneOverTwo => l10n.oneViewLayoutOneOverTwo,
    OneViewSeatLayout.twoOverOne => l10n.oneViewLayoutTwoOverOne,
    OneViewSeatLayout.oneBesideTwo => l10n.oneViewLayoutOneBesideTwo,
    OneViewSeatLayout.twoBesideOne => l10n.oneViewLayoutTwoBesideOne,
    OneViewSeatLayout.grid2x2 => l10n.oneViewLayoutGrid2x2,
    OneViewSeatLayout.oneOverThree => l10n.oneViewLayoutOneOverThree,
    OneViewSeatLayout.threeOverOne => l10n.oneViewLayoutThreeOverOne,
    OneViewSeatLayout.twoOverThree => l10n.oneViewLayoutTwoOverThree,
    OneViewSeatLayout.threeOverTwo => l10n.oneViewLayoutThreeOverTwo,
    OneViewSeatLayout.threeOverThree => l10n.oneViewLayoutThreeOverThree,
    OneViewSeatLayout.threeRowsOfTwo => l10n.oneViewLayoutThreeRowsOfTwo,
  };
}

class _LayoutChoice extends StatelessWidget {
  const _LayoutChoice({
    required this.layout,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final OneViewSeatLayout layout;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final border = selected ? colors.primaryAccent : colors.borderSubtle;
    return SizedBox(
      width: 148,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RadiusTokens.radiusLg,
          side: BorderSide(color: border, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LayoutTokens.gr2,
              LayoutTokens.gr2,
              LayoutTokens.gr2,
              LayoutTokens.gr2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 112,
                  child: buildOneViewSeatSplit(
                    split: layout.split,
                    tile:
                        (_, upsideDown) => _LayoutBlock(
                          selected: selected,
                          upsideDown: upsideDown,
                        ),
                  ),
                ),
                const SizedBox(height: LayoutTokens.gr2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: FontTokens.body,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
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

class _LayoutBlock extends StatelessWidget {
  const _LayoutBlock({required this.selected, required this.upsideDown});

  final bool selected;
  final bool upsideDown;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final block = Padding(
      padding: const EdgeInsets.all(3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primaryAccent.withValues(
            alpha: selected ? OpacityTokens.soft : OpacityTokens.faint,
          ),
          borderRadius: RadiusTokens.radiusSm,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SizedBox(
              width: 14,
              height: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.textPrimary.withValues(
                    alpha: OpacityTokens.half,
                  ),
                  borderRadius: RadiusTokens.radiusPill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!upsideDown) return block;
    return RotatedBox(quarterTurns: 2, child: block);
  }
}

/// Shared row/column split for the table and the layout diagram.
Widget buildOneViewSeatSplit({
  required SeatSplit split,
  required Widget Function(int index, bool upsideDown) tile,
}) {
  return _buildOneViewSeatSplit(split, tile, 0, 1);
}

Widget _buildOneViewSeatSplit(
  SeatSplit split,
  Widget Function(int index, bool upsideDown) tile,
  double start,
  double end,
) {
  return switch (split) {
    SeatLeaf(:final index) => tile(index, oneViewBandUpsideDown(start, end)),
    SeatRow(:final children) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          Expanded(child: _buildOneViewSeatSplit(child, tile, start, end)),
      ],
    ),
    SeatCol(:final children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          Expanded(
            child: _buildOneViewSeatSplit(
              children[i],
              tile,
              start + (end - start) * i / children.length,
              start + (end - start) * (i + 1) / children.length,
            ),
          ),
      ],
    ),
  };
}
