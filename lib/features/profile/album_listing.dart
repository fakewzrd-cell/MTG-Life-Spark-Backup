import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/deck/deck_list_text.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/mana_cost_pips.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import 'card_viewer.dart';
import 'deck_picker_sheet_scaffold.dart';

enum AlbumListing { types, grid, alpha }

enum AlbumSort { nameAsc, nameDesc, count, type }

enum AlbumTypeFilter {
  all,
  creature,
  instant,
  sorcery,
  artifact,
  enchantment,
  planeswalker,
  land,
  other,
}

final albumListingProvider = StateProvider<AlbumListing>(
  (ref) => AlbumListing.types,
);

class AlbumListCard {
  const AlbumListCard({
    required this.name,
    required this.count,
    required this.group,
    this.imageUrl,
    this.backImageUrl,
    this.manaCost,
    this.inclusion,
    this.canAddCopy = true,
    this.warning,
    this.isFaceSlot = false,
    this.isBlank = false,
  });

  final String name;
  final int count;
  final DeckCardGroup group;
  final String? imageUrl;

  /// Other printed face for the 3D preview. Null on single-faced cards.
  final String? backImageUrl;
  final String? manaCost;
  final double? inclusion;
  final bool canAddCopy;

  /// Why this card needs attention, shown beside the row.
  final String? warning;

  /// Pinned commander or cover identity, shown above type groups.
  final bool isFaceSlot;

  /// Empty commander/cover slot waiting for a pick.
  final bool isBlank;

  String get listingKey =>
      isFaceSlot ? (isBlank ? 'face-blank' : 'face') : name;
}

class AlbumListingSwitch extends StatelessWidget {
  const AlbumListingSwitch({
    super.key,
    required this.listing,
    required this.onChanged,
  });

  final AlbumListing listing;
  final ValueChanged<AlbumListing> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    return Wrap(
      spacing: LayoutTokens.gr1,
      children: [
        for (final mode in AlbumListing.values)
          ChoiceChip(
            showCheckmark: false,
            label: Text(
              _listingLabel(l10n, mode),
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: listing == mode ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            selected: listing == mode,
            onSelected: (_) => onChanged(mode),
            selectedColor: colors.surfaceElevated,
            backgroundColor: colors.surface,
            side: BorderSide(
              color:
                  listing == mode ? colors.textSecondary : colors.borderSubtle,
            ),
          ),
      ],
    );
  }
}

String _listingLabel(AppLocalizations l10n, AlbumListing listing) {
  return switch (listing) {
    AlbumListing.types => l10n.deckAlbumViewTypes,
    AlbumListing.grid => l10n.deckAlbumViewGrid,
    AlbumListing.alpha => l10n.deckAlbumViewAlpha,
  };
}

DeckCardGroup? albumTypeGroup(AlbumTypeFilter filter) {
  return switch (filter) {
    AlbumTypeFilter.all => null,
    AlbumTypeFilter.creature => DeckCardGroup.creature,
    AlbumTypeFilter.instant => DeckCardGroup.instant,
    AlbumTypeFilter.sorcery => DeckCardGroup.sorcery,
    AlbumTypeFilter.artifact => DeckCardGroup.artifact,
    AlbumTypeFilter.enchantment => DeckCardGroup.enchantment,
    AlbumTypeFilter.planeswalker => DeckCardGroup.planeswalker,
    AlbumTypeFilter.land => DeckCardGroup.land,
    AlbumTypeFilter.other => DeckCardGroup.other,
  };
}

List<AlbumListCard> browseAlbumCards(
  List<AlbumListCard> cards, {
  required String query,
  required AlbumTypeFilter type,
}) {
  final q = query.trim().toLowerCase();
  final group = albumTypeGroup(type);
  return [
    for (final card in cards)
      if ((group == null || card.group == group) &&
          (q.isEmpty || card.name.toLowerCase().contains(q)))
        card,
  ];
}

