import '../game/game_format.dart';
import '../models/deck_card_entry.dart';
import '../models/player_deck.dart';
import 'bracket_names.dart';
import 'deck_list_text.dart';

/// Commander is exactly 100, commander included. Constructed has no maximum.
int formatDeckSize(GameFormat format) => format.isCommanderStyle ? 100 : 60;

const _manaColors = {'W', 'U', 'B', 'R', 'G'};

/// True when [cardColors] uses a color the commander's identity does not have.
/// An empty card identity is colorless and always fits.
bool outsideCommanderColors(
  Iterable<String> commanderIdentity,
  Iterable<String> cardColors,
) {
  final allowed = commanderIdentity.where(_manaColors.contains).toSet();
  for (final color in cardColors) {
    if (_manaColors.contains(color) && !allowed.contains(color)) return true;
  }
  return false;
}

/// Constructed sideboards stop at 15. Commander has no sideboard.
int formatSideboardSize(GameFormat format) => format.isCommanderStyle ? 0 : 15;

int copyLimit(String name, GameFormat format) {
  if (_ignoresCopyLimit(name)) return 99;
  final key = bracketNameKey(name);
  if (key == 'seven dwarves') return 7;
  if (key == 'nazgul' || key == 'nazgûl') return 9;
  return format.isCommanderStyle ? 1 : 4;
}

enum DeckLimitIssue { none, deckFull, copyLimit, sideboardFull }

DeckLimitIssue pastedListIssue(PlayerDeck deck, List<ParsedDeckCard> cards) {
  var main = 0;
  var side = 0;
  for (final card in cards) {
    if (card.count > copyLimit(card.name, deck.gameFormat)) {
      return DeckLimitIssue.copyLimit;
    }
    if (card.board == DeckBoard.sideboard) {
      side += card.count;
    } else if (card.board == DeckBoard.main) {
      main += card.count;
    }
  }
  if (deck.isCommanderDeck &&
      commanderSlots(deck) + main > formatDeckSize(deck.gameFormat)) {
    return DeckLimitIssue.deckFull;
  }
  if (side > formatSideboardSize(deck.gameFormat)) {
    return DeckLimitIssue.sideboardFull;
  }
  return DeckLimitIssue.none;
}

int commanderSlots(PlayerDeck deck) =>
    deck.isCommanderDeck ? (deck.hasPartner ? 2 : 1) : 0;

int boardCount(Iterable<DeckCardEntry> entries, DeckBoard board) => entries
    .where((entry) => entry.deckBoard == board)
    .fold(0, (sum, entry) => sum + entry.count);

int deckSize(PlayerDeck deck, Iterable<DeckCardEntry> entries) =>
    commanderSlots(deck) + boardCount(entries, DeckBoard.main);

int deckRoom(PlayerDeck deck, Iterable<DeckCardEntry> entries) {
  // Constructed has no main-deck maximum. 99 matches the per-card cap.
  if (!deck.isCommanderDeck) return 99;
  final room = formatDeckSize(deck.gameFormat) - deckSize(deck, entries);
  return room < 0 ? 0 : room;
}

/// The main deck and sideboard counts shown on the deck and in the library.
class DeckCountLabel {
  const DeckCountLabel({
    required this.main,
    required this.mainIllegal,
    this.side,
    this.sideIllegal = false,
  });

  final String main;
  final bool mainIllegal;
  final String? side;
  final bool sideIllegal;

  bool get illegal => mainIllegal || sideIllegal;
}

DeckCountLabel deckCountLabel(
  PlayerDeck deck,
  Iterable<DeckCardEntry> entries,
) {
  final main = deckSize(deck, entries);
  final side = boardCount(entries, DeckBoard.sideboard);
  final sideMax = formatSideboardSize(deck.gameFormat);
  if (deck.isCommanderDeck) {
    final cap = formatDeckSize(deck.gameFormat);
    return DeckCountLabel(
      main: '$main/$cap',
      mainIllegal: main > cap,
      side: side > 0 ? '$side' : null,
      sideIllegal: side > sideMax,
    );
  }
  return DeckCountLabel(
    main: '$main',
    mainIllegal: false,
    side: '$side/$sideMax',
    sideIllegal: side > sideMax,
  );
}

bool deckExceedsLimit(PlayerDeck deck, Iterable<DeckCardEntry> entries) {
  final label = deckCountLabel(deck, entries);
  return label.illegal;
}

int sideboardRoom(PlayerDeck deck, Iterable<DeckCardEntry> entries) {
  final room =
      formatSideboardSize(deck.gameFormat) -
      boardCount(entries, DeckBoard.sideboard);
  return room < 0 ? 0 : room;
}

/// How many more copies of [name] can go on [board] without passing a limit.
int addableCopies(
  PlayerDeck deck,
  Iterable<DeckCardEntry> entries,
  String name,
  DeckBoard board,
) {
  final room =
      board == DeckBoard.sideboard
          ? sideboardRoom(deck, entries)
          : deckRoom(deck, entries);
  if (room <= 0) return 0;
  final key = bracketNameKey(name);
  var have = 0;
  for (final entry in entries) {
    if (entry.deckBoard == board && bracketNameKey(entry.name) == key) {
      have += entry.count;
    }
  }
  final byName = copyLimit(name, deck.gameFormat) - have;
  if (byName <= 0) return 0;
  return room < byName ? room : byName;
}

bool _ignoresCopyLimit(String name) {
  const names = {
    'plains',
    'island',
    'swamp',
    'mountain',
    'forest',
    'wastes',
    'snow-covered plains',
    'snow-covered island',
    'snow-covered swamp',
    'snow-covered mountain',
    'snow-covered forest',
    'relentless rats',
    'shadowborn apostle',
    'rat colony',
    'persistent petitioners',
    "dragon's approach",
    'slime against humanity',
    'hare apparent',
    'tempest hawk',
  };
  return names.contains(bracketNameKey(name));
}
