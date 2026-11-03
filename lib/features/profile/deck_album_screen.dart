import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/deck/bracket_floor.dart';
import '../../core/deck/deck_limits.dart';
import '../../core/deck/bracket_names.dart';
import '../../core/deck/deck_list_text.dart';
import '../../core/deck/edhrec_client.dart';
import '../../core/game/game_format.dart';
import '../../core/game/scryfall_service.dart';
import '../../core/models/collection_entry.dart';
import '../../core/models/deck_card_entry.dart';
import '../../core/models/player_deck.dart';
import '../../core/persistence/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/deck_style_l10n.dart';
import '../../shared/widgets/mana_cost_pips.dart';
import '../../ui/components/ui_app_bar.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/components/ui_snack_bar.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../game/widgets/game_modal_chrome.dart';
import 'album_listing.dart';
import 'card_viewer.dart';
import 'collection_add_sheet.dart';
import 'deck_library_actions.dart';
import 'deck_options_sheet.dart';
import 'deck_stats_view.dart';

class DeckAlbumScreen extends ConsumerStatefulWidget {
  const DeckAlbumScreen({super.key, required this.deckId});

  final String deckId;

  @override
  ConsumerState<DeckAlbumScreen> createState() => _DeckAlbumScreenState();
}

class _DeckAlbumScreenState extends ConsumerState<DeckAlbumScreen> {
  PlayerDeck? _deck;
  List<DeckCardEntry> _entries = const [];
  Map<String, ScryfallCard> _cards = const {};
  var _loadingCards = false;
  var _facesReady = false;
  var _missing = false;
  var _showTitle = false;
  var _showStats = false;
  final _sideboardKey = GlobalKey();
  BracketAssessment? _bracket;
  CommanderMeta? _meta;
  List<_DeckSuggestion> _fits = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final deck = ref.read(deckRepositoryProvider).getById(widget.deckId);
    if (!mounted) return;
    if (deck == null) {
      setState(() {
        _deck = null;
        _missing = true;
        _entries = const [];
      });
      return;
    }
    final listRepo = ref.read(deckListRepositoryProvider);
    await listRepo.init();
    if (deck.isCommanderDeck) {
      await listRepo.foldSideboardIntoMain(deck.id);
    }
    if (!mounted) return;
    setState(() {
      _deck = deck;
      _missing = false;
      _entries = listRepo.entriesFor(deck.id);
      if (!_facesReady && deck.commanderName.trim().isNotEmpty) {
        _loadingCards = true;
      }
    });
    await _loadCardDetails();
    await _loadCommanderExtras();
  }

  Future<void> _loadCommanderExtras() async {
    final deck = _deck;
    if (deck == null || !deck.isCommanderDeck) {
      if (mounted) {
        setState(() {
          _bracket = null;
          _meta = null;
          _fits = const [];
        });
      }
      return;
    }
    final cards = <BracketCard>[
      BracketCard(
        name: deck.commanderName,
        oracleText: _cards[_key(deck.commanderName)]?.oracleText,
      ),
      if (deck.partnerCommanderName != null &&
          deck.partnerCommanderName!.trim().isNotEmpty)
        BracketCard(
          name: deck.partnerCommanderName!,
          oracleText: _cards[_key(deck.partnerCommanderName!)]?.oracleText,
        ),
      for (final entry in _entries)
        if (entry.deckBoard != DeckBoard.sideboard)
          BracketCard(
            name: entry.name,
            oracleText: _cards[_key(entry.name)]?.oracleText,
          ),
    ];
    final comboResult = await ref
        .read(spellbookClientProvider)
        .findTwoCardCombos(
          commanders:
              [
                deck.commanderName,
                if (deck.partnerCommanderName != null)
                  deck.partnerCommanderName!,
              ].where((name) => name.trim().isNotEmpty).toList(),
          main: [
            for (final entry in _entries)
              if (entry.deckBoard == DeckBoard.main) entry.name,
          ],
        );
    final meta = await ref
        .read(edhrecClientProvider)
        .commanderMeta(deck.commanderName);
    final repo = ref.read(collectionRepositoryProvider);
    await repo.init();
    final fits = _fitsFor(deck, meta, repo.getAll());
    if (!mounted || _deck?.id != deck.id) return;
    setState(() {
      _bracket = assessBracket(
        cards,
        combos: comboResult.combos,
        combosUnavailable: comboResult.failed,
      );
      _meta = meta;
      _fits = fits;
    });
    await _attachSuggestionArt(deck, fits);
  }

  Future<void> _attachSuggestionArt(
    PlayerDeck deck,
    List<_DeckSuggestion> fits,
  ) async {
    final missing = [
      for (final fit in fits)
        if (_cards[_key(fit.name)] == null) fit.name,
    ];
    if (missing.isEmpty) return;
    final fetched = await ref
        .read(scryfallServiceProvider)
        .fetchCardsByNames(missing);
    if (!mounted || _deck?.id != deck.id || fetched.isEmpty) return;
    setState(() {
      final next = Map<String, ScryfallCard>.from(_cards);
      for (final card in fetched) {
        next[_key(card.name)] = card;
      }
      _cards = next;
    });
  }

  List<_DeckSuggestion> _suggestionsFor(
    PlayerDeck deck,
    CommanderMeta? meta,
    List<CollectionEntry> owned,
  ) {
    if (meta == null || deckRoom(deck, _entries) == 0) return const [];
    final inDeck = {
      for (final entry in _entries) bracketNameKey(entry.name),
      bracketNameKey(deck.commanderName),
      if (deck.partnerCommanderName != null)
        bracketNameKey(deck.partnerCommanderName!),
    };
    final ownedKeys = {for (final entry in owned) bracketNameKey(entry.name)};
    final suggestions = <_DeckSuggestion>[];
    for (final name in meta.commonCards) {
      final key = bracketNameKey(name);
      if (key.isEmpty || inDeck.contains(key)) continue;
      suggestions.add(
        _DeckSuggestion(
          name: name,
          owned: ownedKeys.contains(key),
          inclusion: meta.inclusionFor(name) ?? 0,
        ),
      );
      if (suggestions.length == 8) break;
    }
    return suggestions;
  }

  List<_DeckSuggestion> _fitsFor(
    PlayerDeck deck,
    CommanderMeta? meta,
    List<CollectionEntry> owned,
  ) {
    if (meta == null) return const [];
    if (deck.isCommanderDeck &&
        deckSize(deck, _entries) > formatDeckSize(deck.gameFormat)) {
      return _cutsFor(deck, meta);
    }
    return _suggestionsFor(deck, meta, owned);
  }

  List<_DeckSuggestion> _cutsFor(PlayerDeck deck, CommanderMeta meta) {
    final ranked = <_DeckSuggestion>[];
    for (final entry in _entries) {
      if (entry.deckBoard != DeckBoard.main) continue;
      if (_isCoverCard(deck, entry) || _isLand(entry.name)) continue;
      ranked.add(
        _DeckSuggestion(
          name: entry.name,
          owned: true,
          inclusion: meta.inclusionFor(entry.name) ?? 0,
          cut: true,
        ),
      );
    }
    ranked.sort((a, b) {
      final byInclusion = a.inclusion.compareTo(b.inclusion);
      if (byInclusion != 0) return byInclusion;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (ranked.length <= 8) return ranked;
    return ranked.sublist(0, 8);
  }

  bool _isLand(String name) {
    final line = _cards[_key(name)]?.typeLine?.toLowerCase() ?? '';
    return RegExp(r'\bland\b').hasMatch(line);
  }

  List<String>? _commanderColors(PlayerDeck deck) {
    if (!deck.isCommanderDeck) return null;
    if (deck.commanderColorIdentity.isNotEmpty) {
      return deck.commanderColorIdentity;
    }
    final primary = _cards[_key(deck.commanderName)];
    if (primary == null) return null;
    final partnerName = deck.partnerCommanderName;
    final partner = partnerName == null ? null : _cards[_key(partnerName)];
    return ScryfallCard.unionColorIdentity(primary, partner);
  }

  Future<bool> _colorsAllow(PlayerDeck deck, String name) async {
    final allowed = _commanderColors(deck);
    if (allowed == null) return true;
    var card = _cards[_key(name)];
    if (card == null) {
      final fetched = await ref.read(scryfallServiceProvider).fetchCardsByNames(
        [name],
      );
      if (fetched.isNotEmpty) card = fetched.first;
    }
    if (card == null) return true;
    return !outsideCommanderColors(allowed, card.colorIdentity);
  }

  Future<String?> _firstOffColor(
    PlayerDeck deck,
    List<ParsedDeckCard> cards,
  ) async {
    if (!deck.isCommanderDeck) return null;
    final names = [
      for (final card in cards) card.name,
      if (deck.commanderColorIdentity.isEmpty &&
          deck.commanderName.trim().isNotEmpty)
        deck.commanderName,
      if (deck.commanderColorIdentity.isEmpty &&
          deck.partnerCommanderName?.trim().isNotEmpty == true)
        deck.partnerCommanderName!,
    ];
    final fetched = await ref
        .read(scryfallServiceProvider)
        .fetchCardsByNames(names);
    final byName = {for (final card in fetched) _key(card.name): card};
    var allowed = deck.commanderColorIdentity;
    if (allowed.isEmpty) {
      final primary = byName[_key(deck.commanderName)];
      if (primary == null) return null;
      final partnerName = deck.partnerCommanderName;
      final partner = partnerName == null ? null : byName[_key(partnerName)];
      allowed = ScryfallCard.unionColorIdentity(primary, partner);
    }
    for (final card in cards) {
      final details = byName[_key(card.name)];
      if (details == null) continue;
      if (outsideCommanderColors(allowed, details.colorIdentity)) {
        return card.name;
      }
    }
    return null;
  }

  Future<void> _addFit(String name) async {
    final deck = _deck;
    if (deck == null) return;
    if (!await _colorsAllow(deck, name)) {
      if (!mounted) return;
      showUiSnackBar(
        context,
        AppLocalizations.of(context).deckAlbumOffColor(name),
        isError: true,
      );
      return;
    }
    if (addableCopies(deck, _entries, name, DeckBoard.main) < 1) return;
    await ref.read(deckListRepositoryProvider).addOneToMain(deck.id, name);
    if (!mounted) return;
    await _reload();
  }

  Future<void> _openSuggestion(_DeckSuggestion fit) async {
    final deck = _deck;
    if (deck == null) return;
    if (fit.cut) {
      final l10n = AppLocalizations.of(context);
      await showAlbumCardViewer(
        context,
        name: fit.name,
        imageUrl: _faceUrl(_cards[_key(fit.name)]),
        note: l10n.deckAlbumPlayedIn(fit.percent),
        actionLabel: l10n.deckAlbumRemoveCard,
        onAction: () => _changeCount(fit.name, -1, sideboard: false),
      );
      return;
    }
    var card = _cards[_key(fit.name)];
    if (card == null) {
      final fetched = await ref.read(scryfallServiceProvider).fetchCardsByNames(
        [fit.name],
      );
      if (fetched.isNotEmpty) card = fetched.first;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final percent = fit.percent;
    await showAlbumCardViewer(
      context,
      name: fit.name,
      imageUrl: _faceUrl(card),
      note: percent == 0 ? null : l10n.deckAlbumPlayedIn(percent),
      actionLabel: l10n.commonAdd,
      onAction: () => _addFit(fit.name),
    );
  }

  Future<void> _moveCopy(String name, {required bool toSideboard}) async {
    final deck = _deck;
    if (deck == null || deck.isCommanderDeck) return;
    final from = toSideboard ? DeckBoard.main : DeckBoard.sideboard;
    final to = toSideboard ? DeckBoard.sideboard : DeckBoard.main;
    if (addableCopies(deck, _entries, name, to) < 1) {
      final l10n = AppLocalizations.of(context);
      showUiSnackBar(
        context,
        to == DeckBoard.sideboard
            ? l10n.deckAlbumSideboardLimit(formatSideboardSize(deck.gameFormat))
            : l10n.deckAlbumCannotAdd,
        isError: true,
      );
      return;
    }
    await ref
        .read(deckListRepositoryProvider)
        .moveOne(deck.id, name, from: from, to: to);
    if (!mounted) return;
    await _reload();
  }

  void _revealSideboard() {
    final target = _sideboardKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _pickBracket() async {
    final deck = _deck;
    final assessment = _bracket;
    if (deck == null || !deck.isCommanderDeck || assessment == null) return;
    final picked = await showDialog<int>(
      context: context,
      builder:
          (context) => _BracketPickerDialog(
            minimum: assessment.minimumChoice,
            selected: deck.chosenBracket,
          ),
    );
    if (picked == null || !mounted) return;
    deck.chosenBracket = picked;
    await ref.read(deckRepositoryProvider).save(deck);
    if (!mounted) return;
    setState(() => _deck = deck);
  }

  Future<void> _changeCount(
    String name,
    int delta, {
    required bool sideboard,
  }) async {
    final deck = _deck;
    if (deck == null || delta == 0) return;
    final board = sideboard ? DeckBoard.sideboard : DeckBoard.main;
    if (delta > 0 && addableCopies(deck, _entries, name, board) < 1) return;
    final repo = ref.read(deckListRepositoryProvider);
    final removed = await repo.changeCount(
      deck.id,
      name,
      board: board,
      delta: delta,
    );
    if (!mounted) return;
    setState(() => _entries = repo.entriesFor(deck.id));
    if (deck.isCommanderDeck) {
      final owned = ref.read(collectionRepositoryProvider).getAll();
      final fits = _fitsFor(deck, _meta, owned);
      setState(() => _fits = fits);
      if (!removed) await _attachSuggestionArt(deck, fits);
    }
    if (removed) await _loadCommanderExtras();
  }

  Future<void> _loadCardDetails() async {
    final deck = _deck;
    final names = <String>[
      ..._visibleEntries(deck, _entries).map((entry) => entry.name),
      if (deck != null && deck.commanderName.trim().isNotEmpty)
        deck.commanderName,
      if (deck?.partnerCommanderName?.trim().isNotEmpty == true)
        deck!.partnerCommanderName!,
    ];
    if (names.isEmpty) {
      if (mounted) {
        setState(() {
          _cards = const {};
          _loadingCards = false;
          _facesReady = true;
        });
      }
      return;
    }
    setState(() => _loadingCards = true);
    final cards = await ref
        .read(scryfallServiceProvider)
        .fetchCardsByNames(names);
    if (!mounted) return;
    final byName = <String, ScryfallCard>{};
    for (final card in cards) {
      byName[_key(card.name)] = card;
    }
    setState(() {
      _cards = byName;
      _loadingCards = false;
      _facesReady = true;
    });
  }

  Future<void> _editCommander() async {
    final deck = _deck;
    if (deck == null || !deck.isCommanderDeck) return;
    await applyDeckSheetAction(
      context: context,
      ref: ref,
      repo: ref.read(deckRepositoryProvider),
      deck: deck,
      action: DeckSheetAction.editCover,
    );
    if (!mounted) return;
    await _reload();
  }

  Future<void> _openOptions() async {
    final deck = _deck;
    if (deck == null) return;
    final action = await showDeckDetailSheet(context, deck);
    if (action == null || !mounted) return;
    if (action == DeckSheetAction.pasteList) {
      await _pasteList();
      return;
    }
    if (action == DeckSheetAction.copyList) {
      await _copyList();
      return;
    }
    final deleted = await applyDeckSheetAction(
      context: context,
      ref: ref,
      repo: ref.read(deckRepositoryProvider),
      deck: deck,
      action: action,
    );
    if (!mounted) return;
    if (deleted) {
      context.pop();
      return;
    }
    await _reload();
  }

  Future<void> _addCards() async {
    final deck = _deck;
    if (deck == null) return;
    final l10n = AppLocalizations.of(context);
    final choice = await showCollectionAddSheet(
      context,
      searchBody: l10n.deckAddSearchBody,
      pasteBody: l10n.deckAddPasteBody,
    );
    if (!mounted || choice == null) return;
    if (choice == CollectionAddChoice.paste) {
      await _pasteList();
      return;
    }
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder:
            (_) => CollectionSearchPage(
              rejectionFor: (card) {
                final allowed = _commanderColors(deck);
                if (allowed == null) return null;
                if (!outsideCommanderColors(allowed, card.colorIdentity)) {
                  return null;
                }
                return l10n.deckAlbumOffColor(card.name);
              },
              onAdd: (name, count) async {
                final repo = ref.read(deckListRepositoryProvider);
                await repo.init();
                final allowed = addableCopies(
                  deck,
                  repo.entriesFor(deck.id),
                  name,
                  DeckBoard.main,
                );
                final adding = count < allowed ? count : allowed;
                if (adding < 1) return 0;
                await repo.addToMain(deck.id, name, count: adding);
                return adding;
              },
            ),
      ),
    );
    if (added == true && mounted) await _reload();
  }

  Future<void> _pasteList() async {
    final deck = _deck;
    if (deck == null) return;
    final l10n = AppLocalizations.of(context);
    final existing = _entries.where(
      (entry) => entry.deckBoard != DeckBoard.commander,
    );
    if (existing.isNotEmpty) {
      final ok = await showGameConfirmDialog(
        context: context,
        title: l10n.deckAlbumReplaceTitle,
        message: l10n.deckAlbumReplaceBody,
        confirmLabel: l10n.deckAlbumReplaceConfirm,
      );
      if (ok != true || !mounted) return;
    }
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _PasteDeckListDialog(),
    );
    if (text == null || !mounted) return;
    final parsed = parseDeckList(
      text,
      commanderName: deck.commanderName,
      partnerName: deck.partnerCommanderName,
      identifyCommander: deck.isCommanderDeck,
    );
    if (parsed.cards.isEmpty) {
      showUiSnackBar(context, l10n.deckAlbumPasteEmpty, isError: true);
      return;
    }
    switch (pastedListIssue(deck, parsed.cards)) {
      case DeckLimitIssue.none:
        break;
      case DeckLimitIssue.deckFull:
        showUiSnackBar(
          context,
          l10n.deckAlbumPasteTooBig(
            deck.gameFormat.displayName,
            formatDeckSize(deck.gameFormat),
          ),
          isError: true,
        );
        return;
      case DeckLimitIssue.sideboardFull:
        showUiSnackBar(
          context,
          l10n.deckAlbumSideboardLimit(formatSideboardSize(deck.gameFormat)),
          isError: true,
        );
        return;
      case DeckLimitIssue.copyLimit:
        showUiSnackBar(context, l10n.deckAlbumCopyLimit, isError: true);
        return;
    }
    final offColor = await _firstOffColor(deck, parsed.cards);
    if (!mounted) return;
    if (offColor != null) {
      showUiSnackBar(context, l10n.deckAlbumOffColor(offColor), isError: true);
      return;
    }
    await ref
        .read(deckListRepositoryProvider)
        .replaceDeckList(deck.id, parsed.cards);
    if (!mounted) return;
    showUiSnackBar(
      context,
      parsed.skippedLines > 0
          ? l10n.deckAlbumPasteSkipped(parsed.skippedLines)
          : l10n.deckAlbumPasteSaved(parsed.totalCards),
    );
    await _reload();
  }

  Future<void> _copyList() async {
    final deck = _deck;
    if (deck == null) return;
    final l10n = AppLocalizations.of(context);
    final text = exportDeckList(
      entries: _entries,
      commanderName: deck.commanderName,
      partnerName: deck.partnerCommanderName,
      identifyCommander: deck.isCommanderDeck,
    );
    if (text.isEmpty) {
      showUiSnackBar(context, l10n.deckAlbumPasteEmpty, isError: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showUiSnackBar(context, l10n.deckAlbumCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final deck = _deck;

    final coverBleeds = deck != null && !_showTitle;
    return Scaffold(
      extendBodyBehindAppBar: deck != null,
      appBar: UiAppBar(
        backgroundColor: coverBleeds ? Colors.transparent : null,
        title:
            deck == null
                ? l10n.deckAlbumTitle
                : _showTitle
                ? deck.displayName
                : null,
        actions: [
          if (deck != null)
            IconButton(
              tooltip: l10n.deckAlbumOptions,
              onPressed: _openOptions,
              icon: const Icon(Icons.more_horiz),
            ),
        ],
      ),
      body:
          _missing
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(LayoutTokens.gr4),
                  child: Text(
                    l10n.deckAlbumMissing,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: FontTokens.body,
                    ),
                  ),
                ),
              )
              : deck == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.axis != Axis.vertical) {
                        return false;
                      }
                      final show = notification.metrics.pixels > 96;
                      if (show != _showTitle) {
                        setState(() => _showTitle = show);
                      }
                      return false;
                    },
                    child: _AlbumBody(
                      deck: deck,
                      entries: _visibleEntries(deck, _entries),
                      cards: _cards,
                      loadingCards: _loadingCards,
                      bracket: _bracket,
                      meta: _meta,
                      fits: _fits,
                      listing: ref.watch(albumListingProvider),
                      onListing: (value) {
                        ref.read(albumListingProvider.notifier).state = value;
                      },
                      onOpenFit: _openSuggestion,
                      onCount: _changeCount,
                      onMoveCopy: _moveCopy,
                      onRevealSideboard: _revealSideboard,
                      sideboardKey: _sideboardKey,
                      onPickBracket: _pickBracket,
                      onEditCommander:
                          deck.isCommanderDeck ? _editCommander : null,
                      showStats: _showStats,
                      onShowStats:
                          (value) => setState(() => _showStats = value),
                    ),
                  ),
                  if (!_showStats && deckRoom(deck, _entries) > 0)
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