/// Search, type filter, and sort shared by deck and collection albums.
class AlbumCardBrowser extends StatefulWidget {
  const AlbumCardBrowser({
    super.key,
    required this.cards,
    required this.listing,
    required this.onListing,
    this.sideboard = const [],
    this.sideboardMax,
    this.showEmptySideboard = false,
    this.sideboardKey,
    this.totalCount,
    this.aboveSections,
    this.onCount,
    this.onSideCount,
    this.onMoveToSideboard,
    this.onMoveToMain,
    this.onCardTap,
    this.onCardLongPress,
    this.faceCards = const [],
    this.faceTitle,
  });

  final List<AlbumListCard> cards;
  final List<AlbumListCard> sideboard;

  /// When set, the sideboard heading shows `count/max`.
  final int? sideboardMax;

  /// Shows the sideboard heading even when that pile is empty.
  final bool showEmptySideboard;
  final Key? sideboardKey;
  final AlbumListing listing;
  final ValueChanged<AlbumListing> onListing;
  final int? totalCount;

  /// Sits on the first card group, such as Creatures.
  final Widget? aboveSections;
  final AlbumCountChange? onCount;
  final AlbumCountChange? onSideCount;
  final void Function(AlbumListCard card)? onMoveToSideboard;
  final void Function(AlbumListCard card)? onMoveToMain;
  final void Function(AlbumListCard card)? onCardTap;
  final void Function(AlbumListCard card)? onCardLongPress;

  /// Pinned commander or cover, shown above Types / Grid / A–Z groups.
  final List<AlbumListCard> faceCards;
  final String? faceTitle;

  @override
  State<AlbumCardBrowser> createState() => _AlbumCardBrowserState();
}

