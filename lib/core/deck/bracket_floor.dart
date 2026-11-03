import 'bracket_names.dart';
import 'commander_bracket_lists.dart';

class BracketCombo {
  const BracketCombo({required this.cards, required this.early});

  final List<String> cards;
  final bool early;
}

/// The calculated floor, plus the cards that caused it.
class BracketAssessment {
  const BracketAssessment({
    required this.floor,
    required this.gameChangers,
    required this.massLandDenial,
    required this.extraTurns,
    required this.combos,
    this.combosUnavailable = false,
  });

  /// 1 means the list only separates Bracket 1 from 2 by choice.
  final int floor;
  final List<String> gameChangers;
  final List<String> massLandDenial;
  final List<String> extraTurns;
  final List<BracketCombo> combos;
  final bool combosUnavailable;

  bool get choosesOneOrTwo => floor <= 2;

  /// Lowest bracket the player may select. Bracket 5 stays available above it.
  int get minimumChoice => floor <= 1 ? 1 : floor;
}

/// One card the floor checks can see. [oracleText] may be null offline.
class BracketCard {
  const BracketCard({required this.name, this.oracleText});

  final String name;
  final String? oracleText;
}

BracketAssessment assessBracket(
  List<BracketCard> cards, {
  List<BracketCombo> combos = const [],
  bool combosUnavailable = false,
}) {
  final seen = <String>{};
  final gameChangers = <String>[];
  final massLandDenial = <String>[];
  final extraTurns = <String>[];

  for (final card in cards) {
    final key = bracketNameKey(card.name);
    if (key.isEmpty || !seen.add(key)) continue;
    if (kGameChangerKeys.contains(key)) gameChangers.add(card.name);
    if (kMassLandDenialKeys.contains(key)) massLandDenial.add(card.name);
    if (kExtraTurnKeys.contains(key) ||
        oracleGrantsExtraTurn(card.oracleText)) {
      extraTurns.add(card.name);
    }
  }

  var floor = 1;
  if (gameChangers.length >= 4) floor = 4;
  if (gameChangers.isNotEmpty && gameChangers.length <= 3 && floor < 3) {
    floor = 3;
  }
  if (massLandDenial.isNotEmpty) floor = 4;
  if (extraTurns.length > 2) floor = 4;
  for (final combo in combos) {
    if (combo.early) {
      floor = 4;
    } else if (floor < 3) {
      floor = 3;
    }
  }

  return BracketAssessment(
    floor: floor,
    gameChangers: gameChangers,
    massLandDenial: massLandDenial,
    extraTurns: extraTurns,
    combos: combos,
    combosUnavailable: combosUnavailable,
  );
}

/// A two-card combo is early when Spellbook marks it Ruthless or it needs
/// six mana or less, so it can happen in the first six turns.
bool comboIsEarly({
  required String? bracketTag,
  required int? manaValueNeeded,
}) {
  if (bracketTag == 'R') return true;
  if (manaValueNeeded != null && manaValueNeeded <= 6) return true;
  return false;
}