AlbumListCard _albumCard(
  BuildContext context,
  PlayerDeck deck,
  List<DeckCardEntry> entries,
  Map<String, ScryfallCard> cards,
  CommanderMeta? meta,
  DeckCardEntry entry,
) {
  return AlbumListCard(
    name: entry.name,
    count: entry.count,
    group: deckCardGroupForTypeLine(cards[_key(entry.name)]?.typeLine),
    imageUrl: _faceUrl(cards[_key(entry.name)]),
    manaCost: cards[_key(entry.name)]?.manaCost,
    inclusion: meta?.inclusionFor(entry.name),
    canAddCopy: addableCopies(deck, entries, entry.name, entry.deckBoard) > 0,
    warning: _cardWarning(context, deck, cards, entry),
  );
}

String? _cardWarning(
  BuildContext context,
  PlayerDeck deck,
  Map<String, ScryfallCard> cards,
  DeckCardEntry entry,
) {
  final l10n = AppLocalizations.of(context);
  final notes = <String>[];
  if (entry.count > copyLimit(entry.name, deck.gameFormat)) {
    notes.add(l10n.deckAlbumCopyLimit);
  }
  final card = cards[_key(entry.name)];
  final allowed = _knownCommanderColors(deck, cards);
  if (allowed != null &&
      card != null &&
      outsideCommanderColors(allowed, card.colorIdentity)) {
    notes.add(l10n.deckAlbumOffColor(entry.name));
  }
  if (notes.isEmpty) return null;
  return notes.join(' ');
}

