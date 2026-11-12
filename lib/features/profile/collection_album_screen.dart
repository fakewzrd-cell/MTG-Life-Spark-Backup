import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/deck/deck_list_text.dart';
import '../../core/game/scryfall_service.dart';
import '../../core/models/collection_entry.dart';
import '../../core/persistence/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../core/models/owned_album.dart';
import '../../ui/components/ui_app_bar.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/components/ui_snack_bar.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../shared/widgets/deck_shuffle_overlay.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/game_modal_chrome.dart';
import 'album_listing.dart';
import 'collection_add_sheet.dart';
import 'deck_picker_sheet_scaffold.dart';

class CollectionAlbumScreen extends StatelessWidget {
  const CollectionAlbumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
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

enum _AlbumFilter { all, recent, favorite }

enum _AlbumSort { nameAsc, nameDesc }

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
    final byName = indexScryfallCards(fetched);
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
    await ref.read(collectionRepositoryProvider).touchAlbumOpened(album.id);
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (_) => OwnedAlbumPage(albumId: album.id, albumName: album.name),
      ),
    );
    if (changed != false && mounted) await _reload();
  }

  Future<void> _toggleFavorite(OwnedAlbum album) async {
    await ref
        .read(collectionRepositoryProvider)
        .setAlbumFavorited(album.id, !album.favorited);
    if (mounted) await _reload();
  }

  Future<void> _pickFilter() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDeckPickerChoiceSheet<_AlbumFilter>(
      context,
      title: l10n.albumFilter,
      selected: _filter,
      choices: [
        for (final filter in _AlbumFilter.values)
          DeckPickerChoice(
            value: filter,
            title: _albumFilterLabel(l10n, filter),
            key: ValueKey('collection-album-filter-${filter.name}'),
          ),
      ],
    );
    if (!mounted || picked == null) return;
    setState(() => _filter = picked);
  }

  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDeckPickerChoiceSheet<_AlbumSort>(
      context,
      title: l10n.albumSortBy,
      selected: _sort,
      choices: [
        for (final sort in _AlbumSort.values)
          DeckPickerChoice(
            value: sort,
            title: _albumSortLabel(l10n, sort),
            key: ValueKey('collection-album-sort-${sort.name}'),
          ),
      ],
    );
    if (!mounted || picked == null) return;
    setState(() => _sort = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final actionHeight = BlurredBottomAction.height(
      context,
      aboveShellDock: true,
    );
    final repo = ref.read(collectionRepositoryProvider);
    final albums = _visibleAlbums();
    final noMatches = _albums.isNotEmpty && albums.isEmpty;
    return Stack(
      children: [
        Column(
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
                          child: AlbumBrowseChip(
                            key: const ValueKey('collection-album-filter'),
                            icon: Icons.filter_list_rounded,
                            label:
                                _filter == _AlbumFilter.all
                                    ? l10n.albumFilter
                                    : _albumFilterLabel(l10n, _filter),
                            onTap: _pickFilter,
                          ),
                        ),
                        SizedBox(width: LayoutTokens.gr2),
                        Expanded(
                          child: AlbumBrowseChip(
                            key: const ValueKey('collection-album-sort'),
                            icon: Icons.swap_vert_rounded,
                            label:
                                '${l10n.albumSortBy}: ${_albumSortLabel(l10n, _sort)}',
                            onTap: _pickSort,
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
                        padding: EdgeInsets.fromLTRB(
                          LayoutTokens.gr4,
                          LayoutTokens.gr2,
                          LayoutTokens.gr4,
                          actionHeight,
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
                            onFavorite: () => _toggleFavorite(album),
                            favoriteLabel: l10n.collectionAlbumFavorite,
                            unfavoriteLabel: l10n.collectionAlbumUnfavorite,
                          );
                        },
                      ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: BlurredBottomAction(
            aboveShellDock: true,
            child: UiButton(
              label: l10n.collectionNewAlbum,
              icon: const Icon(Icons.add_rounded, size: 22),
              onPressed: _createAlbum,
            ),
          ),
        ),
      ],
    );
  }

  List<OwnedAlbum> _visibleAlbums() {
    final query = _query.trim().toLowerCase();
    final albums = [
      for (final album in _albums)
        if (_albumMatches(album, query)) album,
    ];
    albums.sort((a, b) {
      return switch (_sort) {
        _AlbumSort.nameAsc => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        _AlbumSort.nameDesc => b.name.toLowerCase().compareTo(
          a.name.toLowerCase(),
        ),
      };
    });
    return albums;
  }

  bool _albumMatches(OwnedAlbum album, String query) {
    if (query.isNotEmpty && !album.name.toLowerCase().contains(query)) {
      return false;
    }
    return switch (_filter) {
      _AlbumFilter.all => true,
      _AlbumFilter.recent => album.isRecent,
      _AlbumFilter.favorite => album.favorited,
    };
  }
}

