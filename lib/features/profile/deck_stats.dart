import '../../core/deck/deck_list_text.dart';
import '../../core/game/scryfall_service.dart';
import '../../core/models/deck_card_entry.dart';
import '../../core/models/player_deck.dart';
import '../../shared/mana/mana_symbol_assets.dart';

const manaStatLetters = ['W', 'U', 'B', 'R', 'G', 'C'];

/// Mana-value buckets. Index 7 is 7 or more.
const manaValueBucketCount = 8;

class DeckNamedCount {
  const DeckNamedCount(this.label, this.count);

  final String label;
  final int count;
}

class DeckTypeCount {
  const DeckTypeCount(this.group, this.count);

  final DeckCardGroup group;
  final int count;
}

class DeckStats {
  const DeckStats({
    required this.countedCards,
    required this.manaValue,
    required this.manaCost,
    required this.manaProduction,
    required this.cardTypes,
    required this.subtypes,
    required this.tokens,
    required this.landCount,
    required this.averageManaValue,
  });

  final int countedCards;

  /// Lands in the main deck, commander included when it is a land.
  final int landCount;

  /// Average mana value of the nonland cards. Null when the deck has none.
  final double? averageManaValue;

  /// Copies at mana value 0, 1, 2, 3, 4, 5, 6, and 7+. Lands are left out.
  final List<int> manaValue;
  final List<DeckNamedCount> manaCost;
  final List<DeckNamedCount> manaProduction;
  final List<DeckTypeCount> cardTypes;
  final List<DeckNamedCount> subtypes;
  final List<DeckNamedCount> tokens;
}

String deckStatKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Generic numbers add their face value. Each other pip, including hybrid
/// and Phyrexian, adds 1. `{X}` adds nothing.
int manaValueOf(String? cost) {
  var total = 0;
  for (final token in manaCostTokens(cost)) {
    final inner = token.inner.toUpperCase();
    if (inner == 'X' || inner == 'Y' || inner == 'Z') continue;
    final generic = int.tryParse(inner);
    total += generic ?? 1;
  }
  return total;
}

/// Main deck plus the commander and partner. The sideboard is left out.
DeckStats computeDeckStats({
  required PlayerDeck deck,
  required List<DeckCardEntry> entries,
  required Map<String, ScryfallCard> cards,
}) {
  final samples = <({int count, ScryfallCard? card})>[];
  final seen = <String>{};

  void take(String name, int count) {
    final key = deckStatKey(name);
    if (key.isEmpty || count <= 0 || !seen.add(key)) return;
    samples.add((count: count, card: cards[key]));
  }

  for (final entry in entries) {
    if (entry.deckBoard == DeckBoard.sideboard) continue;
    take(entry.name, entry.count);
  }
  if (deck.isCommanderDeck) {
    take(deck.commanderName, 1);
    final partner = deck.partnerCommanderName;
    if (partner != null) take(partner, 1);
  }

  final curve = List<int>.filled(manaValueBucketCount, 0);
  final pips = {for (final letter in manaStatLetters) letter: 0};
  final produced = {for (final letter in manaStatLetters) letter: 0};
  final types = {for (final group in DeckCardGroup.values) group: 0};
  final subtypes = <String, int>{};
  final tokens = <String, int>{};
  var counted = 0;
  var lands = 0;
  var nonlandCopies = 0;
  var nonlandValue = 0;

  for (final sample in samples) {
    counted += sample.count;
    final card = sample.card;
    final group = deckCardGroupForTypeLine(card?.typeLine);
    types[group] = types[group]! + sample.count;

    if (group == DeckCardGroup.land) {
      lands += sample.count;
    } else {
      final value = manaValueOf(card?.manaCost);
      final index = value >= 7 ? 7 : value;
      curve[index] += sample.count;
      nonlandCopies += sample.count;
      nonlandValue += value * sample.count;
    }

    for (final token in manaCostTokens(card?.manaCost)) {
      for (final letter in symbolColors(token.inner)) {
        pips[letter] = pips[letter]! + sample.count;
      }
    }

    for (final letter in manaProductionOf(card).entries) {
      produced[letter.key] =
          produced[letter.key]! + letter.value * sample.count;
    }

    for (final subtype in subtypesOf(card?.typeLine)) {
      subtypes[subtype] = (subtypes[subtype] ?? 0) + sample.count;
    }

    for (final token in card?.tokenNames.toSet() ?? const <String>{}) {
      tokens[token] = (tokens[token] ?? 0) + sample.count;
    }
  }

  return DeckStats(
    countedCards: counted,
    manaValue: curve,
    manaCost: _letters(pips),
    manaProduction: _letters(produced),
    cardTypes: [
      for (final group in DeckCardGroup.values)
        if (types[group]! > 0) DeckTypeCount(group, types[group]!),
    ],
    subtypes: _named(subtypes),
    tokens: _named(tokens),
    landCount: lands,
    averageManaValue: nonlandCopies == 0 ? null : nonlandValue / nonlandCopies,
  );
}

