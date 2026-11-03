import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/deck/deck_limits.dart';
import 'package:mgt_life_spark/core/deck/deck_list_text.dart';
import 'package:mgt_life_spark/core/models/deck_card_entry.dart';
import 'package:mgt_life_spark/core/models/player_deck.dart';

PlayerDeck _deck(String format) {
  return PlayerDeck(
    id: 'deck',
    displayName: 'Deck',
    commanderName: 'Commander',
    format: format,
  );
}

DeckCardEntry _card(
  String name,
  int count, {
  DeckBoard board = DeckBoard.main,
}) {
  return DeckCardEntry(
    id: name,
    deckId: 'deck',
    name: name,
    count: count,
    board: board.name,
  );
}

void main() {
  test('a colorless card fits any commander', () {
    expect(outsideCommanderColors(['W', 'U'], const []), isFalse);
    expect(outsideCommanderColors(['W', 'U'], ['U']), isFalse);
    expect(outsideCommanderColors(['W', 'U'], ['R']), isTrue);
    expect(outsideCommanderColors(const [], ['W']), isTrue);
  });

  test('constructed decks can pass 60 and commander decks stop at 100', () {
    final modern = _deck('modern');
    final commander = _deck('commander');
    final big = [_card('Forest', 70)];

    expect(deckRoom(modern, big), 99);
    expect(deckExceedsLimit(modern, big), isFalse);
    expect(addableCopies(modern, big, 'Lightning Bolt', DeckBoard.main), 4);
    expect(
      pastedListIssue(modern, [
        for (var i = 0; i < 61; i++)
          ParsedDeckCard(name: 'Card $i', count: 1, board: DeckBoard.main),
      ]),
      DeckLimitIssue.none,
    );

    expect(deckCountLabel(modern, [_card('Bolt', 4)]).main, '4');
    expect(deckCountLabel(modern, [_card('Bolt', 4)]).side, '0/15');

    final full = [_card('Sol Ring', 100)];
    expect(deckRoom(commander, full), 0);
    expect(deckExceedsLimit(commander, full), isTrue);
    expect(deckCountLabel(commander, const []).main, '1/100');
    expect(
      pastedListIssue(commander, [
        for (var i = 0; i < 100; i++)
          ParsedDeckCard(name: 'Card $i', count: 1, board: DeckBoard.main),
      ]),
      DeckLimitIssue.deckFull,
    );
  });

  test('a constructed sideboard stops at 15', () {
    final modern = _deck('modern');
    final side = [_card('Force of Will', 16, board: DeckBoard.sideboard)];
    expect(deckExceedsLimit(modern, side), isTrue);
    expect(
      addableCopies(modern, side, 'Force of Negation', DeckBoard.sideboard),
      0,
    );
  });
}