List<String>? _knownCommanderColors(
  PlayerDeck deck,
  Map<String, ScryfallCard> cards,
) {
  if (!deck.isCommanderDeck) return null;
  if (deck.commanderColorIdentity.isNotEmpty) {
    return deck.commanderColorIdentity;
  }
  final primary = cards[_key(deck.commanderName)];
  if (primary == null) return null;
  final partnerName = deck.partnerCommanderName;
  final partner = partnerName == null ? null : cards[_key(partnerName)];
  return ScryfallCard.unionColorIdentity(primary, partner);
}

List<DeckCardEntry> _visibleEntries(
  PlayerDeck? deck,
  List<DeckCardEntry> entries,
) {
  if (deck == null) return const [];
  return entries.where((entry) => !_isCoverCard(deck, entry)).toList();
}

bool _isCoverCard(PlayerDeck deck, DeckCardEntry entry) {
  if (!deck.isCommanderDeck || entry.deckBoard != DeckBoard.commander) {
    return false;
  }
  final name = _key(entry.name);
  if (name.isEmpty) return false;
  if (name == _key(deck.commanderName)) return true;
  final partner = deck.partnerCommanderName;
  return partner != null && name == _key(partner);
}

String _key(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String? _faceUrl(ScryfallCard? card) {
  final face = card?.cardFaceUrl;
  if (face != null && face.isNotEmpty) return face;
  return card?.imageUrl;
}

class _AlbumBody extends StatelessWidget {
  const _AlbumBody({
    required this.deck,
    required this.entries,
    required this.cards,
    required this.loadingCards,
    required this.bracket,
    required this.meta,
    required this.fits,
    required this.listing,
    required this.onListing,
    required this.onOpenFit,
    required this.onCount,
    required this.onMoveCopy,
    required this.onRevealSideboard,
    required this.sideboardKey,
    required this.showStats,
    required this.onShowStats,
    required this.onPickBracket,
    this.onEditCommander,
  });

  final PlayerDeck deck;
  final List<DeckCardEntry> entries;
  final Map<String, ScryfallCard> cards;
  final bool loadingCards;
  final BracketAssessment? bracket;
  final CommanderMeta? meta;
  final List<_DeckSuggestion> fits;
  final AlbumListing listing;
  final ValueChanged<AlbumListing> onListing;
  final ValueChanged<_DeckSuggestion> onOpenFit;
  final void Function(String name, int delta, {required bool sideboard})
  onCount;
  final void Function(String name, {required bool toSideboard}) onMoveCopy;
  final VoidCallback onRevealSideboard;
  final Key sideboardKey;
  final bool showStats;
  final ValueChanged<bool> onShowStats;
  final VoidCallback onPickBracket;
  final VoidCallback? onEditCommander;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    final main =
        entries
            .where((entry) => entry.deckBoard != DeckBoard.sideboard)
            .toList();
    final side =
        entries
            .where((entry) => entry.deckBoard == DeckBoard.sideboard)
            .toList();
    final reserveAction = !showStats && deckRoom(deck, entries) > 0;
    return ListView(
      padding: EdgeInsets.only(
        bottom:
            reserveAction
                ? BlurredBottomAction.height(context)
                : MediaQuery.paddingOf(context).bottom + LayoutTokens.gr4,
      ),
      children: [
        _DeckAlbumHeader(
          deck: deck,
          themeTags: meta?.themeTags ?? const [],
          bracket: bracket,
          onBracketTap: onPickBracket,
          onCommanderTap: onEditCommander,
          loadingFaces: loadingCards,
          commanderFaceUrl: _faceUrl(cards[_key(deck.commanderName)]),
          partnerFaceUrl:
              deck.partnerCommanderName == null
                  ? null
                  : _faceUrl(cards[_key(deck.partnerCommanderName!)]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gr4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: LayoutTokens.gr3),
              DeckAlbumPageSwitch(showStats: showStats, onChanged: onShowStats),
              if (showStats)
                _DeckSizeLine(
                  deck: deck,
                  entries: entries,
                  onSideboard: deck.isCommanderDeck ? null : onRevealSideboard,
                ),
              if (loadingCards) ...[
                SizedBox(height: LayoutTokens.gr2),
                const LinearProgressIndicator(),
              ],
              if (showStats)
                DeckStatsView(deck: deck, entries: entries, cards: cards)
              else ...[
                if (deck.isCommanderDeck)
                  Padding(
                    padding: const EdgeInsets.only(top: LayoutTokens.gr2),
                    child: _BracketCauses(assessment: bracket),
                  ),
                if (deck.isCommanderDeck && fits.isNotEmpty) ...[
                  SizedBox(height: LayoutTokens.gr2),
                  _FitsRow(
                    fits: fits,
                    imageFor: (name) => _faceUrl(cards[_key(name)]),
                    onOpen: onOpenFit,
                  ),
                ],
                if (entries.isEmpty) ...[
                  _DeckSizeLine(
                    deck: deck,
                    entries: entries,
                    onSideboard:
                        deck.isCommanderDeck ? null : onRevealSideboard,
                  ),
                  SizedBox(height: LayoutTokens.gr3),
                  Text(
                    l10n.deckAlbumEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: FontTokens.body,
                    ),
                  ),
                  if (!deck.isCommanderDeck)
                    KeyedSubtree(
                      key: sideboardKey,
                      child: Padding(
                        padding: const EdgeInsets.only(top: LayoutTokens.gr5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${l10n.deckAlbumSideboard} 0/${formatSideboardSize(deck.gameFormat)}',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: FontTokens.title,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: LayoutTokens.gr1),
                            Text(
                              l10n.deckAlbumSideboardEmpty,
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: FontTokens.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ] else ...[
                  SizedBox(height: LayoutTokens.gr2),
                  AlbumCardBrowser(
                    listing: listing,
                    onListing: onListing,
                    aboveSections: _DeckSizeLine(
                      deck: deck,
                      entries: entries,
                      onSideboard:
                          deck.isCommanderDeck ? null : onRevealSideboard,
                    ),
                    sideboardMax:
                        deck.isCommanderDeck
                            ? null
                            : formatSideboardSize(deck.gameFormat),
                    showEmptySideboard: !deck.isCommanderDeck,
                    sideboardKey: sideboardKey,
                    cards: [
                      for (final entry in main)
                        _albumCard(context, deck, entries, cards, meta, entry),
                    ],
                    onCount:
                        (card, delta) =>
                            onCount(card.name, delta, sideboard: false),
                    onSideCount:
                        (card, delta) =>
                            onCount(card.name, delta, sideboard: true),
                    onMoveToSideboard:
                        deck.isCommanderDeck
                            ? null
                            : (card) =>
                                onMoveCopy(card.name, toSideboard: true),
                    onMoveToMain:
                        deck.isCommanderDeck
                            ? null
                            : (card) =>
                                onMoveCopy(card.name, toSideboard: false),
                    sideboard: [
                      for (final entry in side)
                        _albumCard(context, deck, entries, cards, meta, entry),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DeckAlbumHeader extends StatelessWidget {
  const _DeckAlbumHeader({
    required this.deck,
    required this.themeTags,
    required this.bracket,
    required this.onBracketTap,
    this.onCommanderTap,
    this.loadingFaces = false,
    this.commanderFaceUrl,
    this.partnerFaceUrl,
  });

  final PlayerDeck deck;
  final List<String> themeTags;
  final BracketAssessment? bracket;
  final VoidCallback onBracketTap;
  final VoidCallback? onCommanderTap;
  final bool loadingFaces;
  final String? commanderFaceUrl;
  final String? partnerFaceUrl;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final style =
        deck.hasDeckStyle
            ? localizedDeckStyleName(l10n, deck.deckStyle!)
            : l10n.deckOptionsStyleNotSet;
    final identity = deck.commanderColorIdentity;
    final mana =
        identity.isEmpty ? '{C}' : identity.map((letter) => '{$letter}').join();
    final cover = deck.commanderImageUrl;
    final face = _portraitUrl(
      loading: loadingFaces,
      fetched: commanderFaceUrl,
      saved: deck.commanderImageUrl,
    );
    final partnerFace = _portraitUrl(
      loading: loadingFaces,
      fetched: partnerFaceUrl,
      saved: deck.partnerCommanderImageUrl,
    );
    final commander =
        deck.hasPartner
            ? '${deck.commanderName} / ${deck.partnerCommanderName}'
            : deck.commanderName;

    final shown = _shownBracket(deck, bracket);
    final badge =
        bracket == null
            ? '…'
            : shown == null
            ? '1–2'
            : '$shown';
    final winRatio =
        deck.gamesPlayed == 0 ? '—' : '${(deck.winRate * 100).round()}%';

    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: topInset + 196,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _DeckCover(url: cover),
              Positioned(
                top: topInset + LayoutTokens.gr1,
                right: LayoutTokens.gr4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (deck.isCommanderDeck) ...[
                      _CoverStat(
                        label: l10n.deckAlbumCardBracket,
                        value: badge,
                        onTap: onBracketTap,
                      ),
                      const SizedBox(width: LayoutTokens.gr1),
                    ],
                    _CoverStat(
                      label: l10n.deckTileWinRateAbbr,
                      value: winRatio,
                    ),
                    const SizedBox(width: LayoutTokens.gr1),
                    _CoverStat(
                      label: l10n.profileStatGames,
                      value: '${deck.gamesPlayed}',
                    ),
                  ],
                ),
              ),
              Positioned(
                left: LayoutTokens.gr4,
                right: LayoutTokens.gr4,
                bottom: LayoutTokens.gr3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _CommanderFaces(
                      face: face,
                      partner: deck.hasPartner ? partnerFace : null,
                      onTap: onCommanderTap,
                    ),
                    SizedBox(width: LayoutTokens.gr3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            deck.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: FontTokens.headline,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          if (commander.isNotEmpty) ...[
                            SizedBox(height: LayoutTokens.gr1),
                            Text(
                              commander,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: FontTokens.body,
                              ),
                            ),
                          ],
                          SizedBox(height: LayoutTokens.gr1),
                          Wrap(
                            spacing: LayoutTokens.gr1,
                            runSpacing: LayoutTokens.gr1,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${deck.gameFormat.displayName} · $style',
                                style: TextStyle(
                                  color: colors.textMuted,
                                  fontSize: FontTokens.caption,
                                ),
                              ),
                              ManaCostPips(manaCost: mana, symbolHeight: 14),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (themeTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LayoutTokens.gr4,
              LayoutTokens.gr3,
              LayoutTokens.gr4,
              0,
            ),
            child: Wrap(
              spacing: LayoutTokens.gr1,
              runSpacing: LayoutTokens.gr1,
              children: [
                for (final tag in themeTags)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      tag,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: FontTokens.caption,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String? _portraitUrl({
  required bool loading,
  required String? fetched,
  required String? saved,
}) {
  if (fetched != null && fetched.isNotEmpty) return fetched;
  if (loading) return null;
  if (saved != null && saved.isNotEmpty) return saved;
  return null;
}

class _DeckCover extends StatelessWidget {
  const _DeckCover({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final image = url;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image == null || image.isEmpty)
            ColoredBox(color: colors.surface)
          else
            CachedNetworkImage(
              imageUrl: image,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (_, __) => ColoredBox(color: colors.surface),
              errorWidget: (_, __, ___) => ColoredBox(color: colors.surface),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.backgroundPrimary.withValues(alpha: 0),
                  colors.backgroundPrimary.withValues(alpha: 0.08),
                  colors.backgroundPrimary.withValues(alpha: 0.38),
                  colors.backgroundPrimary.withValues(alpha: 0.72),
                  colors.backgroundPrimary.withValues(alpha: 0.94),
                  colors.backgroundPrimary,
                ],
                stops: const [0.08, 0.28, 0.46, 0.64, 0.82, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int? _shownBracket(PlayerDeck deck, BracketAssessment? assessment) {
  final chosen = deck.chosenBracket;
  final floor = assessment?.floor;
  if (floor == null) return null;
  if (chosen == null) {
    return assessment!.choosesOneOrTwo ? null : floor;
  }
  if (chosen < assessment!.minimumChoice) return assessment.minimumChoice;
  return chosen;
}

class _CommanderFaces extends StatelessWidget {
  const _CommanderFaces({required this.face, this.partner, this.onTap});

  final String? face;
  final String? partner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasPartner = partner != null && partner!.isNotEmpty;
    final faces = SizedBox(
      width: hasPartner ? 104 : 88,
      height: 122,
      child: Stack(
        children: [
          if (hasPartner)
            Positioned(
              left: 0,
              top: 14,
              child: _DeckPortrait(url: partner, width: 72, height: 100),
            ),
          Positioned(
            right: 0,
            top: 0,
            child: _DeckPortrait(url: face, width: 88, height: 122),
          ),
        ],
      ),
    );
    if (onTap == null) return faces;
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.commanderSelectEditCommanders,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: faces),
      ),
    );
  }
}

class _DeckPortrait extends StatelessWidget {
  const _DeckPortrait({
    required this.url,
    required this.width,
    required this.height,
  });

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final image = url;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RadiusTokens.sm),
        boxShadow: [
          BoxShadow(
            color: colors.backgroundPrimary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RadiusTokens.sm),
        child: SizedBox(
          width: width,
          height: height,
          child:
              image == null || image.isEmpty
                  ? ColoredBox(color: colors.surface)
                  : CachedNetworkImage(
                    imageUrl: image,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => ColoredBox(color: colors.surface),
                    errorWidget:
                        (_, __, ___) => ColoredBox(color: colors.surface),
                  ),
        ),
      ),
    );
  }
}

class _CoverStat extends StatelessWidget {
  const _CoverStat({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final circle = Container(
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surface,
        border: Border.all(color: colors.primaryAccent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              color: colors.primaryAccent,
              fontSize: value.length > 3 ? 12 : 16,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return circle;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(onTap: onTap, child: circle),
    );
  }
}

class _DeckSizeLine extends StatelessWidget {
  const _DeckSizeLine({
    required this.deck,
    required this.entries,
    this.onSideboard,
  });

  final PlayerDeck deck;
  final List<DeckCardEntry> entries;
  final VoidCallback? onSideboard;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final label = deckCountLabel(deck, entries);
    TextStyle style(bool illegal) {
      return TextStyle(
        color: illegal ? colors.error : colors.textPrimary,
        fontSize: FontTokens.body,
        fontWeight: FontWeight.w800,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: LayoutTokens.gr3),
      child: Row(
        children: [
          Text(label.main, style: style(label.mainIllegal)),
          if (label.side != null) ...[
            SizedBox(width: LayoutTokens.gr3),
            InkWell(
              onTap: onSideboard,
              borderRadius: BorderRadius.circular(RadiusTokens.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${l10n.deckAlbumSideboard} ${label.side}',
                      style: style(label.sideIllegal),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color:
                          label.sideIllegal
                              ? colors.error
                              : colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BracketCauses extends StatelessWidget {
  const _BracketCauses({required this.assessment});

  final BracketAssessment? assessment;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    if (assessment == null) return const SizedBox.shrink();
    final hasCause =
        assessment!.gameChangers.isNotEmpty ||
        assessment!.massLandDenial.isNotEmpty ||
        assessment!.extraTurns.isNotEmpty ||
        assessment!.combos.isNotEmpty ||
        assessment!.combosUnavailable;
    if (!hasCause) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (assessment!.gameChangers.isNotEmpty)
          _CauseGroup(
            title: l10n.deckBracketGameChangers,
            cards: assessment!.gameChangers,
          ),
        if (assessment!.massLandDenial.isNotEmpty)
          _CauseGroup(
            title: l10n.deckBracketMassLandDenial,
            cards: assessment!.massLandDenial,
          ),
        if (assessment!.extraTurns.isNotEmpty)
          _CauseGroup(
            title: l10n.deckBracketExtraTurns,
            cards: assessment!.extraTurns,
          ),
        if (assessment!.combos.any((combo) => combo.early))
          _ComboGroup(
            title: l10n.deckBracketEarlyCombos,
            combos: [
              for (final combo in assessment!.combos)
                if (combo.early) combo,
            ],
          ),
        if (assessment!.combos.any((combo) => !combo.early))
          _ComboGroup(
            title: l10n.deckBracketCombos,
            combos: [
              for (final combo in assessment!.combos)
                if (!combo.early) combo,
            ],
          ),
        if (assessment!.combosUnavailable) ...[
          SizedBox(height: LayoutTokens.gr2),
          Text(
            l10n.deckBracketCombosUnavailable,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: FontTokens.caption,
            ),
          ),
        ],
      ],
    );
  }
}

class _CauseGroup extends StatefulWidget {
  const _CauseGroup({required this.title, required this.cards});

  final String title;
  final List<String> cards;

  @override
  State<_CauseGroup> createState() => _CauseGroupState();
}

class _CauseGroupState extends State<_CauseGroup> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: LayoutTokens.gr2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CauseHeading(
            title: widget.title,
            count: widget.cards.length,
            open: _open,
            onToggle: () => setState(() => _open = !_open),
          ),
          if (_open) ...[
            SizedBox(height: LayoutTokens.gr1),
            Wrap(
              spacing: LayoutTokens.gr1,
              runSpacing: LayoutTokens.gr1,
              children: [
                for (final name in widget.cards)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      name,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: FontTokens.caption,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ComboGroup extends StatefulWidget {
  const _ComboGroup({required this.title, required this.combos});

  final String title;
  final List<BracketCombo> combos;

  @override
  State<_ComboGroup> createState() => _ComboGroupState();
}

class _ComboGroupState extends State<_ComboGroup> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: LayoutTokens.gr2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CauseHeading(
            title: widget.title,
            count: widget.combos.length,
            open: _open,
            onToggle: () => setState(() => _open = !_open),
          ),
          if (_open) ...[
            SizedBox(height: LayoutTokens.gr1),
            for (final combo in widget.combos)
              Padding(
                padding: const EdgeInsets.only(bottom: LayoutTokens.gr1),
                child: Text.rich(
                  TextSpan(
                    children: [
                      for (var i = 0; i < combo.cards.length; i++) ...[
                        if (i > 0)
                          TextSpan(
                            text: '  +  ',
                            style: TextStyle(color: colors.textMuted),
                          ),
                        TextSpan(text: combo.cards[i]),
                      ],
                    ],
                  ),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: FontTokens.caption,
                    height: 1.3,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CauseHeading extends StatelessWidget {
  const _CauseHeading({
    required this.title,
    required this.count,
    required this.open,
    required this.onToggle,
  });

  final String title;
  final int count;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return InkWell(
      onTap: onToggle,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: FontTokens.caption,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: FontTokens.caption,
            ),
          ),
          Icon(
            open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            size: 20,
            color: colors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _DeckSuggestion {
  const _DeckSuggestion({
    required this.name,
    required this.owned,
    required this.inclusion,
    this.cut = false,
  });

  final String name;
  final bool owned;
  final double inclusion;
  final bool cut;

  int get percent {
    if (inclusion <= 0) return 0;
    final value = inclusion > 1 ? inclusion : inclusion * 100;
    return value.round().clamp(1, 100);
  }
}

class _FitsRow extends StatelessWidget {
  const _FitsRow({
    required this.fits,
    required this.imageFor,
    required this.onOpen,
  });

  final List<_DeckSuggestion> fits;
  final String? Function(String name) imageFor;
  final ValueChanged<_DeckSuggestion> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fits.any((fit) => fit.cut) ? l10n.deckAlbumCuts : l10n.deckAlbumFits,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: FontTokens.caption,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: LayoutTokens.gr2),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: fits.length,
            separatorBuilder: (_, __) => SizedBox(width: LayoutTokens.gr2),
            itemBuilder: (context, index) {
              final entry = fits[index];
              return _SuggestionCard(
                name: entry.name,
                imageUrl: imageFor(entry.name),
                owned: entry.owned,
                onTap: () => onOpen(entry),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.name,
    required this.imageUrl,
    required this.owned,
    required this.onTap,
  });

  final String name;
  final String? imageUrl;
  final bool owned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final url = imageUrl;
    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(RadiusTokens.md),
              child: SizedBox(
                width: 92,
                height: 128,
                child:
                    url == null || url.isEmpty
                        ? ColoredBox(
                          color: colors.surface,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(LayoutTokens.gr1),
                              child: Text(
                                name,
                                textAlign: TextAlign.center,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: FontTokens.caption,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        )
                        : CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder:
                              (_, __) => ColoredBox(color: colors.surface),
                          errorWidget:
                              (_, __, ___) => ColoredBox(color: colors.surface),
                        ),
              ),
            ),
            if (owned)
              Positioned(
                top: 6,
                right: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: colors.primaryAccent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BracketPickerDialog extends StatelessWidget {
  const _BracketPickerDialog({required this.minimum, required this.selected});

  final int minimum;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(l10n.deckAlbumCardBracket),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.deckBracketChoose,
            style: TextStyle(color: colors.textSecondary, height: 1.35),
          ),
          SizedBox(height: LayoutTokens.gr3),
          Wrap(
            spacing: LayoutTokens.gr1,
            children: [
              for (var value = 1; value <= 5; value++)
                ChoiceChip(
                  label: Text('$value'),
                  selected: selected == value,
                  onSelected:
                      value < minimum
                          ? null
                          : (_) => Navigator.of(context).pop(value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PasteDeckListDialog extends StatefulWidget {
  const _PasteDeckListDialog();

  @override
  State<_PasteDeckListDialog> createState() => _PasteDeckListDialogState();
}

class _PasteDeckListDialogState extends State<_PasteDeckListDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColorTokens.of(context);
    return AlertDialog(
      title: Text(l10n.deckAlbumPasteTitle),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 8,
          maxLines: 14,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: FontTokens.body,
          ),
          decoration: InputDecoration(hintText: l10n.deckAlbumPasteHint),
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
