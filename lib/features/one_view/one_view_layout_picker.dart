import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/one_view/one_view_layout.dart';
import '../../core/one_view/one_view_state.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import 'one_view_chrome.dart';

/// Centered picker. Options are only the arrangements for the current count.
Future<void> showOneViewLayoutPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context);
  await showOneViewDialog<void>(
    context: context,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final count = ref.watch(
            oneViewProvider.select((s) => s.seats.length),
          );
          final selected = ref.watch(oneViewProvider.select((s) => s.layout));
          final options = OneViewSeatLayout.optionsFor(count);
          return OneViewMenuDialog(
            title: l10n.oneViewLayoutTitle,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 240 ? 2 : 1;
                final choiceWidth =
                    (constraints.maxWidth - 16 * (columns - 1)) / columns;
                return Wrap(
                  spacing: LayoutTokens.gr3,
                  runSpacing: LayoutTokens.gr3,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final option in options)
                      _LayoutChoice(
                        layout: option,
                        width: choiceWidth,
                        label: oneViewLayoutLabel(l10n, option),
                        selected: option == selected,
                        onTap: () {
                          ref.read(oneViewProvider.notifier).setLayout(option);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                );
              },
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
    required this.width,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final OneViewSeatLayout layout;
  final double width;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final border = selected ? colors.primaryAccent : colors.borderSubtle;
    return Semantics(
      selected: selected,
      child: SizedBox(
        width: width,
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
                  Stack(
                    children: [
                      SizedBox(
                        height: width < 150 ? 80 : 100,
                        child: buildOneViewSeatSplit(
                          split: layout.split,
                          tile:
                              (_, upsideDown) => _LayoutBlock(
                                selected: selected,
                                upsideDown: upsideDown,
                              ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: colors.primaryAccent,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: LayoutTokens.gr1),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
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
