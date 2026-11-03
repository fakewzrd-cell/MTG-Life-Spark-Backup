import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/deck/bracket_floor.dart';

void main() {
  test('no flagged cards leaves the floor at 1 or 2', () {
    final result = assessBracket(const [
      BracketCard(name: 'Sol Ring'),
      BracketCard(name: 'Command Tower'),
    ]);
    expect(result.choosesOneOrTwo, isTrue);
    expect(result.floor, 1);
  });

  test('one to three Game Changers set the floor at 3', () {
    final result = assessBracket(const [
      BracketCard(name: 'Rhystic Study'),
      BracketCard(name: 'Smothering Tithe'),
    ]);
    expect(result.floor, 3);
    expect(result.gameChangers, ['Rhystic Study', 'Smothering Tithe']);
  });

  test('four Game Changers, land denial, or many extra turns set 4', () {
    expect(
      assessBracket(const [
        BracketCard(name: 'Rhystic Study'),
        BracketCard(name: 'Smothering Tithe'),
        BracketCard(name: 'Cyclonic Rift'),
        BracketCard(name: 'The One Ring'),
      ]).floor,
      4,
    );
    expect(assessBracket(const [BracketCard(name: 'Armageddon')]).floor, 4);
    expect(
      assessBracket(const [
        BracketCard(name: 'Time Warp'),
        BracketCard(name: 'Capture of Jingzhou'),
        BracketCard(name: 'Walk the Aeons'),
      ]).floor,
      4,
    );
  });

  test('one or two extra turns do not raise the floor', () {
    expect(
      assessBracket(const [
        BracketCard(name: 'Time Warp'),
        BracketCard(name: 'Temporal Manipulation'),
      ]).choosesOneOrTwo,
      isTrue,
    );
  });

  test('a two-card combo sets 3, and an early one sets 4', () {
    expect(
      assessBracket(
        const [BracketCard(name: 'Sol Ring')],
        combos: const [
          BracketCombo(cards: ['A', 'B'], early: false),
        ],
      ).floor,
      3,
    );
    expect(
      assessBracket(
        const [BracketCard(name: 'Sol Ring')],
        combos: const [
          BracketCombo(
            cards: ['Thassa\'s Oracle', 'Demonic Consultation'],
            early: true,
          ),
        ],
      ).floor,
      4,
    );
  });

  test('oracle text counts an extra turn that is not on the stored list', () {
    final result = assessBracket(const [
      BracketCard(
        name: 'Some New Spell',
        oracleText: 'Take an extra turn after this one.',
      ),
    ]);
    expect(result.extraTurns, ['Some New Spell']);
  });
}