String _albumFilterLabel(AppLocalizations l10n, _AlbumFilter filter) {
  return switch (filter) {
    _AlbumFilter.all => l10n.albumFilterAll,
    _AlbumFilter.recent => l10n.collectionAlbumFilterRecent,
    _AlbumFilter.favorite => l10n.collectionAlbumFilterFavorite,
  };
}

String _albumSortLabel(AppLocalizations l10n, _AlbumSort sort) {
  return switch (sort) {
    _AlbumSort.nameAsc => l10n.albumSortName,
    _AlbumSort.nameDesc => l10n.albumSortNameDesc,
  };
}

class _CollectionAlbumTile extends StatelessWidget {
  const _CollectionAlbumTile({
    required this.album,
    required this.countLabel,
    required this.colors,
    required this.onTap,
    required this.onFavorite,
    required this.favoriteLabel,
    required this.unfavoriteLabel,
    this.imageUrl,
  });

  final OwnedAlbum album;
  final String countLabel;
  final String? imageUrl;
  final AppColorTokens colors;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final String favoriteLabel;
  final String unfavoriteLabel;

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
                    LayoutTokens.gr2,
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
                      IconButton(
                        key: ValueKey('collection-album-favorite-${album.id}'),
                        tooltip:
                            album.favorited ? unfavoriteLabel : favoriteLabel,
                        onPressed: onFavorite,
                        icon: Icon(
                          album.favorited
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color:
                              album.favorited
                                  ? colors.primaryAccent
                                  : colors.textSecondary,
                          size: 28,
                        ),
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

enum CollectionAlbumSheetAction { favorite, rename, delete }

Future<CollectionAlbumSheetAction?> showCollectionAlbumOptions(
  BuildContext context, {
  required bool favorited,
}) {
  return showGameBottomSheet<CollectionAlbumSheetAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      final colors = AppColorTokens.of(ctx);
      void pick(CollectionAlbumSheetAction action) {
        HapticFeedback.selectionClick();
        Navigator.pop(ctx, action);
      }

      return GameSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('collection-album-option-favorite'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                color: colors.primaryAccent,
              ),
              title: Text(
                favorited
                    ? l10n.collectionAlbumUnfavorite
                    : l10n.collectionAlbumFavorite,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: FontTokens.body,
                ),
              ),
              onTap: () => pick(CollectionAlbumSheetAction.favorite),
            ),
            ListTile(
              key: const ValueKey('collection-album-option-rename'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined, color: colors.primaryAccent),
              title: Text(
                l10n.collectionRenameAlbum,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: FontTokens.body,
                ),
              ),
              onTap: () => pick(CollectionAlbumSheetAction.rename),
            ),
            Divider(
              height: LayoutTokens.gr2,
              color: colors.borderSubtle.withValues(alpha: 0.45),
            ),
            ListTile(
              key: const ValueKey('collection-album-option-delete'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: colors.error),
              title: Text(
                l10n.collectionDeleteAlbum,
                style: TextStyle(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                  fontSize: FontTokens.body,
                ),
              ),
              onTap: () => pick(CollectionAlbumSheetAction.delete),
            ),
          ],
        ),
      );
    },
  );
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
  var _loading = true;
  late String _albumName = widget.albumName;
  var _favorited = false;
  late final ShuffleWait _shuffle = ShuffleWait(
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  OwnedAlbum? get _album =>
      ref.read(collectionRepositoryProvider).getAlbum(widget.albumId);

  @override
  void initState() {
    super.initState();
    final album = ref
        .read(collectionRepositoryProvider)
        .getAlbum(widget.albumId);
    if (album != null) {
      _albumName = album.name;
      _favorited = album.favorited;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _shuffle.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final repo = ref.read(collectionRepositoryProvider);
    await repo.init();
    if (!mounted) return;
    final entries = repo.forAlbum(widget.albumId);
    final album = repo.getAlbum(widget.albumId);
    setState(() {
      _entries = entries;
      _loading = false;
      if (album != null) {
        _albumName = album.name;
        _favorited = album.favorited;
      }
    });
    final names = [for (final entry in entries) entry.name];
    if (names.isEmpty) {
      _shuffle.end();
      return;
    }
    final service = ref.read(scryfallServiceProvider);
    final cached = await service.cachedCardsByNames(names);
    if (!mounted) return;
    setState(() {
      _cards = indexScryfallCards(cached);
    });
    if (cached.length >= service.uniqueCardNames(names).length) {
      _shuffle.end();
      return;
    }
    _shuffle.begin();
    final fetched = await service.fetchCardsByNames(names);
    if (!mounted) return;
    setState(() {
      _cards = indexScryfallCards(fetched);
    });
    _shuffle.end();
  }

  Future<void> _changeOwned(String name, int delta) async {
    if (delta == 0) return;
    final repo = ref.read(collectionRepositoryProvider);
    await repo.changeOwned(name, delta: delta, albumId: widget.albumId);
    if (!mounted) return;
    setState(() => _entries = repo.forAlbum(widget.albumId));
  }

  Future<void> _toggleFavorite() async {
    final album = _album;
    if (album == null) return;
    await ref
        .read(collectionRepositoryProvider)
        .setAlbumFavorited(album.id, !album.favorited);
    if (!mounted) return;
    setState(() => _favorited = !album.favorited);
  }

  Future<void> _renameAlbum() async {
    final album = _album;
    if (album == null) return;
    final name = await _askAlbumName(context, initial: album.name);
    if (name == null || !mounted) return;
    await ref.read(collectionRepositoryProvider).renameAlbum(album.id, name);
    if (!mounted) return;
    setState(() => _albumName = name);
  }

  Future<void> _deleteAlbum() async {
    final album = _album;
    if (album == null) return;
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
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _openOptions() async {
    final action = await showCollectionAlbumOptions(
      context,
      favorited: _favorited,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case CollectionAlbumSheetAction.favorite:
        await _toggleFavorite();
      case CollectionAlbumSheetAction.rename:
        await _renameAlbum();
      case CollectionAlbumSheetAction.delete:
        await _deleteAlbum();
    }
  }

  Future<void> _addCards() async {
    final choice = await showCollectionAddSheet(context);
    if (!mounted || choice == null) return;
    if (choice == CollectionAddChoice.paste) {
      await _paste();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final added = await Navigator.of(context, rootNavigator: true).push<int>(
      MaterialPageRoute<int>(
        builder:
            (_) => CollectionSearchPage(
              checkoutLabel: l10n.collectionCartCheckoutAlbum,
              onAdd: (name, count) async {
                await ref
                    .read(collectionRepositoryProvider)
                    .addOwned(name, count: count, albumId: widget.albumId);
                return count;
              },
            ),
      ),
    );
    if (!mounted || added == null || added < 1) return;
    showUiSnackBar(context, l10n.collectionCartSaved(added));
    await _reload();
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
                BlurredBottomAction.height(context, aboveShellDock: true),
              ),
              children: [
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
                          backImageUrl: _backUrl(_cards[_key(entry.name)]),
                          manaCost: _cards[_key(entry.name)]?.manaCost,
                        ),
                    ],
                  ),
                ],
              ],
            );
    final theme = Theme.of(context);
    final titleStyle =
        theme.appBarTheme.titleTextStyle ??
        theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: UiAppBar(
        titleWidget: Row(
          children: [
            Flexible(
              child: Text(
                _albumName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            IconButton(
              key: const ValueKey('collection-album-title-favorite'),
              tooltip:
                  _favorited
                      ? l10n.collectionAlbumUnfavorite
                      : l10n.collectionAlbumFavorite,
              onPressed: _toggleFavorite,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _favorited ? colors.primaryAccent : colors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('collection-album-options'),
            tooltip: l10n.collectionAlbumOptions,
            onPressed: _openOptions,
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: Stack(
        children: [
          list,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BlurredBottomAction(
              aboveShellDock: true,
              child: UiButton(
                label: l10n.collectionAddCards,
                icon: const Icon(Icons.add_rounded, size: 22),
                onPressed: _addCards,
              ),
            ),
          ),
          DeckShuffleOverlay(visible: _shuffle.visible),
        ],
      ),
    );
  }
}

String _key(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String? _faceUrl(ScryfallCard? card) {
  if (card == null) return null;
  return scryfallDisplayCardUrl(card);
}

String? _backUrl(ScryfallCard? card) {
  if (card == null) return null;
  return scryfallDisplayBackUrl(card);
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
