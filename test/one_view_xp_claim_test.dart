import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/progression_service.dart';
import 'package:mgt_life_spark/core/one_view/one_view_xp_claim.dart';

void main() {
  test('build/parse round-trip', () {
    final raw = OneViewXpClaim.build(
      matchId: 'm1',
      playerId: 'p1',
      username: 'Alex',
      won: true,
      playerCount: 4,
      format: 'Commander',
      startingLife: 40,
      commanderName: 'Atraxa',
      opponentNames: const ['Bob', 'Cara'],
      durationSeconds: 1200,
    );
    expect(raw.startsWith(OneViewXpClaim.schemePrefix), isTrue);
    final parsed = OneViewXpClaim.parse(raw);
    expect(parsed, isNotNull);
    expect(parsed!.matchId, 'm1');
    expect(parsed.playerId, 'p1');
    expect(parsed.username, 'Alex');
    expect(parsed.won, isTrue);
    expect(parsed.playerCount, 4);
    expect(parsed.commanderName, 'Atraxa');
    expect(parsed.opponentNames, ['Bob', 'Cara']);
    expect(parsed.claimKey, 'm1:p1');
  });

  test('xpForClaim matches progression constants', () {
    expect(
      OneViewXpClaim.xpForClaim(won: false, isFirstWin: false, playerCount: 4),
      kXpParticipate,
    );
    expect(
      OneViewXpClaim.xpForClaim(won: true, isFirstWin: false, playerCount: 4),
      kXpParticipate + kXpWin,
    );
    expect(
      OneViewXpClaim.xpForClaim(won: true, isFirstWin: true, playerCount: 4),
      kXpParticipate + kXpWin + kXpFirstWin,
    );
    expect(
      OneViewXpClaim.xpForClaim(won: true, isFirstWin: true, playerCount: 1),
      0,
    );
  });

  test('rejects non-claim payloads', () {
    expect(OneViewXpClaim.parse('lifespark-sit:{}'), isNull);
    expect(OneViewXpClaim.parse('garbage'), isNull);
  });
}