/// Colors inside one mana symbol. `{W/U}` is both white and blue. `{2}` is none.
Set<String> symbolColors(String inner) {
  final up = inner.toUpperCase().trim();
  if (up.isEmpty || int.tryParse(up) != null) return const {};
  if (up == 'X' || up == 'Y' || up == 'Z' || up == 'T' || up == 'Q') {
    return const {};
  }
  final colors = <String>{};
  for (final part in up.split('/')) {
    if (part == 'C') colors.add('C');
    if (part.length == 1 && 'WUBRG'.contains(part)) colors.add(part);
  }
  return colors;
}

/// How many mana symbols of each color this card can add.
///
/// Oracle text is counted when it says "add", so `{C}{C}` is two colorless.
/// Otherwise Scryfall's produced-mana list counts once per color.
Map<String, int> manaProductionOf(ScryfallCard? card) {
  final fromText = _productionFromOracle(card?.oracleText);
  if (fromText.isNotEmpty) return fromText;
  final counts = <String, int>{};
  for (final raw in card?.producedMana ?? const <String>[]) {
    final letter = raw.toUpperCase();
    if (letter.length == 1 && manaStatLetters.contains(letter)) {
      counts[letter] = (counts[letter] ?? 0) + 1;
    }
  }
  return counts;
}

Map<String, int> _productionFromOracle(String? oracle) {
  if (oracle == null || oracle.isEmpty) return const {};
  final counts = <String, int>{};
  for (final sentence in oracle.split(RegExp(r'[.\n]'))) {
    if (!RegExp(r'\badd\b', caseSensitive: false).hasMatch(sentence)) continue;
    for (final match in RegExp(r'\{([^}]+)\}').allMatches(sentence)) {
      for (final letter in symbolColors(match.group(1)!)) {
        counts[letter] = (counts[letter] ?? 0) + 1;
      }
    }
  }
  return counts;
}

List<String> subtypesOf(String? typeLine) {
  if (typeLine == null || typeLine.isEmpty) return const [];
  final found = <String>[];
  final seen = <String>{};
  for (final face in typeLine.split('//')) {
    final trimmed = face.trim();
    final dash = RegExp(r'\s[—–]\s').firstMatch(trimmed);
    if (dash == null) continue;
    final right = trimmed.substring(dash.end);
    for (final word in right.split(RegExp(r'\s+'))) {
      final clean = word.replaceAll(RegExp(r"[^A-Za-z'-]"), '');
      if (clean.isEmpty || !seen.add(clean)) continue;
      found.add(clean);
    }
  }
  return found;
}

List<DeckNamedCount> _letters(Map<String, int> counts) {
  return [
    for (final letter in manaStatLetters)
      if (counts[letter]! > 0) DeckNamedCount(letter, counts[letter]!),
  ];
}

List<DeckNamedCount> _named(Map<String, int> counts) {
  final rows =
      counts.entries
          .map((entry) => DeckNamedCount(entry.key, entry.value))
          .toList();
  rows.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return a.label.compareTo(b.label);
  });
  return rows;
}
