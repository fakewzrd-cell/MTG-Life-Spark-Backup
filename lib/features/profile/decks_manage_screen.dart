import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import '../../core/deck/deck_limits.dart';
import '../../core/game/game_format.dart';
import '../../core/models/player_deck.dart';
import '../../core/persistence/deck_list_repository.dart';
import '../../core/persistence/providers.dart';
import '../../shared/widgets/mana_cost_pips.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/app_router.dart';
import '../../shared/utils/deck_style_l10n.dart';
import '../../ui/components/ui_app_bar.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../../ui/tokens/typography_tokens.dart';
import 'new_deck_sheet.dart';
import 'collection_album_screen.dart';
import 'library_destination_switch.dart';
import 'profile_carousel_sections.dart';

enum DeckLibraryListing { formats, covers, alpha }

final deckLibraryListingProvider = StateProvider<DeckLibraryListing>(
  (ref) => DeckLibraryListing.formats,
);

class DecksManageScreen extends ConsumerStatefulWidget {
  const DecksManageScreen({super.key});

  @override
  ConsumerState<DecksManageScreen> createState() => _DecksManageScreenState();
}

Map<GameFormat, List<PlayerDeck>> _groupDecksByFormat(List<PlayerDeck> decks) {
  final grouped = <GameFormat, List<PlayerDeck>>{};
  for (final deck in decks) {
    grouped.putIfAbsent(deck.gameFormat, () => []).add(deck);
  }
  for (final list in grouped.values) {
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }
  return grouped;
}

bool _deckMatchesQuery(PlayerDeck deck, String query, AppLocalizations l10n) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  final style = deck.deckStyle;
  final styleHit =
      style != null &&
      (localizedDeckStyleName(l10n, style).toLowerCase().contains(q) ||
          style.displayName.toLowerCase().contains(q) ||
          style.id.contains(q));
  return deck.displayName.toLowerCase().contains(q) ||
      deck.commanderName.toLowerCase().contains(q) ||
      (deck.partnerCommanderName?.toLowerCase().contains(q) ?? false) ||
      styleHit ||
      deck.gameFormat.displayName.toLowerCase().contains(q);
}

