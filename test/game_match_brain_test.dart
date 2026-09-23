import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/alliance.dart';
import 'package:mgt_life_spark/core/game/game_phase.dart';
import 'package:mgt_life_spark/core/game/game_providers.dart';
import 'package:mgt_life_spark/core/game/game_state.dart';
import 'package:mgt_life_spark/core/game/game_state_notifier.dart';
import 'package:mgt_life_spark/core/game/player_game_state.dart';
import 'package:mgt_life_spark/core/game/stack_item.dart';
import 'package:mgt_life_spark/core/network/session_providers.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';

import 'support/fake_ble_service.dart';
import 'support/test_profile_repository.dart';

PlayerGameState _player(String id, {int life = 40, int poison = 0}) {
  return PlayerGameState(
    playerId: id,
    username: id,
    playerColor: Colors.blue,
    life: life,
    poison: poison,
  );
}

GameState _match({
  bool isHost = true,
  String localId = 'alice',
  List<PlayerGameState>? players,
  bool teamsEnabled = false,
  bool planechaseEnabled = false,
  bool archenemyEnabled = false,
  bool bountyEnabled = false,
  bool autoKoFromLife = true,
}) {
  final ps = players ?? [_player('alice'), _player('bob')];
  return GameState(
    players: ps,
    turnOrder: ps.map((p) => p.playerId).toList(),
    localPlayerId: localId,
    isHost: isHost,
    gameStartTime: DateTime(2026, 1, 1),
    autoKoFromCommanderDamage: true,
    commanderDamageReducesLife: true,
    autoKoFromLife: autoKoFromLife,
    teamsEnabled: teamsEnabled,
    planechaseEnabled: planechaseEnabled,
    archenemyEnabled: archenemyEnabled,
    bountyEnabled: bountyEnabled,
  );
}

({ProviderContainer container, GameStateNotifier notifier, TestProfileRepository profile})
    _open(GameState game) {
  final ble = FakeBleService();
  final profile = TestProfileRepository();
  final container = ProviderContainer(
    overrides: [
      sessionServiceProvider.overrideWith((ref) => ble),
      profileRepositoryProvider.overrideWithValue(profile),
    ],
  );
  final notifier = container.read(gameProvider.notifier);
  notifier.setGameStateForTest(game);
  return (container: container, notifier: notifier, profile: profile);
}

