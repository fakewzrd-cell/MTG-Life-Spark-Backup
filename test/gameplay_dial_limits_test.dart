import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/gameplay_dial_ids.dart';
import 'package:mgt_life_spark/core/game/player_game_state.dart';

PlayerGameState _player({
  Map<String, String> customDialLabels = const {},
  List<String> visibleGameplayDials = const [],
}) {
  return PlayerGameState(
    playerId: 'p1',
    username: 'Test',
    playerColor: Colors.red,
    life: 40,
    customDialLabels: customDialLabels,
    visibleGameplayDials: visibleGameplayDials,
  );
}

void main() {
  group('GameplayDialLimits', () {
    test('allows a custom dial below the cap', () {
      final p = _player(
        customDialLabels: {'a': 'A', 'b': 'B', 'c': 'C'},
        visibleGameplayDials: ['a', 'b', 'c'],
      );

      expect(GameplayDialLimits.canAddCustomDial(p), isTrue);
      expect(
        GameplayDialLimits.canRegisterCustomDial(
          p,
          isNewKey: true,
          addsToStrip: true,
        ),
        isTrue,
      );
    });

    test('blocks a 9th new custom dial', () {
      final p = _player(
        customDialLabels: {
          for (var i = 0; i < GameplayDialIds.maxCustomDials; i++) 'c$i': 'C$i',
        },
        visibleGameplayDials: [
          for (var i = 0; i < GameplayDialIds.maxCustomDials; i++) 'c$i',
        ],
      );

      expect(
        GameplayDialLimits.customDialCount(p),
        GameplayDialIds.maxCustomDials,
      );
      expect(GameplayDialLimits.canAddCustomDial(p), isFalse);
      expect(
        GameplayDialLimits.canRegisterCustomDial(
          p,
          isNewKey: true,
          addsToStrip: true,
        ),
        isFalse,
      );
    });

    test('blocks new custom dial when strip is full even below custom max', () {
      final p = _player(
        customDialLabels: {'custom1': 'Mine'},
        visibleGameplayDials: [
          'poison',
          'energy',
          'experience',
          'rad',
          'blood',
          'clue',
          'map',
          'treasure',
        ],
      );

      expect(GameplayDialLimits.customDialCount(p), 1);
      expect(
        GameplayDialLimits.stripDialCount(p),
        GameplayDialIds.maxStripDials,
      );
      expect(GameplayDialLimits.canAddCustomDial(p), isFalse);
    });

    test('allows relabeling an existing custom dial at the limit', () {
      final p = _player(
        customDialLabels: {
          for (var i = 0; i < GameplayDialIds.maxCustomDials; i++) 'c$i': 'C$i',
        },
        visibleGameplayDials: [
          for (var i = 0; i < GameplayDialIds.maxCustomDials; i++) 'c$i',
        ],
      );

      expect(
        GameplayDialLimits.canRegisterCustomDial(
          p,
          isNewKey: false,
          addsToStrip: false,
        ),
        isTrue,
      );
    });

    test('allows a new custom dial after dropping below the limit', () {
      final p = _player(
        customDialLabels: {'a': 'A', 'b': 'B', 'c': 'C'},
        visibleGameplayDials: ['a', 'b', 'c'],
      );

      expect(GameplayDialLimits.canAddCustomDial(p), isTrue);
    });

    test('hides add tile when the custom-counter cap is showing', () {
      final p = _player(
        customDialLabels: {
          for (var i = 0; i < GameplayDialIds.maxCustomDials; i++) 'c$i': 'C$i',
        },
        visibleGameplayDials: [
          for (var i = 0; i < GameplayDialIds.maxCustomDials; i++) 'c$i',
        ],
      );

      expect(
        GameplayDialLimits.visibleCustomDialCount(p),
        GameplayDialIds.maxCustomDials,
      );
      expect(
        GameplayDialLimits.showAddCounterTile(p, isEliminated: false),
        isFalse,
      );
    });

    test('shows add tile again after removing a custom counter', () {
      final p = _player(
        customDialLabels: {'a': 'A', 'b': 'B', 'c': 'C'},
        visibleGameplayDials: ['a', 'b', 'c'],
      );

      expect(
        GameplayDialLimits.showAddCounterTile(p, isEliminated: false),
        isTrue,
      );
    });
  });
}
