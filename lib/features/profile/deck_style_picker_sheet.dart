import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/deck_style.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/deck_style_l10n.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/game_modal_chrome.dart';
import 'deck_picker_sheet_scaffold.dart';

/// Result of a style picker. [style] is `null` when the user chose All.
class DeckStyleFilterPick {
  const DeckStyleFilterPick.all() : style = null;
  const DeckStyleFilterPick.style(DeckStyle this.style);
  final DeckStyle? style;
}

Future<DeckStyleFilterPick?> _showDeckStylePicker(
  BuildContext context, {
  DeckStyle? selected,
  bool includeAll = false,
}) {
  return showGameBottomSheet<DeckStyleFilterPick>(
    context: context,
    isScrollControlled: true,
    builder:
        (ctx) =>
            _DeckStylePickerSheet(initial: selected, includeAll: includeAll),
  );
}

/// Searchable list of [DeckStyle] values for create/edit deck flows.
Future<DeckStyle?> showDeckStylePickerSheet(
  BuildContext context, {
  DeckStyle? selected,
}) async {
  final picked = await _showDeckStylePicker(context, selected: selected);
  return picked?.style;
}

/// Library filter: All is a real choice, distinct from dismissing the sheet.
Future<DeckStyleFilterPick?> showDeckStyleFilterSheet(
  BuildContext context, {
  DeckStyle? selected,
}) {
  return _showDeckStylePicker(context, selected: selected, includeAll: true);
}

class _DeckStylePickerSheet extends StatefulWidget {
  const _DeckStylePickerSheet({this.initial, this.includeAll = false});

  final DeckStyle? initial;
  final bool includeAll;

  @override
  State<_DeckStylePickerSheet> createState() => _DeckStylePickerSheetState();
}

class _DeckStylePickerSheetState extends State<_DeckStylePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DeckStyle> _filtered(AppLocalizations l10n) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return DeckStyle.values;
    return DeckStyle.values.where((s) {
      final name = localizedDeckStyleName(l10n, s).toLowerCase();
      final desc = localizedDeckStyleDescription(l10n, s).toLowerCase();
      return name.contains(q) ||
          desc.contains(q) ||
          s.displayName.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          s.id.contains(q);
    }).toList();
  }

  void _pick(DeckStyle style) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, DeckStyleFilterPick.style(style));
  }

  void _pickAll() {
    HapticFeedback.selectionClick();
    Navigator.pop(context, const DeckStyleFilterPick.all());
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

    final filtered = _filtered(l10n);
    final showAll = _showAllRow(l10n);
    return DeckPickerSheetScaffold(
      title: l10n.stylePickerTitle,
      searchField: TextField(
        controller: _searchCtrl,
        scrollPadding: const EdgeInsets.only(
          bottom: LayoutTokens.gr6 * 2 + LayoutTokens.gr4,
        ),
        decoration: InputDecoration(
          hintText: l10n.stylePickerSearchHint,
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
            key: const ValueKey('deck-style-filter-all'),
            title: l10n.albumFilterAll,
            isSelected: widget.initial == null,
            onTap: _pickAll,
          );
        }
        final style = filtered[showAll ? i - 1 : i];
        return DeckPickerChoiceTile(
          key: ValueKey('deck-style-${style.id}'),
          title: localizedDeckStyleName(l10n, style),
          subtitle: localizedDeckStyleDescription(l10n, style),
          isSelected: widget.initial == style,
          onTap: () => _pick(style),
        );
      },
    );
  }
}

/// Tappable row showing the chosen style (or placeholder).
class DeckStylePickerField extends StatelessWidget {
  const DeckStylePickerField({
    super.key,
    required this.selected,
    required this.onPick,
    this.errorText,
  });

  final DeckStyle? selected;
  final VoidCallback onPick;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final label =
        selected != null
            ? localizedDeckStyleName(l10n, selected!)
            : l10n.stylePickerChoose;
    final hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onPick,
          borderRadius: RadiusTokens.radiusXl,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.stylePickerFieldLabel,
              labelStyle: TextStyle(color: colors.textSecondary),
              errorText: hasError ? errorText : null,
              suffixIcon: Icon(
                Icons.unfold_more_rounded,
                color: colors.textSecondary,
              ),
            ),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    selected != null
                        ? colors.textPrimary
                        : colors.textSecondary,
                fontWeight:
                    selected != null ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