class _AlbumCardBrowserState extends State<AlbumCardBrowser> {
  final _search = TextEditingController();
  var _query = '';
  var _type = AlbumTypeFilter.all;
  var _sort = AlbumSort.nameAsc;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickType() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDeckPickerChoiceSheet<AlbumTypeFilter>(
      context,
      title: l10n.albumFilter,
      selected: _type,
      choices: [
        for (final filter in AlbumTypeFilter.values)
          DeckPickerChoice(
            value: filter,
            title: _filterLabel(l10n, filter),
            key: ValueKey('album-type-${filter.name}'),
          ),
      ],
    );
    if (!mounted || picked == null) return;
    setState(() => _type = picked);
  }

  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDeckPickerChoiceSheet<AlbumSort>(
      context,
      title: l10n.albumSortBy,
      selected: _sort,
      choices: [
        for (final sort in AlbumSort.values)
          DeckPickerChoice(
            value: sort,
            title: _sortLabel(l10n, sort),
            key: ValueKey('album-sort-${sort.name}'),
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
    final cards = browseAlbumCards(widget.cards, query: _query, type: _type);
    final sideboard = browseAlbumCards(
      widget.sideboard,
      query: _query,
      type: _type,
    );
    final typeLabel =
        _type == AlbumTypeFilter.all
            ? l10n.albumFilter
            : _groupLabel(l10n, albumTypeGroup(_type)!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: l10n.albumSearchHint,
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
                key: const ValueKey('album-type-filter'),
                icon: Icons.filter_list_rounded,
                label: typeLabel,
                onTap: _pickType,
              ),
            ),
            SizedBox(width: LayoutTokens.gr2),
            Expanded(
              child: AlbumBrowseChip(
                key: const ValueKey('album-sort'),
                icon: Icons.swap_vert_rounded,
                label: '${l10n.albumSortBy}: ${_sortLabel(l10n, _sort)}',
                onTap: _pickSort,
              ),
            ),
          ],
        ),
        SizedBox(height: LayoutTokens.gr3),
        Row(
          children: [
            Expanded(
              child: AlbumListingSwitch(
                listing: widget.listing,
                onChanged: widget.onListing,
              ),
            ),
            if (widget.totalCount != null) ...[
              SizedBox(width: LayoutTokens.gr2),
              Text(
                '${widget.totalCount}',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: FontTokens.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        ...albumListingChildren(
          context: context,
          listing: widget.listing,
          cards: cards,
          sideboard: sideboard,
          sideboardMax: widget.sideboardMax,
          showEmptySideboard:
              widget.showEmptySideboard && widget.sideboard.isEmpty,
          sideboardKey: widget.sideboardKey,
          aboveSections: widget.aboveSections,
          sort: _sort,
          onCount: widget.onCount,
          onSideCount: widget.onSideCount,
          onMoveToSideboard: widget.onMoveToSideboard,
          onMoveToMain: widget.onMoveToMain,
          onCardTap: widget.onCardTap,
          onCardLongPress: widget.onCardLongPress,
          faceCards: widget.faceCards,
          faceTitle: widget.faceTitle,
        ),
        if (cards.isEmpty &&
            sideboard.isEmpty &&
            (widget.faceCards.isEmpty || _query.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: LayoutTokens.gr5),
            child: Text(
              l10n.albumNoMatches,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// Shared filter-chip face for album / library browse menus.
class AlbumBrowseChip extends StatelessWidget {
  const AlbumBrowseChip({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final radius = BorderRadius.circular(RadiusTokens.lg);
    final face = _AlbumBrowseChipFace(icon: icon, label: label, colors: colors);
    return Material(
      color: colors.surface,
      borderRadius: radius,
      child:
          onTap == null
              ? face
              : InkWell(onTap: onTap, borderRadius: radius, child: face),
    );
  }
}

class _AlbumBrowseChipFace extends StatelessWidget {
  const _AlbumBrowseChipFace({
    required this.icon,
    required this.label,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final AppColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LayoutTokens.gr2,
        vertical: 10,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.primaryAccent),
          SizedBox(width: LayoutTokens.gr1),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: FontTokens.sm,
              ),
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: colors.textSecondary,
          ),
        ],
      ),
    );
  }
}

String _filterLabel(AppLocalizations l10n, AlbumTypeFilter filter) {
  if (filter == AlbumTypeFilter.all) return l10n.albumFilterAll;
  return _groupLabel(l10n, albumTypeGroup(filter)!);
}

String _sortLabel(AppLocalizations l10n, AlbumSort sort) {
  return switch (sort) {
    AlbumSort.nameAsc => l10n.albumSortName,
    AlbumSort.nameDesc => l10n.albumSortNameDesc,
    AlbumSort.count => l10n.albumSortCount,
    AlbumSort.type => l10n.albumSortType,
  };
}

typedef AlbumCountChange = void Function(AlbumListCard card, int delta);

List<Widget> albumListingChildren({
  required BuildContext context,
  required AlbumListing listing,
  required List<AlbumListCard> cards,
  List<AlbumListCard> sideboard = const [],
  int? sideboardMax,
  bool showEmptySideboard = false,
  Key? sideboardKey,
  Widget? aboveSections,
  AlbumSort sort = AlbumSort.nameAsc,
  AlbumCountChange? onCount,
  AlbumCountChange? onSideCount,
  void Function(AlbumListCard card)? onMoveToSideboard,
  void Function(AlbumListCard card)? onMoveToMain,
  void Function(AlbumListCard card)? onCardTap,
  void Function(AlbumListCard card)? onCardLongPress,
  List<AlbumListCard> faceCards = const [],
  String? faceTitle,
}) {
  final l10n = AppLocalizations.of(context);
  final width = MediaQuery.sizeOf(context).width;
  final sections = _sections(cards, sort);
  final title = faceTitle;
  final hasFace = faceCards.isNotEmpty && title != null && title.isNotEmpty;
  return [
    if (aboveSections != null) aboveSections,
    if (hasFace) ...[
      SizedBox(
        height: aboveSections != null ? LayoutTokens.gr1 : LayoutTokens.gr4,
      ),
      _SectionLabel(
        title: title,
        count: faceCards.fold<int>(
          0,
          (sum, card) => sum + (card.isBlank ? 0 : card.count),
        ),
      ),
      ..._cardsInListing(
        listing: listing,
        cards: faceCards,
        width: width,
        sort: sort,
        onCount: onCount,
        onCardTap: onCardTap,
        onCardLongPress: onCardLongPress,
      ),
    ],
    if (listing == AlbumListing.alpha)
      ..._alphaBlock(
        cards,
        sort,
        onCount,
        onMove: onMoveToSideboard,
        moveTooltip: l10n.deckAlbumMoveToSideboard,
        onCardTap: onCardTap,
        onCardLongPress: onCardLongPress,
      )
    else
      for (var i = 0; i < sections.length; i++) ...[
        SizedBox(
          height:
              i == 0 && (aboveSections != null || hasFace)
                  ? LayoutTokens.gr1
                  : LayoutTokens.gr4,
        ),
        _SectionLabel(
          title: _groupLabel(l10n, sections[i].group),
          count: sections[i].total,
        ),
        ..._cardsInListing(
          listing: listing,
          cards: sections[i].cards,
          width: width,
          sort: sort,
          onCount: onCount,
          onMove: onMoveToSideboard,
          moveTooltip: l10n.deckAlbumMoveToSideboard,
          onCardTap: onCardTap,
          onCardLongPress: onCardLongPress,
        ),
      ],
    if (sideboard.isNotEmpty || showEmptySideboard)
      KeyedSubtree(
        key: sideboardKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: LayoutTokens.gr5),
            _SectionLabel(
              title: l10n.deckAlbumSideboard,
              count: sideboard.fold<int>(0, (sum, card) => sum + card.count),
              maxCount: sideboardMax,
            ),
            if (sideboard.isEmpty)
              Text(
                l10n.deckAlbumSideboardEmpty,
                style: TextStyle(
                  color: AppColorTokens.of(context).textMuted,
                  fontSize: FontTokens.body,
                ),
              )
            else if (listing == AlbumListing.grid)
              _CardGrid(
                cards: _sorted(sideboard, sort),
                columns: _gridColumns(width),
                onCount: onSideCount,
                onMove: onMoveToMain,
                moveLabel: l10n.deckAlbumMoveToMain,
                onCardTap: onCardTap,
                onCardLongPress: onCardLongPress,
              )
            else if (listing == AlbumListing.alpha)
              for (final card in _sorted(sideboard, sort))
                _NameLine(
                  card: card,
                  onCount: onSideCount,
                  onMove: onMoveToMain,
                  moveTooltip: l10n.deckAlbumMoveToMain,
                  onCardTap: onCardTap,
                  onCardLongPress: onCardLongPress,
                )
            else
              for (final card in _sorted(sideboard, sort))
                _AlbumCardRow(
                  card: card,
                  onCount: onSideCount,
                  onMove: onMoveToMain,
                  moveTooltip: l10n.deckAlbumMoveToMain,
                  onCardTap: onCardTap,
                  onCardLongPress: onCardLongPress,
                ),
          ],
        ),
      ),
  ];
}

