import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug/app_log.dart';
import '../../core/game/scryfall_service.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/ui_app_bar.dart';
import '../../ui/components/ui_snack_bar.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../game/widgets/game_modal_chrome.dart';

enum CollectionAddChoice { search, paste }

Future<CollectionAddChoice?> showCollectionAddSheet(
  BuildContext context, {
  String? searchBody,
  String? pasteBody,
}) {
  return showGameBottomSheet<CollectionAddChoice>(
    context: context,
    showDragHandle: true,
    builder:
        (context) =>
            _CollectionAddSheet(searchBody: searchBody, pasteBody: pasteBody),
  );
}

class _CollectionAddSheet extends StatelessWidget {
  const _CollectionAddSheet({this.searchBody, this.pasteBody});

  final String? searchBody;
  final String? pasteBody;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LayoutTokens.gr4,
          LayoutTokens.gr2,
          LayoutTokens.gr4,
          LayoutTokens.gr4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.search_rounded, color: colors.primaryAccent),
              title: Text(
                l10n.collectionAddSearch,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: FontTokens.body,
                ),
              ),
              subtitle: Text(
                searchBody ?? l10n.collectionAddSearchBody,
                style: TextStyle(color: colors.textSecondary),
              ),
              onTap: () => Navigator.pop(context, CollectionAddChoice.search),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.content_paste_outlined,
                color: colors.primaryAccent,
              ),
              title: Text(
                l10n.deckAlbumPaste,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: FontTokens.body,
                ),
              ),
              subtitle: Text(
                pasteBody ?? l10n.collectionAddPasteBody,
                style: TextStyle(color: colors.textSecondary),
              ),
              onTap: () => Navigator.pop(context, CollectionAddChoice.paste),
            ),
          ],
        ),
      ),
    );
  }
}

class CollectionSearchPage extends ConsumerStatefulWidget {
  const CollectionSearchPage({
    super.key,
    required this.onAdd,
    this.rejectionFor,
  });

  final Future<int> Function(String name, int count) onAdd;

  /// When this returns a message, the card is not added and the message is shown.
  final String? Function(ScryfallCard card)? rejectionFor;

  @override
  ConsumerState<CollectionSearchPage> createState() =>
      _CollectionSearchPageState();
}

class _CollectionSearchPageState extends ConsumerState<CollectionSearchPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ScryfallCard> _results = const [];
  var _searching = false;
  String? _error;
  var _added = false;
  var _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _searchCards(q));
  }

  Future<void> _searchCards(String query) async {
    final requestId = ++_requestId;
    try {
      final cards = await ref.read(scryfallServiceProvider).searchCards(query);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = cards.take(20).toList();
        _searching = false;
        _error =
            _results.isEmpty
                ? AppLocalizations.of(context).lookupNoResults(query)
                : null;
      });
    } catch (e, st) {
      appLog('Collection search failed', error: e, stackTrace: st);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = const [];
        _searching = false;
        _error = AppLocalizations.of(context).lookupNetworkError;
      });
    }
  }

  Future<void> _add(ScryfallCard card) async {
    final l10n = AppLocalizations.of(context);
    final rejection = widget.rejectionFor?.call(card);
    if (rejection != null) {
      showUiSnackBar(context, rejection, isError: true);
      return;
    }
    final count = await showDialog<int>(
      context: context,
      builder: (context) => _OwnedCountDialog(name: card.name),
    );
    if (count == null || !mounted) return;
    final added = await widget.onAdd(card.name, count);
    if (!mounted) return;
    if (added < 1) {
      showUiSnackBar(context, l10n.deckAlbumCannotAdd, isError: true);
      return;
    }
    setState(() => _added = true);
    showUiSnackBar(context, l10n.collectionAddSaved(added, card.name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _added);
      },
      child: Scaffold(
        appBar: UiAppBar(title: l10n.collectionSearchTitle),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LayoutTokens.gr4,
                LayoutTokens.gr2,
                LayoutTokens.gr4,
                LayoutTokens.gr2,
              ),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onQuery,
                decoration: InputDecoration(
                  hintText: l10n.collectionSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (_searching) const LinearProgressIndicator(),
            Expanded(
              child:
                  _error != null && _results.isEmpty
                      ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(LayoutTokens.gr4),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                      )
                      : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder:
                            (_, __) =>
                                Divider(height: 1, color: colors.borderSubtle),
                        itemBuilder: (context, index) {
                          final card = _results[index];
                          return ListTile(
                            title: Text(
                              card.name,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle:
                                card.typeLine == null
                                    ? null
                                    : Text(
                                      card.typeLine!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                      ),
                                    ),
                            onTap: () => _add(card),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnedCountDialog extends StatefulWidget {
  const _OwnedCountDialog({required this.name});

  final String name;

  @override
  State<_OwnedCountDialog> createState() => _OwnedCountDialogState();
}

class _OwnedCountDialogState extends State<_OwnedCountDialog> {
  var _count = 1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.collectionAddCountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.name),
          SizedBox(height: LayoutTokens.gr3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed:
                    _count <= 1 ? null : () => setState(() => _count -= 1),
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$_count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: FontTokens.title,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed:
                    _count >= 99 ? null : () => setState(() => _count += 1),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _count),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
