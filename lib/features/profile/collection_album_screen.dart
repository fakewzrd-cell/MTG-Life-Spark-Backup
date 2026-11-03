import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/deck/bracket_names.dart';
import '../../core/deck/deck_list_text.dart';
import '../../core/game/scryfall_service.dart';
import '../../core/models/collection_entry.dart';
import '../../core/persistence/collection_repository.dart';
import '../../core/persistence/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../core/models/owned_album.dart';
import '../../ui/components/ui_app_bar.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/components/ui_snack_bar.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/game_modal_chrome.dart';
import 'album_listing.dart';
import 'collection_add_sheet.dart';

class _Suggestion {
  const _Suggestion({
    required this.commander,
    required this.owned,
    required this.total,
  });

  final String commander;
  final int owned;
  final int total;
}

class CollectionAlbumScreen extends StatelessWidget {
  const CollectionAlbumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UiAppBar(title: AppLocalizations.of(context).collectionTitle),
      body: const CollectionAlbumView(),
    );
  }
}

/// Albums of cards the player owns, inside the decks library toggle.
class CollectionAlbumView extends ConsumerStatefulWidget {
  const CollectionAlbumView({super.key});

  @override
  ConsumerState<CollectionAlbumView> createState() =>
      _CollectionAlbumViewState();
}

enum _AlbumFilter { all, withCards, empty }

enum _AlbumSort { nameAsc, nameDesc, cards }