class _DecksManageScreenState extends ConsumerState<DecksManageScreen> {
  List<PlayerDeck> _decks = [];
  Map<String, DeckCountLabel> _counts = {};
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final decks = ref.read(deckRepositoryProvider).getAll();
    final counts = <String, DeckCountLabel>{};
    if (Hive.isBoxOpen(DeckListRepository.boxName)) {
      final lists = ref.read(deckListRepositoryProvider);
      for (final deck in decks) {
        if (deck.isCommanderDeck) {
          await lists.foldSideboardIntoMain(deck.id);
        }
        counts[deck.id] = deckCountLabel(deck, lists.entriesFor(deck.id));
      }
    }
    if (!mounted) return;
    setState(() {
      _decks = decks;
      _counts = counts;
    });
  }

  Future<void> _promptNewDeckName() async {
    final result = await showNewDeckSheet(context);
    if (result == null || !mounted) return;
    final profile = ref.read(profileRepositoryProvider).getProfile();
    if (profile == null) return;
    await context.push(
      AppRoutes.commanderSelect,
      extra: {
        'playerId': profile.playerId,
        'newDeckDisplayName': result.name,
        'deckFormat': result.format.name,
        'deckStyleId': result.deckStyleId,
      },
    );
    bumpDeckListRevision(ref);
    _reload();
  }

  Future<void> _onDeckTap(PlayerDeck deck) async {
    await context.push('/decks/${Uri.encodeComponent(deck.id)}');
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(deckListRevisionProvider, (_, __) => _reload());
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final filtered =
        _decks.where((d) => _deckMatchesQuery(d, _query, l10n)).toList();
    final grouped = _groupDecksByFormat(filtered);
    final listing = ref.watch(deckLibraryListingProvider);
    final destination = ref.watch(libraryDestinationProvider);
    final showingDecks = destination == LibraryDestination.decks;

    final isEmpty = _decks.isEmpty;
    final noMatches = !isEmpty && filtered.isEmpty;

    final sectionChildren = <Widget>[];
    for (final format in GameFormatDetails.lobbyPickerOrder) {
      final decks = grouped[format];
      if (decks == null || decks.isEmpty) continue;
      if (sectionChildren.isNotEmpty) {
        sectionChildren.add(SizedBox(height: LayoutTokens.shellSectionGap));
      }
      sectionChildren.add(
        _DecksFormatSection(
          format: format,
          decks: decks,
          counts: _counts,
          colors: colors,
          onDeckTap: _onDeckTap,
        ),
      );
    }

    Widget scrollBody;
    if (isEmpty) {
      scrollBody = Center(
        child: Padding(
          padding: const EdgeInsets.all(LayoutTokens.shellPageInset),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.style_outlined,
                size: 56,
                color: colors.primaryAccent.withValues(alpha: 0.85),
              ),
              SizedBox(height: LayoutTokens.gr4),
              Text(
                l10n.decksEmptyTitle,
                textAlign: TextAlign.center,
                style: TypographyTokens.sectionTitle(colors.textPrimary),
              ),
              SizedBox(height: LayoutTokens.gr2),
              Text(
                l10n.decksEmptyBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontSize: FontTokens.body,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      scrollBody = ListView(
        padding: LayoutTokens.shellScrollPadding(
          context,
          top: LayoutTokens.gr2,
        ),
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: LayoutTokens.gr3),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: l10n.decksSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                hintStyle: TextStyle(color: colors.textSecondary),
                suffixIcon:
                    _query.isEmpty
                        ? null
                        : IconButton(
                          tooltip: l10n.decksClearSearchTooltip,
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
              ),
              style: TextStyle(color: colors.textPrimary),
            ),
          ),
          _DeckListingSwitch(
            listing: listing,
            onChanged: (value) {
              ref.read(deckLibraryListingProvider.notifier).state = value;
            },
          ),
          SizedBox(height: LayoutTokens.gr3),
          if (noMatches)
            Padding(
              padding: EdgeInsets.symmetric(vertical: LayoutTokens.gr5),
              child: Text(
                l10n.decksNoSearchMatches(_query),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            )
          else if (listing == DeckLibraryListing.covers)
            _DeckCoverGrid(
              decks: filtered,
              colors: colors,
              onDeckTap: _onDeckTap,
            )
          else if (listing == DeckLibraryListing.alpha)
            _DeckAlphaList(
              decks: filtered,
              colors: colors,
              onDeckTap: _onDeckTap,
            )
          else
            ...sectionChildren,
        ],
      );
    }

    return Scaffold(
      appBar: UiAppBar(
        title:
            showingDecks
                ? AppLocalizations.of(context).decksTitle
                : AppLocalizations.of(context).collectionTitle,
      ),
      backgroundColor: colors.backgroundPrimary,
      body: Column(
        children: [
          const LibraryDestinationSwitch(),
          Expanded(
            child: showingDecks ? scrollBody : const CollectionAlbumView(),
          ),
          if (showingDecks)
            Padding(
              padding: EdgeInsets.fromLTRB(
                LayoutTokens.gr4,
                LayoutTokens.gr2,
                LayoutTokens.gr4,
                MediaQuery.paddingOf(context).bottom + LayoutTokens.gr2,
              ),
              child: UiButton(
                label: l10n.decksAddDeck,
                icon: const Icon(Icons.add_rounded, size: 22),
                onPressed: _promptNewDeckName,
              ),
            ),
        ],
      ),
    );
  }
}

/// Format section: header + vertical list of compact deck rows.
class _DecksFormatSection extends StatelessWidget {
  const _DecksFormatSection({
    required this.format,
    required this.decks,
    required this.counts,
    required this.colors,
    required this.onDeckTap,
  });

  final GameFormat format;
  final List<PlayerDeck> decks;
  final Map<String, DeckCountLabel> counts;
  final AppColorTokens colors;
  final ValueChanged<PlayerDeck> onDeckTap;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TypographyTokens.sectionTitle(colors.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileSectionHeader(
          title: format.displayName,
          titleStyle: titleStyle,
          colors: colors,
          count: decks.length,
          singularUnit: 'deck',
          pluralUnit: 'decks',
        ),
        SizedBox(height: LayoutTokens.gr2),
        ...[
          for (var i = 0; i < decks.length; i++) ...[
            if (i > 0) SizedBox(height: LayoutTokens.gr2),
            _DeckLibraryTile(
              deck: decks[i],
              count: counts[decks[i].id],
              colors: colors,
              onTap: () => onDeckTap(decks[i]),
            ),
          ],
        ],
      ],
    );
  }
}