void main() {
  group('match brain — life, turns, and wins', () {
    test('life change undoes and a lethal drop ends the match', () {
      final session = _open(_match());
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.adjustLife('bob', -5);
      expect(session.container.read(gameProvider).playerById('bob')!.life, 35);
      n.undo('bob');
      expect(session.container.read(gameProvider).playerById('bob')!.life, 40);

      n.adjustLife('bob', -40);
      final game = session.container.read(gameProvider);
      expect(game.playerById('bob')!.isEliminated, isTrue);
      expect(game.playerById('bob')!.eliminationReason, 'life');
      expect(game.gameOver, isTrue);
      expect(game.winnerPlayerId, 'alice');
    });

    test('poison and commander damage knock a player out', () {
      final session = _open(_match(autoKoFromLife: false));
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.adjustCounter('bob', 'poison', 10);
      expect(
        session.container.read(gameProvider).playerById('bob')!.eliminationReason,
        'poison',
      );

      final again = _open(_match());
      addTearDown(again.container.dispose);
      again.notifier.applyCommanderDamage(
        fromPlayerId: 'alice',
        partnerIndex: 0,
        toPlayerId: 'bob',
        delta: 21,
      );
      final game = again.container.read(gameProvider);
      expect(game.playerById('bob')!.eliminationReason, 'commanderDamage');
      expect(game.playerById('bob')!.life, 19);
      expect(again.profile.commanderKillIncrements, 1);
    });

    test('counters, proliferate, commander casts, and undo stay consistent', () {
      final session = _open(_match(autoKoFromLife: false));
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.adjustCounter('alice', 'energy', 2);
      n.setGameplayDialAbsolute('alice', 'experience', 4);
      expect(n.registerCustomGameplayDial('alice', 'storm', 'Storm'), isTrue);
      n.setGameplayDialAbsolute('alice', 'storm', 1);
      n.proliferate('alice');

      final alice = session.container.read(gameProvider).playerById('alice')!;
      expect(alice.energy, 3);
      expect(alice.experience, 5);
      expect(alice.extraDials['storm'], 2);

      n.castCommanderFromZone('alice');
      n.castCommanderFromZone('alice');
      n.uncastCommanderFromZone('alice');
      expect(
        session.container.read(gameProvider).playerById('alice')!.commanderCastCount,
        1,
      );
      n.undo('alice');
      expect(
        session.container.read(gameProvider).playerById('alice')!.commanderCastCount,
        2,
      );
    });

    test('host passes the turn, wraps the round, and steps phases', () {
      final session = _open(_match());
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.setPhase(GamePhase.combat);
      n.previousPhase();
      expect(
        session.container.read(gameProvider).currentPhase,
        GamePhase.preCombatMain,
      );
      n.advancePhase();
      n.advancePhase();
      n.advancePhase();
      final afterPass = session.container.read(gameProvider);
      expect(afterPass.activePlayerId, 'bob');
      expect(afterPass.currentPhase, GamePhase.untap);
      expect(afterPass.roundNumber, 1);

      n.endTurn();
      expect(session.container.read(gameProvider).activePlayerId, 'alice');
      expect(session.container.read(gameProvider).roundNumber, 2);
    });

    test('priority and timeout block turn and life changes', () {
      final session = _open(_match());
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.holdPriority('alice');
      n.endTurn();
      expect(session.container.read(gameProvider).activePlayerId, 'alice');
      n.releasePriority('alice');

      n.startTimeout(durationSeconds: null);
      n.adjustLife('alice', -1);
      expect(session.container.read(gameProvider).playerById('alice')!.life, 40);
      n.endTimeout();
      n.adjustLife('alice', -1);
      expect(session.container.read(gameProvider).playerById('alice')!.life, 39);
    });

    test('end turn skips an eliminated seat', () {
      final session = _open(
        _match(
          players: [
            _player('alice'),
            _player('bob', life: 1),
            _player('cara'),
          ],
        ),
      );
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.adjustLife('bob', -1);
      n.endTurn();
      expect(session.container.read(gameProvider).activePlayerId, 'cara');
    });

    test('host reorders seats, assigns teams, and tracks table markers', () {
      final session = _open(_match(teamsEnabled: true));
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.hostSetTurnOrder(['bob', 'alice']);
      expect(session.container.read(gameProvider).turnOrder, ['bob', 'alice']);
      expect(session.container.read(gameProvider).activePlayerId, 'alice');

      n.assignTeam('alice', 1);
      n.assignTeam('bob', 1);
      n.setMonarch('alice');
      n.setInitiative('bob');
      n.setDayNight(DayNightState.night);

      final game = session.container.read(gameProvider);
      expect(game.monarchPlayerId, 'alice');
      expect(game.initiativePlayerId, 'bob');
      expect(game.dayNight, DayNightState.night);
      expect(game.teamAssignments['alice'], 1);
    });

    test('variant decks advance and wrap', () {
      final session = _open(
        _match(
          planechaseEnabled: true,
          archenemyEnabled: true,
          bountyEnabled: true,
        ),
      );
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.advancePlanar(2);
      n.advancePlanar(2);
      n.setPlanarIndex(0);
      n.advanceScheme(3);
      n.advanceBounty(2);
      n.advanceBounty(2);

      final game = session.container.read(gameProvider);
      expect(game.currentPlanarIndex, 0);
      expect(game.currentSchemeIndex, 1);
      expect(game.currentBountyIndex, 0);
    });

    test('alliances form, reveal, and break', () {
      final session = _open(_match());
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.proposeAlliance('alice', 'bob', AllianceDuration.endOfTurn);
      n.respondToAlliance('bob', true);
      expect(session.container.read(gameProvider).alliances, hasLength(1));

      n.revealAlliance('alice');
      expect(
        session.container.read(gameProvider).alliances.single.isRevealed,
        isTrue,
      );
      n.breakAlliance('bob');
      expect(session.container.read(gameProvider).alliances, isEmpty);
    });

    test('stack items can be added, resolved, and cleared', () {
      final session = _open(_match());
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.addStackItem(name: 'Counterspell');
      final item = session.container.read(gameProvider).stackItems.single;
      n.setStackItemStatus(item.id, StackItemStatus.resolved);
      expect(
        session.container.read(gameProvider).stackItems.single.status,
        StackItemStatus.resolved,
      );
      n.clearAllStackItems();
      expect(session.container.read(gameProvider).stackItems, isEmpty);
    });

    test('a declined alliance and a commander-damage undo restore the table', () {
      final session = _open(_match());
      addTearDown(session.container.dispose);
      final n = session.notifier;

      n.proposeAlliance('alice', 'bob', AllianceDuration.manual);
      n.respondToAlliance('bob', false);
      expect(session.container.read(gameProvider).alliances, isEmpty);
      expect(session.container.read(gameProvider).pendingProposals, isEmpty);

      n.applyCommanderDamage(
        fromPlayerId: 'alice',
        partnerIndex: 1,
        toPlayerId: 'bob',
        delta: 3,
      );
      expect(session.container.read(gameProvider).playerById('bob')!.life, 37);
      n.undo('bob');
      final bob = session.container.read(gameProvider).playerById('bob')!;
      expect(bob.life, 40);
      expect(bob.commanderDamage['alice']?[1] ?? 0, 0);
    });

    test('preset dials can be shown and hidden on the strip', () {
      final session = _open(_match());
      addTearDown(session.container.dispose);
      final n = session.notifier;

      expect(n.addGameplayDialToStrip('alice', 'treasure'), isTrue);
      expect(
        session.container
            .read(gameProvider)
            .playerById('alice')!
            .visibleGameplayDials,
        contains('treasure'),
      );
      n.removeGameplayDialFromStrip('alice', 'treasure');
      expect(
        session.container
            .read(gameProvider)
            .playerById('alice')!
            .visibleGameplayDials,
        isNot(contains('treasure')),
      );
    });

    test('a guest cannot change another player life', () {
      final session = _open(_match(isHost: false, localId: 'alice'));
      addTearDown(session.container.dispose);
      session.notifier.adjustLife('bob', -5);
      expect(session.container.read(gameProvider).playerById('bob')!.life, 40);
      session.notifier.adjustLife('alice', -2);
      expect(session.container.read(gameProvider).playerById('alice')!.life, 38);
    });
  });
}