class _CollectionAlbumViewState extends ConsumerState<CollectionAlbumView> {
  List<OwnedAlbum> _albums = const [];
  Map<String, String> _covers = const {};
  var _loading = true;
  final _search = TextEditingController();
  var _query = '';
  var _filter = _AlbumFilter.all;
  var _sort = _AlbumSort.nameAsc;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final repo = ref.read(collectionRepositoryProvider);
    final looseName = AppLocalizations.of(context).collectionTitle;
    await repo.init();
    await repo.adoptLooseCards(looseName);
    if (!mounted) return;
    final albums = repo.getAlbums();
    final firstNames = <String, String>{};
    for (final album in albums) {
      final cards = repo.forAlbum(album.id);
      if (cards.isNotEmpty) firstNames[album.id] = cards.first.name;
    }
    setState(() {
      _albums = albums;
      _loading = false;
    });
    if (firstNames.isEmpty) {
      if (mounted) setState(() => _covers = const {});
      return;
    }
    final fetched = await ref
        .read(scryfallServiceProvider)
        .fetchCardsByNames(firstNames.values.toList());
    if (!mounted) return;
    final byName = {for (final card in fetched) _key(card.name): card};
    final covers = <String, String>{};
    for (final entry in firstNames.entries) {
      final card = byName[_key(entry.value)];
      final url = card?.imageUrl;
      final face = card?.cardFaceUrl;
      final image =
          url != null && url.isNotEmpty
              ? url
              : (face != null && face.isNotEmpty ? face : null);
      if (image != null) covers[entry.key] = image;
    }
    setState(() => _covers = covers);
  }

  Future<void> _createAlbum() async {
    final name = await _askAlbumName(context);
    if (name == null || !mounted) return;
    final album = await ref
        .read(collectionRepositoryProvider)
        .createAlbum(name);
    if (!mounted) return;
    await _open(album);
  }

  Future<void> _open(OwnedAlbum album) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (_) => OwnedAlbumPage(albumId: album.id, albumName: album.name),
      ),
    );
    if (changed != false && mounted) await _reload();
  }

  Future<void> _rename(OwnedAlbum album) async {
    final name = await _askAlbumName(context, initial: album.name);
    if (name == null || !mounted) return;
    await ref.read(collectionRepositoryProvider).renameAlbum(album.id, name);
    if (mounted) await _reload();
  }

  Future<void> _delete(OwnedAlbum album) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showGameConfirmDialog(
      context: context,
      title: l10n.collectionDeleteAlbum,
      message: l10n.collectionDeleteAlbumBody(album.name),
      confirmLabel: l10n.collectionDeleteAlbum,
      destructive: true,
    );
    if (ok != true || !mounted) return;
    await ref.read(collectionRepositoryProvider).deleteAlbum(album.id);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom + LayoutTokens.gr2;
    final repo = ref.read(collectionRepositoryProvider);
    final albums = _visibleAlbums(repo);
    final noMatches = _albums.isNotEmpty && albums.isEmpty;
    return Column(
      children: [
        if (!_loading && _albums.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LayoutTokens.gr4,
              LayoutTokens.gr2,
              LayoutTokens.gr4,
              0,
            ),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: l10n.collectionAlbumSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintStyle: TextStyle(color: colors.textSecondary),
                    suffixIcon:
                        _query.isEmpty
                            ? null
                            : IconButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                  ),
                  style: TextStyle(color: colors.textPrimary),
                ),
                SizedBox(height: LayoutTokens.gr2),
                Row(
                  children: [
                    Expanded(
                      child: AlbumBrowseMenu<_AlbumFilter>(
                        icon: Icons.filter_list_rounded,
                        label:
                            _filter == _AlbumFilter.all
                                ? l10n.albumFilter
                                : _albumFilterLabel(l10n, _filter),
                        value: _filter,
                        onSelected: (value) => setState(() => _filter = value),
                        items: [
                          for (final filter in _AlbumFilter.values)
                            PopupMenuItem(
                              value: filter,
                              child: Text(_albumFilterLabel(l10n, filter)),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: LayoutTokens.gr2),
                    Expanded(
                      child: AlbumBrowseMenu<_AlbumSort>(
                        icon: Icons.swap_vert_rounded,
                        label:
                            '${l10n.albumSortBy}: ${_albumSortLabel(l10n, _sort)}',
                        value: _sort,
                        onSelected: (value) => setState(() => _sort = value),
                        items: [
                          for (final sort in _AlbumSort.values)
                            PopupMenuItem(
                              value: sort,
                              child: Text(_albumSortLabel(l10n, sort)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child:
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _albums.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(LayoutTokens.gr4),
                      child: Text(
                        l10n.collectionAlbumsEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: FontTokens.body,
                        ),
                      ),
                    ),
                  )
                  : noMatches
                  ? Center(
                    child: Text(
                      l10n.collectionAlbumNoMatches,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: FontTokens.body,
                      ),
                    ),
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      LayoutTokens.gr4,
                      LayoutTokens.gr2,
                      LayoutTokens.gr4,
                      LayoutTokens.gr3,
                    ),
                    itemCount: albums.length,
                    separatorBuilder:
                        (_, __) => SizedBox(height: LayoutTokens.gr2),
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return _CollectionAlbumTile(
                        album: album,
                        countLabel: l10n.collectionAlbumCount(
                          repo.cardCount(album.id),
                        ),
                        imageUrl: _covers[album.id],
                        colors: colors,
                        onTap: () => _open(album),
                        onRename: () => _rename(album),
                        onDelete: () => _delete(album),
                        renameLabel: l10n.collectionRenameAlbum,
                        deleteLabel: l10n.collectionDeleteAlbum,
                      );
                    },
                  ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            LayoutTokens.gr4,
            LayoutTokens.gr2,
            LayoutTokens.gr4,
            bottom,
          ),
          child: UiButton(
            label: l10n.collectionNewAlbum,
            icon: const Icon(Icons.add_rounded, size: 22),
            onPressed: _createAlbum,
          ),
        ),
      ],
    );
  }

  List<OwnedAlbum> _visibleAlbums(CollectionRepository repo) {
    final query = _query.trim().toLowerCase();
    final albums = [
      for (final album in _albums)
        if (_albumMatches(album, repo, query)) album,
    ];
    albums.sort((a, b) {
      return switch (_sort) {
        _AlbumSort.nameAsc => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        _AlbumSort.nameDesc => b.name.toLowerCase().compareTo(
          a.name.toLowerCase(),
        ),
        _AlbumSort.cards => repo
            .cardCount(b.id)
            .compareTo(repo.cardCount(a.id)),
      };
    });
    return albums;
  }

  bool _albumMatches(
    OwnedAlbum album,
    CollectionRepository repo,
    String query,
  ) {
    if (query.isNotEmpty && !album.name.toLowerCase().contains(query)) {
      return false;
    }
    final count = repo.cardCount(album.id);
    return switch (_filter) {
      _AlbumFilter.all => true,
      _AlbumFilter.withCards => count > 0,
      _AlbumFilter.empty => count == 0,
    };
  }
}

String _albumFilterLabel(AppLocalizations l10n, _AlbumFilter filter) {
  return switch (filter) {
    _AlbumFilter.all => l10n.albumFilterAll,
    _AlbumFilter.withCards => l10n.collectionAlbumFilterWithCards,
    _AlbumFilter.empty => l10n.collectionAlbumFilterEmpty,
  };
}

String _albumSortLabel(AppLocalizations l10n, _AlbumSort sort) {
  return switch (sort) {
    _AlbumSort.nameAsc => l10n.albumSortName,
    _AlbumSort.nameDesc => l10n.albumSortNameDesc,
    _AlbumSort.cards => l10n.collectionAlbumSortCards,
  };
}

