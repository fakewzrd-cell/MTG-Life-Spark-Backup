import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/game_format.dart';
import 'package:mgt_life_spark/core/models/deck_style.dart';
import 'package:mgt_life_spark/core/models/player_deck.dart';
import 'package:mgt_life_spark/features/profile/deck_bracket_filter_sheet.dart';
import 'package:mgt_life_spark/features/profile/decks_manage_screen.dart';
import 'package:mgt_life_spark/l10n/app_localizations.dart';

PlayerDeck _deck({
  required String name,
  GameFormat format = GameFormat.commander,
  String styleId = 'control',
  int? bracket,
}) {
  final deck = PlayerDeck.create(
    displayName: name,
    commanderName: 'Atraxa',
    format: format,
    deckStyleId: styleId,
  );
  deck.chosenBracket = bracket;
  return deck;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('format filter keeps matching decks', () {
    final commander = _deck(name: 'EDH', format: GameFormat.commander);
    final standard = _deck(name: 'Std', format: GameFormat.standard);
    expect(
      deckMatchesLibraryBrowse(
        deck: commander,
        query: '',
        l10n: l10n,
        format: GameFormat.commander,
      ),
      isTrue,
    );
    expect(
      deckMatchesLibraryBrowse(
        deck: standard,
        query: '',
        l10n: l10n,
        format: GameFormat.commander,
      ),
      isFalse,
    );
  });

  test('style filter keeps matching decks', () {
    final stax = _deck(name: 'Stax', styleId: DeckStyle.stax.id);
    final control = _deck(name: 'Control', styleId: DeckStyle.control.id);
    expect(
      deckMatchesLibraryBrowse(
        deck: stax,
        query: '',
        l10n: l10n,
        style: DeckStyle.stax,
      ),
      isTrue,
    );
    expect(
      deckMatchesLibraryBrowse(
        deck: control,
        query: '',
        l10n: l10n,
        style: DeckStyle.stax,
      ),
      isFalse,
    );
  });

  test('bracket filter matches chosen level or unset', () {
    final b3 = _deck(name: 'B3', bracket: 3);
    final unset = _deck(name: 'Open');
    expect(
      deckMatchesLibraryBrowse(deck: b3, query: '', l10n: l10n, bracket: 3),
      isTrue,
    );
    expect(
      deckMatchesLibraryBrowse(deck: unset, query: '', l10n: l10n, bracket: 3),
      isFalse,
    );
    expect(
      deckMatchesLibraryBrowse(
        deck: unset,
        query: '',
        l10n: l10n,
        bracket: kLibraryBracketUnset,
      ),
      isTrue,
    );
    expect(
      deckMatchesLibraryBrowse(
        deck: b3,
        query: '',
        l10n: l10n,
        bracket: kLibraryBracketUnset,
      ),
      isFalse,
    );
  });

  test('style and bracket filters both have to match', () {
    final staxB3 = _deck(name: 'Stax', styleId: DeckStyle.stax.id, bracket: 3);
    expect(
      deckMatchesLibraryBrowse(
        deck: staxB3,
        query: '',
        l10n: l10n,
        style: DeckStyle.stax,
        bracket: 2,
      ),
      isFalse,
    );
    expect(
      deckMatchesLibraryBrowse(
        deck: staxB3,
        query: '',
        l10n: l10n,
        style: DeckStyle.battlecruiser,
        bracket: 3,
      ),
      isFalse,
    );
    expect(
      deckMatchesLibraryBrowse(
        deck: staxB3,
        query: '',
        l10n: l10n,
        style: DeckStyle.stax,
        bracket: 3,
      ),
      isTrue,
    );
  });

  test('text query still applies with filters', () {
    final deck = _deck(name: 'Atraxa Stax', styleId: DeckStyle.stax.id);
    expect(
      deckMatchesLibraryBrowse(
        deck: deck,
        query: 'atraxa',
        l10n: l10n,
        style: DeckStyle.stax,
      ),
      isTrue,
    );
    expect(
      deckMatchesLibraryBrowse(
        deck: deck,
        query: 'kinnan',
        l10n: l10n,
        style: DeckStyle.stax,
      ),
      isFalse,
    );
  });
}
