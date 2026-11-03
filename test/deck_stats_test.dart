import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/scryfall_service.dart';
import 'package:mgt_life_spark/core/models/deck_card_entry.dart';
import 'package:mgt_life_spark/core/models/player_deck.dart';
import 'package:mgt_life_spark/features/profile/deck_stats.dart';

void main() {
  test('mana value ignores X and counts hybrid as one', () {
    expect(manaValueOf('{2}{W}{U}'), 4);
    expect(manaValueOf('{X}{R}'), 1);
    expect(manaValueOf('{W/U}'), 1);
  });

  test('stats follow the main deck and leave the sideboard out', () {
    final deck = PlayerDeck(
      id: 'deck',
      displayName: 'Elves',
      commanderName: 'Lathril, Blade of the Elves',
      format: 'commander',
    );
    final cards = {
      'lathril, blade of the elves': ScryfallCard(
        name: 'Lathril, Blade of the Elves',
        manaCost: '{2}{B}{G}',
        typeLine: 'Legendary Creature — Elf Noble',
        oracleText: 'Create a 1/1 green Elf token.',
        tokenNames: const ['Elf'],
      ),
      'sol ring': ScryfallCard(
        name: 'Sol Ring',
        manaCost: '{1}',
        typeLine: 'Artifact',
        oracleText: '{T}: Add {C}{C}.',
        producedMana: const ['C'],
      ),
      'forest': ScryfallCard(
        name: 'Forest',
        typeLine: 'Basic Land — Forest',
        oracleText: '{T}: Add {G}.',
        producedMana: const ['G'],
      ),
      'counterspell': ScryfallCard(
        name: 'Counterspell',
        manaCost: '{U}{U}',
        typeLine: 'Instant',
      ),
    };

    final stats = computeDeckStats(
      deck: deck,
      entries: [
        DeckCardEntry(
          id: '1',
          deckId: 'deck',
          name: 'Sol Ring',
          count: 1,
          board: DeckBoard.main.name,
        ),
        DeckCardEntry(
          id: '2',
          deckId: 'deck',
          name: 'Forest',
          count: 2,
          board: DeckBoard.main.name,
        ),
        DeckCardEntry(
          id: '3',
          deckId: 'deck',
          name: 'Counterspell',
          count: 1,
          board: DeckBoard.sideboard.name,
        ),
      ],
      cards: cards,
    );

    expect(stats.countedCards, 4);
    expect(stats.manaValue[1], 1);
    expect(stats.manaValue[4], 1);
    expect(stats.manaValue[0], 0);
    expect(stats.manaCost.map((row) => row.label), ['B', 'G']);
    expect(stats.manaProduction.map((row) => '${row.label}:${row.count}'), [
      'G:2',
      'C:2',
    ]);
    expect(stats.subtypes.map((row) => row.label), ['Forest', 'Elf', 'Noble']);
    expect(stats.tokens.single.label, 'Elf');
    expect(stats.landCount, 2);
    expect(stats.averageManaValue, 2.5);
    expect(stats.cardTypes.map((row) => row.group.name), [
      'creature',
      'artifact',
      'land',
    ]);
  });
}