List<Widget> _cardsInListing({
  required AlbumListing listing,
  required List<AlbumListCard> cards,
  required double width,
  required AlbumSort sort,
  AlbumCountChange? onCount,
  void Function(AlbumListCard card)? onMove,
  String? moveTooltip,
  void Function(AlbumListCard card)? onCardTap,
  void Function(AlbumListCard card)? onCardLongPress,
}) {
  if (listing == AlbumListing.grid) {
    return [
      _CardGrid(
        cards: cards,
        columns: _gridColumns(width),
        onCount: onCount,
        onMove: onMove,
        moveLabel: moveTooltip,
        onCardTap: onCardTap,
        onCardLongPress: onCardLongPress,
      ),
    ];
  }
  if (listing == AlbumListing.alpha) {
    return _alphaBlock(
      cards,
      sort,
      onCount,
      onMove: onMove,
      moveTooltip: moveTooltip,
      onCardTap: onCardTap,
      onCardLongPress: onCardLongPress,
    );
  }
  return [
    for (final card in cards)
      _AlbumCardRow(
        card: card,
        onCount: onCount,
        onMove: onMove,
        moveTooltip: moveTooltip,
        onCardTap: onCardTap,
        onCardLongPress: onCardLongPress,
      ),
  ];
}

int _gridColumns(double width) {
  if (width >= 900) return 4;
  if (width >= 700) return 3;
  return 2;
}

