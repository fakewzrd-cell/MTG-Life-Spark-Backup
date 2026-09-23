import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/game_state.dart';
import 'package:mgt_life_spark/core/game/lobby_state.dart';
import 'package:mgt_life_spark/core/game/player_game_state.dart';
import 'package:mgt_life_spark/core/game/progression_service.dart';
import 'package:mgt_life_spark/core/models/game_feedback.dart';
import 'package:mgt_life_spark/core/models/match_record.dart';
import 'package:mgt_life_spark/core/models/player_deck.dart';
import 'package:mgt_life_spark/core/models/player_profile.dart';
import 'package:mgt_life_spark/core/persistence/feedback_repository.dart';
import 'package:mgt_life_spark/core/persistence/match_repository.dart';

import 'support/test_deck_repository.dart';
import 'support/test_profile_repository.dart';

class _Profile extends TestProfileRepository {
  int likesXp = 0;

  @override
  Future<void> recordMatchResult({
    required String commanderName,
    required bool won,
    required int xpGained,
  }) async {
    final p = profile!;
    p.xp += xpGained;
    p.totalGamesPlayed += 1;
    if (won) {
      p.totalWins += 1;
    } else {
      p.totalLosses += 1;
    }
    p.level = 1 + p.xp ~/ 200;
  }

  @override
  Future<void> addXp(int amount) async {
    likesXp += amount;
    profile!.xp += amount;
  }

  @override
  Future<void> recomputeSocialStatsFromFeedback(
    FeedbackRepository feedbackRepo,
    String localPlayerId,
  ) async {}
}

class _Matches extends MatchRepository {
  final saved = <String, MatchRecord>{};

  @override
  bool hasMatch(String matchId) => saved.containsKey(matchId);

  @override
  Future<void> saveMatch(MatchRecord record) async {
    saved[record.matchId] = record;
  }
}

class _Feedback extends FeedbackRepository {
  final items = <GameFeedback>[];

  @override
  Future<void> saveFeedback(GameFeedback feedback) async {
    items.add(feedback);
  }

  @override
  Iterable<GameFeedback> allFeedback() => items;
}

class _Decks extends TestDeckRepository {
  _Decks({super.decks});

  int recorded = 0;
  int saves = 0;

  @override
  Future<void> recordMatchResult(String deckId, bool won) async {
    recorded++;
    final deck = getById(deckId);
    if (deck == null) return;
    deck.gamesPlayed += 1;
    if (won) {
      deck.wins += 1;
    } else {
      deck.losses += 1;
    }
  }

  @override
  Future<void> save(PlayerDeck deck) async {
    saves++;
  }
}

PlayerGameState _seat(
  String id, {
  String? deckId,
  String? commanderImageUrl,
  String? eliminationReason,
}) {
  return PlayerGameState(
    playerId: id,
    username: id,
    playerColor: Colors.blue,
    life: id == 'bob' ? 0 : 40,
    isEliminated: id == 'bob',
    eliminationReason: eliminationReason,
    commanderName: 'Atraxa',
    commanderImageUrl: commanderImageUrl,
    selectedDeckId: deckId,
  );
}

GameState _game({
  required List<PlayerGameState> players,
  String? winner,
  String localId = 'alice',
}) {
  return GameState(
    players: players,
    turnOrder: players.map((p) => p.playerId).toList(),
    localPlayerId: localId,
    winnerPlayerId: winner,
    gameStartTime: DateTime.now().subtract(const Duration(minutes: 12)),
  );
}

