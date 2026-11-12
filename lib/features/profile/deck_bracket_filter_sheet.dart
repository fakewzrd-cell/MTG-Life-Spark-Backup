import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../game/widgets/game_modal_chrome.dart';
import 'deck_picker_sheet_scaffold.dart';

/// `null` = any bracket, `-1` = no bracket set, `1`–`5` = that level.
const int kLibraryBracketUnset = -1;

/// Result of a bracket filter picker. [value] is `null` for All.
class DeckBracketFilterPick {
  const DeckBracketFilterPick.all() : value = null;
  const DeckBracketFilterPick.unset() : value = kLibraryBracketUnset;
  const DeckBracketFilterPick.level(int this.value)
    : assert(value >= 1 && value <= 5);

  final int? value;
}

/// Library filter: All / No bracket / 1–5, same listing as Style and Format.
Future<DeckBracketFilterPick?> showDeckBracketFilterSheet(
  BuildContext context, {
  int? selected,
}) {
  return showGameBottomSheet<DeckBracketFilterPick>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _DeckBracketFilterSheet(initial: selected),
  );
}

class _DeckBracketFilterSheet extends StatelessWidget {
  const _DeckBracketFilterSheet({this.initial});

  final int? initial;

  void _pop(BuildContext context, DeckBracketFilterPick pick) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, pick);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const levels = [1, 2, 3, 4, 5];
    return DeckPickerSheetScaffold(
      title: l10n.decksFilterBracket,
      itemCount: 2 + levels.length,
      itemBuilder: (context, i) {
        if (i == 0) {
          return DeckPickerChoiceTile(
            key: const ValueKey('deck-bracket-filter-all'),
            title: l10n.albumFilterAll,
            isSelected: initial == null,
            onTap: () => _pop(context, const DeckBracketFilterPick.all()),
          );
        }
        if (i == 1) {
          return DeckPickerChoiceTile(
            key: const ValueKey('deck-bracket-filter-unset'),
            title: l10n.decksFilterNoBracket,
            isSelected: initial == kLibraryBracketUnset,
            onTap: () => _pop(context, const DeckBracketFilterPick.unset()),
          );
        }
        final n = levels[i - 2];
        return DeckPickerChoiceTile(
          key: ValueKey('deck-bracket-$n'),
          title: '${l10n.deckAlbumCardBracket} $n',
          isSelected: initial == n,
          onTap: () => _pop(context, DeckBracketFilterPick.level(n)),
        );
      },
    );
  }
}
