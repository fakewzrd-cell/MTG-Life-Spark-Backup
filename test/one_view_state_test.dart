import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/one_view/one_view_state.dart';
import 'package:mgt_life_spark/core/models/player_profile.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';

import 'support/test_profile_repository.dart';
import 'support/test_settings_repository.dart';

ProviderContainer _container({String playerId = 'local-1'}) {
  return ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(
        TestProfileRepository(
          profile: PlayerProfile(username: 'Host', playerId: playerId),
        ),
      ),
      settingsRepositoryProvider.overrideWithValue(TestSettingsRepository()),
    ],
  );
}

void main() {
  test('startTable seeds empty seats from player count', () {
    final container = _container();
    addTearDown(container.dispose);

    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 4);
    notifier.setStartingLife(40);
    notifier.startTable();

    final state = container.read(oneViewProvider);
    expect(state.started, isTrue);
    expect(state.seats, hasLength(4));
    expect(state.seats.every((s) => s.isEmpty), isTrue);
    expect(state.seats.every((s) => s.life == 40), isTrue);
  });

  test('claimAsMe then second seat with same profile is blocked', () {
    final container = _container();
    addTearDown(container.dispose);

    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 2);
    notifier.startTable();

    expect(notifier.claimAsMe(0), isTrue);
    expect(notifier.claimAsMe(1), isFalse);
    expect(container.read(oneViewProvider).seats[0].username, 'Host');
  });

  test('guests skip deck identity fields', () {
    final container = _container();
    addTearDown(container.dispose);

    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 1);
    notifier.startTable();
    expect(notifier.claimAsGuest(0, name: 'Bob'), isTrue);
    final seat = container.read(oneViewProvider).seats[0];
    expect(seat.isGuest, isTrue);
    expect(seat.username, 'Bob');
    expect(seat.selectedDeckId, isNull);
  });
}