List<Widget> _alphaBlock(
  List<AlbumListCard> cards,
  AlbumSort sort,
  AlbumCountChange? onCount, {
  void Function(AlbumListCard card)? onMove,
  String? moveTooltip,
  void Function(AlbumListCard card)? onCardTap,
  void Function(AlbumListCard card)? onCardLongPress,
}) {
  final sorted = _sorted(cards, sort);
  return [
    for (final card in sorted)
      _NameLine(
        card: card,
        onCount: onCount,
        onMove: onMove,
        moveTooltip: moveTooltip,
        onCardTap: onCardTap,
        onCardLongPress: onCardLongPress,
      ),
  ];
}

void _showAlbumCard(
  BuildContext context,
  AlbumListCard card, {
  String? actionLabel,
  void Function(AlbumListCard card)? onMove,
}) {
  showAlbumCardViewer(
    context,
    name: card.name,
    imageUrl: card.imageUrl,
    backImageUrl: card.backImageUrl,
    actionLabel: onMove == null ? null : actionLabel,
    onAction: onMove == null ? null : () => onMove(card),
  );
}

VoidCallback _albumCardTap(
  BuildContext context,
  AlbumListCard card, {
  void Function(AlbumListCard card)? onCardTap,
  String? moveLabel,
  void Function(AlbumListCard card)? onMove,
  AlbumCountChange? onCount,
}) {
  if (card.isBlank) {
    if (onCardTap != null) return () => onCardTap(card);
    if (onCount != null) return () => onCount(card, 1);
    return () {};
  }
  if (onCardTap != null) return () => onCardTap(card);
  return () =>
      _showAlbumCard(context, card, actionLabel: moveLabel, onMove: onMove);
}

GestureLongPressCallback? _albumCardLongPress(
  BuildContext context,
  AlbumListCard card, {
  void Function(AlbumListCard card)? onCardTap,
  void Function(AlbumListCard card)? onCardLongPress,
  String? moveLabel,
  void Function(AlbumListCard card)? onMove,
}) {
  if (card.isBlank) return null;
  if (onCardLongPress != null) return () => onCardLongPress(card);
  if (onCardTap != null) {
    return () =>
        _showAlbumCard(context, card, actionLabel: moveLabel, onMove: onMove);
  }
  return null;
}

int _compareCards(AlbumListCard a, AlbumListCard b, AlbumSort sort) {
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return switch (sort) {
    AlbumSort.nameAsc => byName,
    AlbumSort.nameDesc => -byName,
    AlbumSort.count => b.count == a.count ? byName : b.count.compareTo(a.count),
    AlbumSort.type =>
      a.group.index == b.group.index
          ? byName
          : a.group.index.compareTo(b.group.index),
  };
}

List<AlbumListCard> _sorted(List<AlbumListCard> cards, AlbumSort sort) {
  final copy = [...cards];
  copy.sort((a, b) => _compareCards(a, b, sort));
  return copy;
}

class _AlbumSection {
  const _AlbumSection({required this.group, required this.cards});

  final DeckCardGroup group;
  final List<AlbumListCard> cards;

  int get total => cards.fold<int>(
    0,
    (sum, card) => sum + (card.count < 1 ? 1 : card.count),
  );
}

List<_AlbumSection> _sections(List<AlbumListCard> cards, AlbumSort sort) {
  final grouped = <DeckCardGroup, List<AlbumListCard>>{};
  for (final card in cards) {
    grouped.putIfAbsent(card.group, () => []).add(card);
  }
  final within = sort == AlbumSort.type ? AlbumSort.nameAsc : sort;
  for (final list in grouped.values) {
    list.sort((a, b) => _compareCards(a, b, within));
  }
  return [
    for (final group in DeckCardGroup.values)
      if (grouped[group] != null)
        _AlbumSection(group: group, cards: grouped[group]!),
  ];
}

