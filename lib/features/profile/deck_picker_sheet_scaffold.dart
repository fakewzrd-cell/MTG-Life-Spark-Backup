import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/game_modal_chrome.dart';

/// Shared layout for Format / Style / Bracket searchable pickers.
///
/// - Sheet hugs short lists (no forced empty band under the last row)
/// - Caps tall lists with [Flexible] + [FlexFit.loose] so chrome growth
///   (large text / long titles) cannot overflow the sheet
class DeckPickerSheetScaffold extends StatelessWidget {
  const DeckPickerSheetScaffold({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.searchField,
    this.separatorHeight = LayoutTokens.gr1,
  });

  final String title;
  final Widget? searchField;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double separatorHeight;

  /// Max fraction of screen height for the whole sheet.
  static const double maxSheetFraction = 0.92;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Root-navigator sheets already cover the floating shell dock. Keep only
    // the system inset so the last row is not cropped as a fake scroll cue.
    final systemBottom = media.viewPadding.bottom;
    final sheetMedia = media.copyWith(
      padding: media.padding.copyWith(bottom: systemBottom),
    );
    final maxSheetH = sheetMedia.size.height * maxSheetFraction;
    final keyboardInset = sheetMedia.viewInsets.bottom;

    return MediaQuery(
      data: sheetMedia,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetH),
          child: GameSheetBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GameSheetHeader(title: title),
                if (searchField != null) ...[
                  SizedBox(height: LayoutTokens.gr2),
                  searchField!,
                ],
                SizedBox(height: LayoutTokens.gr2),
                Flexible(
                  fit: FlexFit.loose,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.only(bottom: LayoutTokens.gr2),
                    itemCount: itemCount,
                    separatorBuilder:
                        (_, __) => SizedBox(height: separatorHeight),
                    itemBuilder: itemBuilder,
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

/// Selectable row used by Format / Style / Bracket picker sheets.
class DeckPickerChoiceTile extends StatelessWidget {
  const DeckPickerChoiceTile({
    super.key,
    required this.title,
    required this.isSelected,
    required this.onTap,
    this.subtitle,
    this.subtitleMaxLines = 2,
  });

  final String title;
  final String? subtitle;
  final int subtitleMaxLines;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: RadiusTokens.radiusXl,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                isSelected
                    ? colors.primaryAccent.withValues(alpha: 0.12)
                    : colors.surface,
            borderRadius: RadiusTokens.radiusXl,
            border: Border.all(
              color:
                  isSelected
                      ? colors.primaryAccent.withValues(alpha: 0.5)
                      : colors.borderSubtle.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(LayoutTokens.gr2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: FontTokens.body,
                        ),
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: LayoutTokens.gr0),
                        Text(
                          subtitle!,
                          maxLines: subtitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: FontTokens.sm,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isSelected) ...[
                  SizedBox(width: LayoutTokens.gr2),
                  Icon(
                    Icons.check_circle_rounded,
                    color: colors.primaryAccent,
                    size: 24,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in [showDeckPickerChoiceSheet].
class DeckPickerChoice<T> {
  const DeckPickerChoice({
    required this.value,
    required this.title,
    this.subtitle,
    this.key,
  });

  final T value;
  final String title;
  final String? subtitle;
  final Key? key;
}

/// Same tile listing as Format / Style / Bracket, for short choice lists.
Future<T?> showDeckPickerChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<DeckPickerChoice<T>> choices,
}) {
  return showGameBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder:
        (ctx) => _DeckPickerChoiceSheet<T>(
          title: title,
          selected: selected,
          choices: choices,
        ),
  );
}

class _DeckPickerChoiceSheet<T> extends StatelessWidget {
  const _DeckPickerChoiceSheet({
    required this.title,
    required this.selected,
    required this.choices,
  });

  final String title;
  final T selected;
  final List<DeckPickerChoice<T>> choices;

  void _pick(BuildContext context, T value) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return DeckPickerSheetScaffold(
      title: title,
      itemCount: choices.length,
      itemBuilder: (context, i) {
        final choice = choices[i];
        return DeckPickerChoiceTile(
          key: choice.key,
          title: choice.title,
          subtitle: choice.subtitle,
          isSelected: choice.value == selected,
          onTap: () => _pick(context, choice.value),
        );
      },
    );
  }
}
