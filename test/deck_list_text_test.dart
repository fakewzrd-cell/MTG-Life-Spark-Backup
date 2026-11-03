import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/deck/deck_list_text.dart';
import 'package:mgt_life_spark/core/models/deck_card_entry.dart';

void main() {
  group('parseDeckList', () {
    test(
      'reads counts, drops the commander, and keeps a Sideboard heading on the main deck',
      () {
        final parsed = parseDeckList(
          '''
1 Atraxa, Praetors' Voice

1 Sol Ring (cmr) 325
2x Command Tower

Sideboard
1 Rest in Peace
not a card
''',
          commanderName: "Atraxa, Praetors' Voice",
          identifyCommander: true,
        );

        expect(parsed.skippedLines, 1);
        expect(parsed.totalCards, 4);
        expect(
          parsed.cards.map(
            (card) => '${card.count} ${card.name} ${card.board.name}',
          ),
          ['2 Command Tower main', '1 Rest in Peace main', '1 Sol Ring main'],
        );
      },
    );

    test('only a Sideboard heading starts the sideboard', () {
      final gap = parseDeckList('''
4 Lightning Bolt

3 Pyroblast
''', identifyCommander: false);
      expect(gap.cards.every((card) => card.board == DeckBoard.main), isTrue);

      const source = '''
4 Lightning Bolt

Sideboard
3 Pyroblast''';
      final parsed = parseDeckList(source, identifyCommander: false);
      final text = exportDeckList(
        entries: [
          for (final card in parsed.cards)
            DeckCardEntry(
              id: card.name,
              deckId: 'deck',
              name: card.name,
              count: card.count,
              board: card.board.name,
            ),
        ],
        identifyCommander: false,
      );
      final again = parseDeckList(text, identifyCommander: false);
      expect(
        again.cards.map(
          (card) => '${card.count} ${card.name} ${card.board.name}',
        ),
        ['4 Lightning Bolt main', '3 Pyroblast sideboard'],
      );
    });

    test(
      'a commander list keeps cards after a blank line in the main deck',
      () {
        final parsed = parseDeckList(
          '''
1 Atraxa, Praetors' Voice

1 Sol Ring

1 Lightning Greaves
''',
          commanderName: "Atraxa, Praetors' Voice",
          identifyCommander: true,
        );
        expect(
          parsed.cards.map(
            (card) => '${card.count} ${card.name} ${card.board.name}',
          ),
          ['1 Lightning Greaves main', '1 Sol Ring main'],
        );
      },
    );

    test('constructed lists keep the cover card in the main deck', () {
      final parsed = parseDeckList(
        '''
4 Lightning Bolt

Sideboard
2 Smash to Smithereens
''',
        commanderName: 'Lightning Bolt',
        identifyCommander: false,
      );
      expect(parsed.cards.map((card) => card.name), [
        'Lightning Bolt',
        'Smash to Smithereens',
      ]);
      expect(parsed.cards.last.board, DeckBoard.sideboard);
    });
  });

  group('deckCardGroupForTypeLine', () {
    test('lands win over artifacts', () {
      expect(deckCardGroupForTypeLine('Artifact Land'), DeckCardGroup.land);
      expect(
        deckCardGroupForTypeLine('Legendary Creature — Phyrexian Horror'),
        DeckCardGroup.creature,
      );
      expect(deckCardGroupForTypeLine(null), DeckCardGroup.other);
    });
  });
}