class _CollectionAlbumTile extends StatelessWidget {
  const _CollectionAlbumTile({
    required this.album,
    required this.countLabel,
    required this.colors,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.renameLabel,
    required this.deleteLabel,
    this.imageUrl,
  });

  final OwnedAlbum album;
  final String countLabel;
  final String? imageUrl;
  final AppColorTokens colors;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final String renameLabel;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    final artUrl = imageUrl;
    final hasArt = artUrl != null && artUrl.isNotEmpty;
    return Material(
      color: colors.surface,
      borderRadius: RadiusTokens.radiusLg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
            final artWidth =
                hasArt ? (tileWidth * 0.34).clamp(112.0, 200.0) : 0.0;
            final textInset =
                hasArt ? artWidth + LayoutTokens.gr2 : LayoutTokens.gr4;
            return Stack(
              children: [
                if (hasArt)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: artWidth,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) {
                        return const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xFFFFFFFF),
                            Color(0xFFFFFFFF),
                            Color(0xD9FFFFFF),
                            Color(0x8CFFFFFF),
                            Color(0x47FFFFFF),
                            Color(0x14FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                          stops: [0.0, 0.42, 0.58, 0.7, 0.82, 0.92, 1.0],
                        ).createShader(bounds);
                      },
                      child: CachedNetworkImage(
                        imageUrl: artUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    textInset,
                    LayoutTokens.gr2,
                    LayoutTokens.gr1,
                    LayoutTokens.gr2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: FontTokens.body,
                              ),
                            ),
                            SizedBox(height: LayoutTokens.gr0),
                            Text(
                              countLabel,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: FontTokens.sm,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') onRename();
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder:
                            (context) => [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text(renameLabel),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(deleteLabel),
                              ),
                            ],
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

Future<String?> _askAlbumName(BuildContext context, {String? initial}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _AlbumNameDialog(initial: initial),
  );
}

class _AlbumNameDialog extends StatefulWidget {
  const _AlbumNameDialog({this.initial});

  final String? initial;

  @override
  State<_AlbumNameDialog> createState() => _AlbumNameDialogState();
}

class _AlbumNameDialogState extends State<_AlbumNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.collectionAlbumNameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: l10n.collectionAlbumNameHint),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(onPressed: _save, child: Text(l10n.commonSave)),
      ],
    );
  }
}

class OwnedAlbumPage extends ConsumerStatefulWidget {
  const OwnedAlbumPage({
    super.key,
    required this.albumId,
    required this.albumName,
  });

  final String albumId;
  final String albumName;

  @override
  ConsumerState<OwnedAlbumPage> createState() => _OwnedAlbumPageState();
}

