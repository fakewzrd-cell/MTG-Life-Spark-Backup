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
    this.manaCost,
    this.inclusion,
    this.canAddCopy = true,
    this.warning,
  });

  final String name;
  final int count;
  final DeckCardGroup group;
  final String? imageUrl;
  final String? manaCost;
  final double? inclusion;
  final bool canAddCopy;

  /// Why this card needs attention, shown beside the row.
  final String? warning;
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
    return Wrap(
      spacing: LayoutTokens.gr1,
      children: [
        for (final mode in AlbumListing.values)
          ChoiceChip(
            label: Text(_listingLabel(l10n, mode)),
            selected: listing == mode,
            onSelected: (_) => onChanged(mode),
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
              child: AlbumBrowseMenu<AlbumTypeFilter>(
                icon: Icons.filter_list_rounded,
                label: typeLabel,
                value: _type,
                onSelected: (value) => setState(() => _type = value),
                items: [
                  for (final filter in AlbumTypeFilter.values)
                    PopupMenuItem(
                      value: filter,
                      child: Text(_filterLabel(l10n, filter)),
                    ),
                ],
              ),
            ),
            SizedBox(width: LayoutTokens.gr2),
            Expanded(
              child: AlbumBrowseMenu<AlbumSort>(
                icon: Icons.swap_vert_rounded,
                label: '${l10n.albumSortBy}: ${_sortLabel(l10n, _sort)}',
                value: _sort,
                onSelected: (value) => setState(() => _sort = value),
                items: [
                  for (final sort in AlbumSort.values)
                    PopupMenuItem(
                      value: sort,
                      child: Text(_sortLabel(l10n, sort)),
                    ),
                ],
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
        if (cards.isEmpty && sideboard.isEmpty) ...[
          if (widget.aboveSections != null) widget.aboveSections!,
          Padding(
            padding: const EdgeInsets.only(top: LayoutTokens.gr5),
            child: Text(
              l10n.albumNoMatches,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
        ] else
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
          ),
      ],
    );
  }
}

class AlbumBrowseMenu<T> extends StatelessWidget {
  const AlbumBrowseMenu({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onSelected,
    required this.items,
  });

  final IconData icon;
  final String label;
  final T value;
  final ValueChanged<T> onSelected;
  final List<PopupMenuEntry<T>> items;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final radius = BorderRadius.circular(RadiusTokens.lg);
    return Material(
      color: colors.surface,
      borderRadius: radius,
      child: PopupMenuButton<T>(
        initialValue: value,
        onSelected: onSelected,
        itemBuilder: (_) => items,
        child: Padding(
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
        ),
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
}) {
  final l10n = AppLocalizations.of(context);
  final width = MediaQuery.sizeOf(context).width;
  final sections = _sections(cards, sort);
  return [
    if (aboveSections != null) aboveSections,
    if (listing == AlbumListing.alpha)
      ..._alphaBlock(
        cards,
        sort,
        onCount,
        onMove: onMoveToSideboard,
        moveTooltip: l10n.deckAlbumMoveToSideboard,
      )
    else
      for (var i = 0; i < sections.length; i++) ...[
        SizedBox(
          height:
              i == 0 && aboveSections != null
                  ? LayoutTokens.gr1
                  : LayoutTokens.gr4,
        ),
        _SectionLabel(
          title: _groupLabel(l10n, sections[i].group),
          count: sections[i].total,
        ),
        if (listing == AlbumListing.grid)
          _CardGrid(
            cards: sections[i].cards,
            columns: _gridColumns(width),
            onCount: onCount,
            onMove: onMoveToSideboard,
            moveLabel: l10n.deckAlbumMoveToSideboard,
          )
        else
          for (final card in sections[i].cards)
            _AlbumCardRow(
              card: card,
              onCount: onCount,
              onMove: onMoveToSideboard,
              moveTooltip: l10n.deckAlbumMoveToSideboard,
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
              )
            else if (listing == AlbumListing.alpha)
              for (final card in _sorted(sideboard, sort))
                _NameLine(
                  card: card,
                  onCount: onSideCount,
                  onMove: onMoveToMain,
                  moveTooltip: l10n.deckAlbumMoveToMain,
                )
            else
              for (final card in _sorted(sideboard, sort))
                _AlbumCardRow(
                  card: card,
                  onCount: onSideCount,
                  onMove: onMoveToMain,
                  moveTooltip: l10n.deckAlbumMoveToMain,
                ),
          ],
        ),
      ),
  ];
}

