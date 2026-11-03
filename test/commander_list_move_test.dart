import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/deck/commander_list_move.dart';

void main() {
  test('a deck card becomes the commander and the old one returns', () {
    final move = planCommanderListMove(
      oldCommander: 'Atraxa, Praetors\' Voice',
      newCommander: 'Lathril, Blade of the Elves',
    );
    expect(move.removeFromMain, ['Lathril, Blade of the Elves']);
    expect(move.addToMain, ['Atraxa, Praetors\' Voice']);
  });

  test('swapping commander and partner does not touch the list', () {
    final move = planCommanderListMove(
      oldCommander: 'Tymna the Weaver',
      oldPartner: 'Kamahl, Heart of Krosa',
      newCommander: 'Kamahl, Heart of Krosa',
      newPartner: 'Tymna the Weaver',
    );
    expect(move.removeFromMain, isEmpty);
    expect(move.addToMain, isEmpty);
  });

  test('clearing a partner puts that card back', () {
    final move = planCommanderListMove(
      oldCommander: 'Tymna the Weaver',
      oldPartner: 'Kamahl, Heart of Krosa',
      newCommander: 'Tymna the Weaver',
    );
    expect(move.removeFromMain, isEmpty);
    expect(move.addToMain, ['Kamahl, Heart of Krosa']);
  });

  test('confirming the same commander changes nothing', () {
    final move = planCommanderListMove(
      oldCommander: 'Atraxa, Praetors\' Voice',
      newCommander: 'atraxa, praetors\' voice',
    );
    expect(move.removeFromMain, isEmpty);
    expect(move.addToMain, isEmpty);
  });
}