/// Compact scannable row for the decks library (not a carousel card).
class _DeckLibraryTile extends StatelessWidget {
  const _DeckLibraryTile({
    required this.deck,
    required this.colors,
    required this.onTap,
    this.count,
  });

  final PlayerDeck deck;
  final AppColorTokens colors;
  final VoidCallback onTap;
  final DeckCountLabel? count;

  @override
  Widget build(BuildContext context) {
    final commanderLine =
        deck.isCommanderDeck && deck.hasPartner
            ? '${deck.commanderName} // ${deck.partnerCommanderName}'
            : deck.commanderName;
    final styleLine =
        deck.hasDeckStyle
            ? localizedDeckStyleName(
              AppLocalizations.of(context),
              deck.deckStyle!,
            )
            : AppLocalizations.of(context).decksStyleNotSet;
    return Semantics(
      button: true,
      label: '${deck.displayName}, ${deck.gameFormat.displayName}',
      child: Material(
        color: colors.surface,
        borderRadius: RadiusTokens.radiusXl,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: RadiusTokens.radiusXl,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final artUrl = deck.commanderImageUrl;
              final hasArt = artUrl != null && artUrl.isNotEmpty;
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
                              Row(
                                children: [
                                  if (deck.isPinned) ...[
                                    Icon(
                                      Icons.push_pin_rounded,
                                      size: 14,
                                      color: colors.primaryAccent,
                                    ),
                                    SizedBox(width: LayoutTokens.gr0),
                                  ],
                                  Expanded(
                                    child: Text(
                                      deck.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: FontTokens.body,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: LayoutTokens.gr0),
                              Text(
                                commanderLine.isEmpty
                                    ? AppLocalizations.of(
                                      context,
                                    ).decksNoCoverCard
                                    : commanderLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: FontTokens.sm,
                                ),
                              ),
                              SizedBox(height: LayoutTokens.gr0),
                              Text(
                                styleLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      deck.hasDeckStyle
                                          ? colors.textSecondary
                                          : colors.warning,
                                  fontSize: FontTokens.sm,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _DeckRowTrail(deck: deck, count: count, colors: colors),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DeckRowTrail extends StatelessWidget {
  const _DeckRowTrail({required this.deck, required this.colors, this.count});

  final PlayerDeck deck;
  final AppColorTokens colors;
  final DeckCountLabel? count;

  @override
  Widget build(BuildContext context) {
    final pips = _deckPips(deck);
    final label = count;
    if (pips == null && label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: LayoutTokens.gr2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (pips != null) ManaCostPips(manaCost: pips, symbolHeight: 14),
          if (label != null) ...[
            if (pips != null) SizedBox(height: LayoutTokens.gr1),
            Text(
              label.main,
              style: TextStyle(
                color: label.illegal ? colors.error : colors.textSecondary,
                fontSize: FontTokens.sm,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String? _deckPips(PlayerDeck deck) {
  const order = ['W', 'U', 'B', 'R', 'G'];
  final colors = [
    for (final letter in order)
      if (deck.commanderColorIdentity.contains(letter)) letter,
  ];
  if (colors.isEmpty) return deck.isCommanderDeck ? '{C}' : null;
  return colors.map((letter) => '{$letter}').join();
}

class _DeckListingSwitch extends StatelessWidget {
  const _DeckListingSwitch({required this.listing, required this.onChanged});

  final DeckLibraryListing listing;
  final ValueChanged<DeckLibraryListing> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: LayoutTokens.gr1,
      children: [
        for (final mode in DeckLibraryListing.values)
          ChoiceChip(
            label: Text(_deckListingLabel(l10n, mode)),
            selected: listing == mode,
            onSelected: (_) => onChanged(mode),
          ),
      ],
    );
  }
}

String _deckListingLabel(AppLocalizations l10n, DeckLibraryListing listing) {
  return switch (listing) {
    DeckLibraryListing.formats => l10n.deckLibraryViewFormats,
    DeckLibraryListing.covers => l10n.deckLibraryViewCovers,
    DeckLibraryListing.alpha => l10n.deckAlbumViewAlpha,
  };
}

String _deckCommanderLine(PlayerDeck deck) {
  if (deck.isCommanderDeck && deck.hasPartner) {
    return '${deck.commanderName} // ${deck.partnerCommanderName}';
  }
  return deck.commanderName;
}

class _DeckCoverGrid extends StatelessWidget {
  const _DeckCoverGrid({
    required this.decks,
    required this.colors,
    required this.onDeckTap,
  });

  final List<PlayerDeck> decks;
  final AppColorTokens colors;
  final ValueChanged<PlayerDeck> onDeckTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: decks.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 248,
        mainAxisSpacing: LayoutTokens.gr2,
        crossAxisSpacing: LayoutTokens.gr2,
      ),
      itemBuilder: (context, index) {
        final deck = decks[index];
        return _DeckCoverTile(
          deck: deck,
          colors: colors,
          onTap: () => onDeckTap(deck),
        );
      },
    );
  }
}

class _DeckCoverTile extends StatelessWidget {
  const _DeckCoverTile({
    required this.deck,
    required this.colors,
    required this.onTap,
  });

  final PlayerDeck deck;
  final AppColorTokens colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final artUrl = deck.commanderImageUrl;
    final hasArt = artUrl != null && artUrl.isNotEmpty;
    final commander = _deckCommanderLine(deck);
    return Semantics(
      button: true,
      label: '${deck.displayName}, ${deck.gameFormat.displayName}',
      child: Material(
        color: colors.surface,
        borderRadius: RadiusTokens.radiusXl,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasArt)
                CachedNetworkImage(
                  imageUrl: artUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorWidget:
                      (_, __, ___) => ColoredBox(color: colors.surfaceElevated),
                )
              else
                ColoredBox(color: colors.surfaceElevated),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.surface.withValues(alpha: 0),
                      colors.surface.withValues(alpha: 0),
                      colors.surface.withValues(alpha: 0.55),
                      colors.surface,
                      colors.surface,
                    ],
                    stops: const [0, 0.46, 0.56, 0.68, 1],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LayoutTokens.gr2,
                    LayoutTokens.gr2,
                    LayoutTokens.gr2,
                    LayoutTokens.gr2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.displayName,
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
                        commander.isEmpty
                            ? AppLocalizations.of(context).decksNoCoverCard
                            : commander,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: FontTokens.sm,
                        ),
                      ),
                    ],
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

class _DeckAlphaList extends StatelessWidget {
  const _DeckAlphaList({
    required this.decks,
    required this.colors,
    required this.onDeckTap,
  });

  final List<PlayerDeck> decks;
  final AppColorTokens colors;
  final ValueChanged<PlayerDeck> onDeckTap;

  @override
  Widget build(BuildContext context) {
    final sorted = [...decks]..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return Column(
      children: [
        for (var i = 0; i < sorted.length; i++) ...[
          if (i > 0) SizedBox(height: LayoutTokens.gr2),
          _DeckAlphaTile(
            deck: sorted[i],
            colors: colors,
            onTap: () => onDeckTap(sorted[i]),
          ),
        ],
      ],
    );
  }
}

class _DeckAlphaTile extends StatelessWidget {
  const _DeckAlphaTile({
    required this.deck,
    required this.colors,
    required this.onTap,
  });

  final PlayerDeck deck;
  final AppColorTokens colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final commander = _deckCommanderLine(deck);
    final subtitle =
        commander.isEmpty
            ? deck.gameFormat.displayName
            : '$commander · ${deck.gameFormat.displayName}';
    return Semantics(
      button: true,
      label: '${deck.displayName}, ${deck.gameFormat.displayName}',
      child: Material(
        color: colors.surface,
        borderRadius: RadiusTokens.radiusLg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LayoutTokens.gr3,
              vertical: LayoutTokens.gr2,
            ),
            child: Row(
              children: [
                if (deck.isPinned) ...[
                  Icon(
                    Icons.push_pin_rounded,
                    size: 14,
                    color: colors.primaryAccent,
                  ),
                  SizedBox(width: LayoutTokens.gr1),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.displayName,
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
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: FontTokens.sm,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_deckPips(deck) != null) ...[
                  SizedBox(width: LayoutTokens.gr2),
                  ManaCostPips(manaCost: _deckPips(deck), symbolHeight: 14),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