String _groupLabel(AppLocalizations l10n, DeckCardGroup group) {
  return switch (group) {
    DeckCardGroup.creature => l10n.deckAlbumCreatures,
    DeckCardGroup.instant => l10n.deckAlbumInstants,
    DeckCardGroup.sorcery => l10n.deckAlbumSorceries,
    DeckCardGroup.artifact => l10n.deckAlbumArtifacts,
    DeckCardGroup.enchantment => l10n.deckAlbumEnchantments,
    DeckCardGroup.planeswalker => l10n.deckAlbumPlaneswalkers,
    DeckCardGroup.land => l10n.deckAlbumLands,
    DeckCardGroup.other => l10n.deckAlbumOther,
  };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.title,
    required this.count,
    this.maxCount,
  });

  final String title;
  final int count;
  final int? maxCount;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final capped = maxCount != null && maxCount! > 0;
    final over = maxCount != null && count > maxCount!;
    final value = capped ? '$count/$maxCount' : '$count';
    return Padding(
      padding: const EdgeInsets.only(bottom: LayoutTokens.gr1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: FontTokens.title,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: over ? colors.error : colors.textSecondary,
              fontSize: FontTokens.body,
              fontWeight: over ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumCardRow extends StatelessWidget {
  const _AlbumCardRow({
    required this.card,
    this.onCount,
    this.onMove,
    this.moveTooltip,
    this.onCardTap,
    this.onCardLongPress,
  });

  final AlbumListCard card;
  final AlbumCountChange? onCount;
  final void Function(AlbumListCard card)? onMove;
  final String? moveTooltip;
  final void Function(AlbumListCard card)? onCardTap;
  final void Function(AlbumListCard card)? onCardLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final art = card.imageUrl;
    return Semantics(
      button: true,
      label: '${card.count} ${card.name}',
      child: GestureDetector(
        key: ValueKey('album-card-${card.listingKey}'),
        behavior: HitTestBehavior.opaque,
        onTap: _albumCardTap(
          context,
          card,
          onCardTap: onCardTap,
          moveLabel: moveTooltip,
          onMove: onMove,
          onCount: onCount,
        ),
        onLongPress: _albumCardLongPress(
          context,
          card,
          onCardTap: onCardTap,
          onCardLongPress: onCardLongPress,
          moveLabel: moveTooltip,
          onMove: onMove,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: LayoutTokens.gr1),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(RadiusTokens.xs),
                child: SizedBox(
                  width: 36,
                  height: 50,
                  child: _ArtImage(url: art, colors: colors),
                ),
              ),
              SizedBox(width: LayoutTokens.gr2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: FontTokens.body,
                      ),
                    ),
                    if (card.manaCost != null && card.manaCost!.isNotEmpty)
                      ManaCostPips(manaCost: card.manaCost, symbolHeight: 14),
                  ],
                ),
              ),
              if (card.inclusion != null) ...[
                SizedBox(width: LayoutTokens.gr2),
                Text(
                  '${(card.inclusion! * 100).round()}%',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: FontTokens.caption,
                  ),
                ),
              ],
              if (card.warning != null) ...[
                SizedBox(width: LayoutTokens.gr1),
                _CardWarning(message: card.warning!),
              ],
              if (onMove != null && !card.isBlank) ...[
                SizedBox(width: LayoutTokens.gr1),
                _MoveButton(
                  tooltip: moveTooltip ?? '',
                  onPressed: () => onMove!(card),
                ),
              ],
              if (!card.isBlank) ...[
                SizedBox(width: LayoutTokens.gr2),
                _CountStepper(
                  count: card.count,
                  canIncrease: card.canAddCopy,
                  onDelta:
                      onCount == null ? null : (delta) => onCount!(card, delta),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NameLine extends StatelessWidget {
  const _NameLine({
    required this.card,
    this.onCount,
    this.onMove,
    this.moveTooltip,
    this.onCardTap,
    this.onCardLongPress,
  });

  final AlbumListCard card;
  final AlbumCountChange? onCount;
  final void Function(AlbumListCard card)? onMove;
  final String? moveTooltip;
  final void Function(AlbumListCard card)? onCardTap;
  final void Function(AlbumListCard card)? onCardLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Semantics(
      button: true,
      label: '${card.count} ${card.name}',
      child: GestureDetector(
        key: ValueKey('album-card-${card.listingKey}'),
        behavior: HitTestBehavior.opaque,
        onTap: _albumCardTap(
          context,
          card,
          onCardTap: onCardTap,
          moveLabel: moveTooltip,
          onMove: onMove,
          onCount: onCount,
        ),
        onLongPress: _albumCardLongPress(
          context,
          card,
          onCardTap: onCardTap,
          onCardLongPress: onCardLongPress,
          moveLabel: moveTooltip,
          onMove: onMove,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: LayoutTokens.gr1),
          child: Row(
            children: [
              if (onCount == null)
                SizedBox(
                  width: 28,
                  child: Text(
                    '${card.count}',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: FontTokens.body,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: FontTokens.body,
                  ),
                ),
              ),
              if (card.inclusion != null) ...[
                SizedBox(width: LayoutTokens.gr2),
                Text(
                  '${(card.inclusion! * 100).round()}%',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: FontTokens.caption,
                  ),
                ),
              ],
              if (card.warning != null) ...[
                SizedBox(width: LayoutTokens.gr1),
                _CardWarning(message: card.warning!),
              ],
              if (onMove != null && !card.isBlank) ...[
                SizedBox(width: LayoutTokens.gr1),
                _MoveButton(
                  tooltip: moveTooltip ?? '',
                  onPressed: () => onMove!(card),
                ),
              ],
              if (onCount != null && !card.isBlank) ...[
                SizedBox(width: LayoutTokens.gr2),
                _CountStepper(
                  count: card.count,
                  onDelta: (delta) => onCount!(card, delta),
                  canIncrease: card.canAddCopy,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({
    required this.cards,
    required this.columns,
    this.onCount,
    this.onMove,
    this.moveLabel,
    this.onCardTap,
    this.onCardLongPress,
  });

  final List<AlbumListCard> cards;
  final int columns;
  final AlbumCountChange? onCount;
  final void Function(AlbumListCard card)? onMove;
  final String? moveLabel;
  final void Function(AlbumListCard card)? onCardTap;
  final void Function(AlbumListCard card)? onCardLongPress;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: LayoutTokens.gr1,
        crossAxisSpacing: LayoutTokens.gr1,
        childAspectRatio: 63 / 88,
      ),
      itemBuilder:
          (context, index) => _GridTile(
            card: cards[index],
            onCount: onCount,
            onMove: onMove,
            moveLabel: moveLabel,
            onCardTap: onCardTap,
            onCardLongPress: onCardLongPress,
          ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.card,
    this.onCount,
    this.onMove,
    this.moveLabel,
    this.onCardTap,
    this.onCardLongPress,
  });

  final AlbumListCard card;
  final AlbumCountChange? onCount;
  final void Function(AlbumListCard card)? onMove;
  final String? moveLabel;
  final void Function(AlbumListCard card)? onCardTap;
  final void Function(AlbumListCard card)? onCardLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Semantics(
      button: true,
      label: '${card.count} ${card.name}',
      child: GestureDetector(
        key: ValueKey('album-card-${card.listingKey}'),
        behavior: HitTestBehavior.opaque,
        onTap: _albumCardTap(
          context,
          card,
          onCardTap: onCardTap,
          moveLabel: moveLabel,
          onMove: onMove,
          onCount: onCount,
        ),
        onLongPress: _albumCardLongPress(
          context,
          card,
          onCardTap: onCardTap,
          onCardLongPress: onCardLongPress,
          moveLabel: moveLabel,
          onMove: onMove,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(RadiusTokens.md),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (card.isBlank)
                ColoredBox(
                  color: colors.surfaceElevated,
                  child: Icon(
                    Icons.add_rounded,
                    color: colors.textMuted,
                    size: 36,
                  ),
                )
              else
                _ArtImage(url: card.imageUrl, colors: colors),
              if (card.warning != null)
                Positioned(
                  top: 4,
                  left: 4,
                  child: _CardWarning(message: card.warning!),
                ),
              if (onCount != null && !card.isBlank)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Center(
                    child: _CountStepper(
                      count: card.count,
                      dense: true,
                      onDelta: (delta) => onCount!(card, delta),
                      canIncrease: card.canAddCopy,
                    ),
                  ),
                )
              else if (!card.isBlank && card.count > 1)
                Positioned(
                  top: 4,
                  right: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(RadiusTokens.xs),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        '${card.count}',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: FontTokens.caption,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardWarning extends StatelessWidget {
  const _CardWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      child: Icon(
        Icons.error_rounded,
        color: AppColorTokens.of(context).error,
        size: 18,
      ),
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
      color: AppColorTokens.of(context).textSecondary,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    );
  }
}

class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.count,
    required this.onDelta,
    this.dense = false,
    this.canIncrease = true,
  });

  final int count;
  final ValueChanged<int>? onDelta;
  final bool dense;
  final bool canIncrease;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    if (onDelta == null) {
      return Text(
        '$count',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: FontTokens.title,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final l10n = AppLocalizations.of(context);
    final size = dense ? 28.0 : 32.0;
    final iconSize = dense ? 16.0 : 18.0;
    final foreground = dense ? const Color(0xFF1A1A1A) : colors.textPrimary;
    Widget button(IconData icon, String tooltip, VoidCallback? onPressed) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        color: foreground,
        disabledColor: foreground.withValues(alpha: 0.35),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: BoxConstraints.tightFor(width: size, height: size),
      );
    }

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          Icons.remove_rounded,
          l10n.albumCountRemove,
          count <= 0 ? null : () => onDelta!(-1),
        ),
        SizedBox(
          width: dense ? 18 : 22,
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: dense ? FontTokens.caption : FontTokens.title,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        button(
          Icons.add_rounded,
          l10n.albumCountAdd,
          !canIncrease || count >= 99 ? null : () => onDelta!(1),
        ),
      ],
    );
    return GestureDetector(
      onTap: () {},
      child:
          dense
              ? DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(RadiusTokens.pill),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: controls,
              )
              : controls,
    );
  }
}