class _OwnedAlbumPageState extends ConsumerState<OwnedAlbumPage> {
  List<CollectionEntry> _entries = const [];
  Map<String, ScryfallCard> _cards = const {};
  List<_Suggestion> _suggestions = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final repo = ref.read(collectionRepositoryProvider);
    await repo.init();
    if (!mounted) return;
    final entries = repo.forAlbum(widget.albumId);
    setState(() {
      _entries = entries;
      _loading = false;
    });
    final fetched = await ref.read(scryfallServiceProvider).fetchCardsByNames([
      for (final entry in entries) entry.name,
    ]);
    if (!mounted) return;
    setState(() {
      _cards = {for (final card in fetched) _key(card.name): card};
    });
    await _loadSuggestions(entries);
  }

  Future<void> _loadSuggestions(List<CollectionEntry> entries) async {
    final commanders = <String>[];
    for (final entry in entries) {
      final type = _cards[_key(entry.name)]?.typeLine?.toLowerCase() ?? '';
      final legendary = type.contains('legendary');
      final leader = type.contains('creature') || type.contains('planeswalker');
      if (legendary && leader) commanders.add(entry.name);
      if (commanders.length == 6) break;
    }
    final owned = {for (final entry in entries) bracketNameKey(entry.name)};
    final suggestions = <_Suggestion>[];
    final client = ref.read(edhrecClientProvider);
    for (final commander in commanders) {
      final meta = await client.commanderMeta(commander);
      if (meta == null || meta.commonCards.isEmpty) continue;
      var count = owned.contains(bracketNameKey(commander)) ? 1 : 0;
      for (final card in meta.commonCards) {
        if (owned.contains(bracketNameKey(card))) count++;
      }
      suggestions.add(
        _Suggestion(
          commander: commander,
          owned: count,
          total: meta.commonCards.length + 1,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _suggestions = suggestions);
  }

  Future<void> _changeOwned(String name, int delta) async {
    if (delta == 0) return;
    final repo = ref.read(collectionRepositoryProvider);
    await repo.changeOwned(name, delta: delta, albumId: widget.albumId);
    if (!mounted) return;
    setState(() => _entries = repo.forAlbum(widget.albumId));
  }

  Future<void> _addCards() async {
    final choice = await showCollectionAddSheet(context);
    if (!mounted || choice == null) return;
    if (choice == CollectionAddChoice.paste) {
      await _paste();
      return;
    }
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (_) => CollectionSearchPage(
              onAdd: (name, count) async {
                await ref
                    .read(collectionRepositoryProvider)
                    .addOwned(name, count: count, albumId: widget.albumId);
                return count;
              },
            ),
      ),
    );
    if (added == true && mounted) await _reload();
  }

  Future<void> _paste() async {
    final l10n = AppLocalizations.of(context);
    if (_entries.isNotEmpty) {
      final ok = await showGameConfirmDialog(
        context: context,
        title: l10n.deckAlbumReplaceTitle,
        message: l10n.collectionAlbumReplaceBody,
        confirmLabel: l10n.deckAlbumReplaceConfirm,
      );
      if (ok != true || !mounted) return;
    }
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _CollectionPasteDialog(),
    );
    if (text == null || !mounted) return;
    final parsed = parseDeckList(text, identifyCommander: false);
    if (parsed.cards.isEmpty) {
      showUiSnackBar(context, l10n.deckAlbumPasteEmpty, isError: true);
      return;
    }
    await ref
        .read(collectionRepositoryProvider)
        .replaceAlbum(widget.albumId, parsed.cards);
    if (!mounted) return;
    showUiSnackBar(context, l10n.deckAlbumPasteSaved(parsed.totalCards));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final listing = ref.watch(albumListingProvider);

    final list =
        _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
              padding: EdgeInsets.fromLTRB(
                LayoutTokens.gr4,
                LayoutTokens.gr2,
                LayoutTokens.gr4,
                BlurredBottomAction.height(context),
              ),
              children: [
                if (_suggestions.isNotEmpty) ...[
                  SizedBox(height: LayoutTokens.gr4),
                  Text(
                    l10n.collectionSuggestions,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: FontTokens.title,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: LayoutTokens.gr1),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _suggestions.length,
                      separatorBuilder:
                          (_, __) => SizedBox(width: LayoutTokens.gr1),
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        final short = suggestion.commander.split(',').first;
                        return Chip(
                          label: Text(
                            l10n.collectionSuggestionCount(
                              short,
                              suggestion.owned,
                              suggestion.total,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (_entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: LayoutTokens.gr5),
                    child: Text(
                      l10n.collectionAlbumEmpty,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: FontTokens.body,
                      ),
                    ),
                  )
                else ...[
                  SizedBox(height: LayoutTokens.gr3),
                  AlbumCardBrowser(
                    listing: listing,
                    onListing: (value) {
                      ref.read(albumListingProvider.notifier).state = value;
                    },
                    totalCount: _entries.fold<int>(
                      0,
                      (sum, entry) => sum + entry.count,
                    ),
                    onCount: (card, delta) => _changeOwned(card.name, delta),
                    cards: [
                      for (final entry in _entries)
                        AlbumListCard(
                          name: entry.name,
                          count: entry.count,
                          group: deckCardGroupForTypeLine(
                            _cards[_key(entry.name)]?.typeLine,
                          ),
                          imageUrl: _faceUrl(_cards[_key(entry.name)]),
                          manaCost: _cards[_key(entry.name)]?.manaCost,
                        ),
                    ],
                  ),
                ],
              ],
            );
    return Scaffold(
      appBar: UiAppBar(title: widget.albumName),
      body: Stack(
        children: [
          list,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BlurredBottomAction(
              child: UiButton(
                label: l10n.collectionAddCards,
                icon: const Icon(Icons.add_rounded, size: 22),
                onPressed: _addCards,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _key(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String? _faceUrl(ScryfallCard? card) {
  final face = card?.cardFaceUrl;
  if (face != null && face.isNotEmpty) return face;
  return card?.imageUrl;
}

class _CollectionPasteDialog extends StatefulWidget {
  const _CollectionPasteDialog();

  @override
  State<_CollectionPasteDialog> createState() => _CollectionPasteDialogState();
}

class _CollectionPasteDialogState extends State<_CollectionPasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.collectionPasteTitle),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 8,
          maxLines: 14,
          decoration: InputDecoration(hintText: l10n.collectionPasteHint),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.deckAlbumPasteAction),
        ),
      ],
    );
  }
}
