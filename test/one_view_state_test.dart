import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/one_view/one_view_layout.dart';
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

  test('a guest can set commander art without a deck', () {
    final container = _container();
    addTearDown(container.dispose);

    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 1);
    notifier.startTable();
    notifier.claimAsGuest(0, name: 'Bob');
    notifier.setCommanderVisual(
      seatIndex: 0,
      name: 'Atraxa, Praetors\' Voice',
      imageUrl: 'https://example.com/atraxa.jpg',
      colorIdentity: const ['W', 'U', 'B', 'G'],
    );

    final seat = container.read(oneViewProvider).seats[0];
    expect(seat.isGuest, isTrue);
    expect(seat.selectedDeckId, isNull);
    expect(seat.commanderName, 'Atraxa, Praetors\' Voice');
    expect(seat.commanderImageUrl, 'https://example.com/atraxa.jpg');

    notifier.clearCommanderVisual(0);
    final cleared = container.read(oneViewProvider).seats[0];
    expect(cleared.commanderName, isNull);
    expect(cleared.commanderImageUrl, isNull);
    expect(cleared.username, 'Bob');
  });

  test('startTable picks the default sitting layout for the count', () {
    final container = _container();
    addTearDown(container.dispose);

    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 4);
    notifier.startTable();
    expect(container.read(oneViewProvider).layout, OneViewSeatLayout.grid2x2);

    notifier.setLayout(OneViewSeatLayout.oneOverThree);
    expect(
      container.read(oneViewProvider).layout,
      OneViewSeatLayout.oneOverThree,
    );
    notifier.setLayout(OneViewSeatLayout.sideBySide);
    expect(
      container.read(oneViewProvider).layout,
      OneViewSeatLayout.oneOverThree,
    );
  });

  test('adding a seat drops a layout that no longer fits', () {
    final container = _container();
    addTearDown(container.dispose);

    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 2);
    notifier.startTable();
    notifier.setLayout(OneViewSeatLayout.sideBySide);
    notifier.addSeats(1);

    final state = container.read(oneViewProvider);
    expect(state.seats, hasLength(3));
    expect(state.layout, OneViewSeatLayout.oneOverTwo);
  });
}