class _ArtImage extends StatelessWidget {
  const _ArtImage({required this.url, required this.colors});

  final String? url;
  final AppColorTokens colors;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return ColoredBox(color: colors.surfaceElevated);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cacheWidth =
            width.isFinite && width > 0
                ? (width * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(72, 640)
                : null;
        return CachedNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          memCacheWidth: cacheWidth,
          placeholder: (_, __) => ColoredBox(color: colors.surfaceElevated),
          errorWidget:
              (_, __, ___) => ColoredBox(color: colors.surfaceElevated),
        );
      },
    );
  }
}

/// Frosted strip so a list can scroll behind a bottom action.
class BlurredBottomAction extends StatelessWidget {
  const BlurredBottomAction({
    super.key,
    required this.child,
    this.aboveShellDock = false,
  });

  final Widget child;

  /// When true, lift the button above [MainShell]'s floating nav.
  final bool aboveShellDock;

  static const double buttonHeight = 52;

  static double _bottomPad(BuildContext context, bool aboveShellDock) {
    if (aboveShellDock) {
      return LayoutTokens.shellDockInset(context) + LayoutTokens.gr2;
    }
    return MediaQuery.viewPaddingOf(context).bottom + LayoutTokens.gr2;
  }

  static double height(BuildContext context, {bool aboveShellDock = false}) {
    return LayoutTokens.gr2 +
        buttonHeight +
        _bottomPad(context, aboveShellDock);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.backgroundPrimary.withValues(alpha: 0.04),
                colors.backgroundPrimary.withValues(alpha: 0.5),
                colors.backgroundPrimary.withValues(alpha: 0.78),
              ],
              stops: const [0.0, 0.28, 1],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              LayoutTokens.gr4,
              LayoutTokens.gr2,
              LayoutTokens.gr4,
              _bottomPad(context, aboveShellDock),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
