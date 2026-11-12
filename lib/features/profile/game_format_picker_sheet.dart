import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/game/game_format.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/game_modal_chrome.dart';
import 'deck_picker_sheet_scaffold.dart';

/// Result of a format picker. [format] is `null` when the user chose All.
class GameFormatFilterPick {
  const GameFormatFilterPick.all() : format = null;
  const GameFormatFilterPick.format(GameFormat this.format);
  final GameFormat? format;
}

Future<GameFormatFilterPick?> _showGameFormatPicker(
  BuildContext context, {
  GameFormat? selected,
  bool includeAll = false,
}) {
  return showGameBottomSheet<GameFormatFilterPick>(
    context: context,
    isScrollControlled: true,
    builder:
        (ctx) =>
            _GameFormatPickerSheet(initial: selected, includeAll: includeAll),
  );
}

/// Searchable list of [GameFormat] values for create/edit deck flows.
Future<GameFormat?> showGameFormatPickerSheet(
  BuildContext context, {
  GameFormat? selected,
}) async {
  final picked = await _showGameFormatPicker(context, selected: selected);
  return picked?.format;
}

/// Library filter: All is a real choice, distinct from dismissing the sheet.
Future<GameFormatFilterPick?> showGameFormatFilterSheet(
  BuildContext context, {
  GameFormat? selected,
}) {
  return _showGameFormatPicker(context, selected: selected, includeAll: true);
}

String _formatPickerSubtitle(AppLocalizations l10n, GameFormat format) {
  final life = '${format.defaultStartingLife}';
  if (format.isCommanderStyle) {
    return l10n.formatPickerMultiplayerLife(life);
  }
  return l10n.formatPickerConstructedLife(life);
}

class _GameFormatPickerSheet extends StatefulWidget {
  const _GameFormatPickerSheet({this.initial, this.includeAll = false});

  final GameFormat? initial;
  final bool includeAll;

  @override
  State<_GameFormatPickerSheet> createState() => _GameFormatPickerSheetState();
}

class _GameFormatPickerSheetState extends State<_GameFormatPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<GameFormat> _filtered() {
    final q = _query.trim().toLowerCase();
    final ordered = GameFormatDetails.lobbyPickerOrder;
    if (q.isEmpty) return ordered;
    return ordered.where((f) {
      return f.displayName.toLowerCase().contains(q) || f.name.contains(q);
    }).toList();
  }

  void _pick(GameFormat format) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, GameFormatFilterPick.format(format));
  }

  void _pickAll() {
    HapticFeedback.selectionClick();
    Navigator.pop(context, const GameFormatFilterPick.all());
  }

  bool _showAllRow(AppLocalizations l10n) {
    if (!widget.includeAll) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return l10n.albumFilterAll.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final filtered = _filtered();
    final showAll = _showAllRow(l10n);

    return DeckPickerSheetScaffold(
      title: l10n.formatPickerTitle,
      searchField: TextField(
        controller: _searchCtrl,
        scrollPadding: const EdgeInsets.only(
          bottom: LayoutTokens.gr6 * 2 + LayoutTokens.gr4,
        ),
        decoration: InputDecoration(
          hintText: l10n.formatPickerSearchHint,
          prefixIcon: const Icon(Icons.search_rounded),
          hintStyle: TextStyle(color: colors.textSecondary),
        ),
        style: TextStyle(color: colors.textPrimary),
        onChanged: (v) => setState(() => _query = v),
      ),
      itemCount: filtered.length + (showAll ? 1 : 0),
      itemBuilder: (context, i) {
        if (showAll && i == 0) {
          return DeckPickerChoiceTile(
            key: const ValueKey('deck-format-filter-all'),
            title: l10n.albumFilterAll,
            isSelected: widget.initial == null,
            onTap: _pickAll,
          );
        }
        final format = filtered[showAll ? i - 1 : i];
        return DeckPickerChoiceTile(
          key: ValueKey('deck-format-${format.name}'),
          title: format.displayName,
          subtitle: _formatPickerSubtitle(l10n, format),
          isSelected: widget.initial == format,
          onTap: () => _pick(format),
        );
      },
    );
  }
}

/// Tappable row showing the chosen format (matches [DeckStylePickerField]).
class GameFormatPickerField extends StatelessWidget {
  const GameFormatPickerField({
    super.key,
    required this.selected,
    required this.onPick,
  });

  final GameFormat selected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);

    return InkWell(
      onTap: onPick,
      borderRadius: RadiusTokens.radiusXl,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.formatPickerFieldLabel,
          labelStyle: TextStyle(color: colors.textSecondary),
          suffixIcon: Icon(
            Icons.unfold_more_rounded,
            color: colors.textSecondary,
          ),
        ),
        child: Text(
          selected.displayName,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