int _gridColumns(double width) {
  if (width >= 900) return 6;
  if (width >= 700) return 5;
  if (width >= 520) return 4;
  return 3;
}

List<Widget> _alphaBlock(
  List<AlbumListCard> cards,
  AlbumSort sort,
  AlbumCountChange? onCount, {
  void Function(AlbumListCard card)? onMove,
  String? moveTooltip,
}) {
  final sorted = _sorted(cards, sort);
  return [
    for (final card in sorted)
      _NameLine(
        card: card,
        onCount: onCount,
        onMove: onMove,
        moveTooltip: moveTooltip,
      ),
  ];
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

  int get total => cards.fold<int>(0, (sum, card) => sum + card.count);
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
  });

  final AlbumListCard card;
  final AlbumCountChange? onCount;
  final void Function(AlbumListCard card)? onMove;
  final String? moveTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final art = card.imageUrl;
    return Semantics(
      button: true,
      label: '${card.count} ${card.name}',
      child: GestureDetector(
        onTap:
            () => showAlbumCardViewer(
              context,
              name: card.name,
              imageUrl: card.imageUrl,
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
              if (onMove != null) ...[
                SizedBox(width: LayoutTokens.gr1),
                _MoveButton(
                  tooltip: moveTooltip ?? '',
                  onPressed: () => onMove!(card),
                ),
              ],
              SizedBox(width: LayoutTokens.gr2),
              _CountStepper(
                count: card.count,
                canIncrease: card.canAddCopy,
                onDelta:
                    onCount == null ? null : (delta) => onCount!(card, delta),
              ),
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
  });

  final AlbumListCard card;
  final AlbumCountChange? onCount;
  final void Function(AlbumListCard card)? onMove;
  final String? moveTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Semantics(
      button: true,
      label: '${card.count} ${card.name}',
      child: GestureDetector(
        onTap:
            () => showAlbumCardViewer(
              context,
              name: card.name,
              imageUrl: card.imageUrl,
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
              if (onMove != null) ...[
                SizedBox(width: LayoutTokens.gr1),
                _MoveButton(
                  tooltip: moveTooltip ?? '',
                  onPressed: () => onMove!(card),
                ),
              ],
              if (onCount != null) ...[
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
  });

  final List<AlbumListCard> cards;
  final int columns;
  final AlbumCountChange? onCount;
  final void Function(AlbumListCard card)? onMove;
  final String? moveLabel;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
  });

  final AlbumListCard card;
  final AlbumCountChange? onCount;
  final void Function(AlbumListCard card)? onMove;
  final String? moveLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Semantics(
      button: true,
      label: '${card.count} ${card.name}',
      child: GestureDetector(
        onTap:
            () => showAlbumCardViewer(
              context,
              name: card.name,
              imageUrl: card.imageUrl,
              actionLabel: onMove == null ? null : moveLabel,
              onAction: onMove == null ? null : () => onMove!(card),
            ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(RadiusTokens.md),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ArtImage(url: card.imageUrl, colors: colors),
              if (card.warning != null)
                Positioned(
                  top: 4,
                  left: 4,
                  child: _CardWarning(message: card.warning!),
                ),
              if (onCount != null)
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
              else if (card.count > 1)
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
        button(Icons.remove_rounded, l10n.albumCountRemove, () => onDelta!(-1)),
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
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      placeholder: (_, __) => ColoredBox(color: colors.surfaceElevated),
      errorWidget: (_, __, ___) => ColoredBox(color: colors.surfaceElevated),
    );
  }
}

/// Frosted strip so a list can scroll behind a bottom action.
class BlurredBottomAction extends StatelessWidget {
  const BlurredBottomAction({super.key, required this.child});

  final Widget child;

  static const double buttonHeight = 52;

  static double height(BuildContext context) {
    return LayoutTokens.gr2 +
        buttonHeight +
        MediaQuery.paddingOf(context).bottom +
        LayoutTokens.gr2;
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
              MediaQuery.paddingOf(context).bottom + LayoutTokens.gr2,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
