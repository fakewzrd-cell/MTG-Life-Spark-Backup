import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/lobby_state.dart';
import 'package:mgt_life_spark/core/one_view/one_view_match_recording.dart';
import 'package:mgt_life_spark/core/one_view/one_view_state.dart';

void main() {
  test('recording snapshots include claimed seats only', () {
    final state = OneViewState(
      config: const LobbyConfig(startingLife: 40, maxPlayers: 3),
      started: true,
      startTime: DateTime(2026, 1, 1),
      seats: [
        const OneViewSeat(
          index: 0,
          playerId: 'local-1',
          username: 'Host',
          life: 38,
          seatColor: Colors.red,
          selectedDeckId: 'deck-1',
          commanderName: 'Atraxa',
        ),
        const OneViewSeat(
          index: 1,
          playerId: 'guest-1',
          username: 'Bob',
          isGuest: true,
          life: 40,
          seatColor: Colors.blue,
        ),
        OneViewSeat.empty(index: 2, startingLife: 40),
      ],
    );

    final snap = oneViewRecordingSnapshots(
      oneView: state,
      localPlayerId: 'local-1',
    );
    expect(snap, isNotNull);
    expect(snap!.game.players, hasLength(2));
    expect(snap.game.localPlayerId, 'local-1');
    expect(snap.game.localPlayer?.selectedDeckId, 'deck-1');
    expect(oneViewCanAwardProgression(snap.game), isTrue);
  });

  test('no local seat means no progression eligibility', () {
    final state = OneViewState(
      started: true,
      seats: [
        const OneViewSeat(
          index: 0,
          playerId: 'guest-1',
          username: 'Bob',
          isGuest: true,
          life: 40,
          seatColor: Colors.blue,
        ),
      ],
    );
    final snap = oneViewRecordingSnapshots(
      oneView: state,
      localPlayerId: 'local-1',
    );
    expect(snap, isNotNull);
    expect(snap!.game.localPlayerId, isEmpty);
    expect(oneViewCanAwardProgression(snap.game), isFalse);
  });

  test('winner picker sets winnerPlayerId when seated', () {
    final state = OneViewState(
      started: true,
      seats: [
        const OneViewSeat(
          index: 0,
          playerId: 'local-1',
          username: 'Host',
          life: 40,
          seatColor: Colors.red,
        ),
        const OneViewSeat(
          index: 1,
          playerId: 'friend-1',
          username: 'Alex',
          life: 40,
          seatColor: Colors.blue,
        ),
      ],
    );
    final snap = oneViewRecordingSnapshots(
      oneView: state,
      localPlayerId: 'local-1',
      winnerPlayerId: 'friend-1',
    );
    expect(snap!.game.winnerPlayerId, 'friend-1');
    expect(snap.game.gameOver, isTrue);
  });

  test('xp claim seats exclude guests and local profile', () {
    final state = OneViewState(
      started: true,
      seats: [
        const OneViewSeat(
          index: 0,
          playerId: 'local-1',
          username: 'Host',
          life: 40,
          seatColor: Colors.red,
        ),
        const OneViewSeat(
          index: 1,
          playerId: 'friend-1',
          username: 'Alex',
          life: 40,
          seatColor: Colors.blue,
        ),
        const OneViewSeat(
          index: 2,
          playerId: 'guest-1',
          username: 'Bob',
          isGuest: true,
          life: 40,
          seatColor: Colors.green,
        ),
      ],
    );
    final seats = oneViewXpClaimSeats(
      oneView: state,
      localPlayerId: 'local-1',
    );
    expect(seats, hasLength(1));
    expect(seats.single.playerId, 'friend-1');
  });
}