void main() {
  test('a missing profile records nothing', () async {
    final service = ProgressionService(
      profileRepo: _Profile(),
      matchRepo: _Matches(),
      feedbackRepo: _Feedback(),
      deckRepo: _Decks(),
    );

    final result = await service.recordMatch(
      finalState: _game(players: [_seat('alice'), _seat('bob')], winner: 'alice'),
      lobbyState: const LobbyState(),
      startTime: DateTime.now(),
    );

    expect(result.awardsProgression, isFalse);
    expect(result.xpGained, 0);
  });

  test('a first win awards participation, win, and first-win XP', () async {
    final profile = _Profile()
      ..profile = PlayerProfile(username: 'alice', playerId: 'alice', level: 1);
    final matches = _Matches();
    final decks = _Decks(
      decks: [
        PlayerDeck(
          id: 'edh',
          displayName: 'EDH',
          commanderName: 'Atraxa',
          format: 'commander',
        ),
      ],
    );
    final service = ProgressionService(
      profileRepo: profile,
      matchRepo: matches,
      feedbackRepo: _Feedback(),
      deckRepo: decks,
    );

    final result = await service.recordMatch(
      finalState: _game(
        players: [
          _seat('alice', deckId: 'edh', commanderImageUrl: 'https://img/a.jpg'),
          _seat('bob'),
        ],
        winner: 'alice',
      ),
      lobbyState: const LobbyState(matchLabel: 'Friday'),
      startTime: DateTime.now().subtract(const Duration(minutes: 12)),
      matchId: 'm1',
    );

    expect(result.xpGained, kXpParticipate + kXpWin + kXpFirstWin);
    expect(result.leveledUp, isTrue);
    expect(matches.saved['m1']!.result, 'win');
    expect(matches.saved['m1']!.labelSnapshot, 'Friday');
    expect(decks.recorded, 1);
    expect(decks.getById('edh')!.wins, 1);
    expect(decks.getById('edh')!.commanderImageUrl, 'https://img/a.jpg');
    expect(profile.profile!.totalWins, 1);

    final again = await service.recordMatch(
      finalState: _game(players: [_seat('alice'), _seat('bob')], winner: 'bob'),
      lobbyState: const LobbyState(),
      startTime: DateTime.now(),
      matchId: 'm1',
    );
    expect(again.xpGained, 0);
  });

  test('a concede and a later win use the smaller XP amounts', () async {
    final profile = _Profile()
      ..profile = PlayerProfile(
        username: 'alice',
        playerId: 'alice',
        totalWins: 2,
      );
    final matches = _Matches();
    final decks = _Decks(
      decks: [
        PlayerDeck(
          id: 'std',
          displayName: 'Standard',
          commanderName: 'Sheoldred',
          format: 'standard',
        ),
      ],
    );
    final service = ProgressionService(
      profileRepo: profile,
      matchRepo: matches,
      feedbackRepo: _Feedback(),
      deckRepo: decks,
    );

    final conceded = await service.recordMatch(
      finalState: _game(
        players: [
          _seat('alice', deckId: 'std', eliminationReason: 'concede'),
          _seat('bob'),
        ],
        winner: 'bob',
      ),
      lobbyState: const LobbyState(),
      startTime: DateTime.now(),
      matchId: 'loss',
    );
    expect(conceded.xpGained, kXpParticipate);
    expect(matches.saved['loss']!.result, 'concede');
    expect(decks.recorded, 0);

    final won = await service.recordMatch(
      finalState: _game(
        players: [_seat('alice', deckId: 'edh'), _seat('bob')],
        winner: 'alice',
      ),
      lobbyState: const LobbyState(),
      startTime: DateTime.now(),
      matchId: 'win-2',
    );
    expect(won.xpGained, kXpParticipate + kXpWin);
  });

  test('solo play skips XP but still fills missing deck art', () async {
    final decks = _Decks(
      decks: [
        PlayerDeck(
          id: 'edh',
          displayName: 'EDH',
          commanderName: 'Atraxa',
        ),
      ],
    );
    final service = ProgressionService(
      profileRepo: _Profile()
        ..profile = PlayerProfile(username: 'alice', playerId: 'alice'),
      matchRepo: _Matches(),
      feedbackRepo: _Feedback(),
      deckRepo: decks,
    );

    final result = await service.recordMatch(
      finalState: _game(
        players: [
          _seat('alice', deckId: 'edh', commanderImageUrl: 'https://img/solo.jpg'),
        ],
      ),
      lobbyState: const LobbyState(),
      startTime: DateTime.now(),
    );

    expect(result.awardsProgression, isFalse);
    expect(result.xpGained, 0);
    expect(decks.getById('edh')!.commanderImageUrl, 'https://img/solo.jpg');
    expect(decks.saves, 1);
  });

  test('likes from a ballot add giver XP', () async {
    final profile = _Profile()
      ..profile = PlayerProfile(username: 'alice', playerId: 'alice');
    final feedback = _Feedback();
    final service = ProgressionService(
      profileRepo: profile,
      matchRepo: _Matches(),
      feedbackRepo: feedback,
      deckRepo: _Decks(),
    );

    await service.saveFeedback(
      const GameFeedback(
        matchId: 'm1',
        voterPlayerId: 'alice',
        likePlayerIds: ['bob', 'cara'],
      ),
    );

    expect(feedback.items, hasLength(1));
    expect(profile.likesXp, 2 * kXpPerLike);

    await service.saveFeedback(
      const GameFeedback(
        matchId: 'm1',
        voterPlayerId: 'bob',
        likePlayerIds: ['alice'],
      ),
      awardGiverXp: false,
    );
    expect(profile.likesXp, 2 * kXpPerLike);
  });
}
