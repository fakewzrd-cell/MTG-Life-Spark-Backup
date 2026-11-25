import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/models/player_deck.dart';
import 'package:mgt_life_spark/core/one_view/one_view_layout.dart';
import 'package:mgt_life_spark/core/one_view/one_view_state.dart';
import 'package:mgt_life_spark/core/models/player_profile.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';

import 'support/test_deck_repository.dart';
import 'support/test_profile_repository.dart';
import 'support/test_settings_repository.dart';

ProviderContainer _container({
  String playerId = 'local-1',
  PlayerProfile? profile,
  List<PlayerDeck> decks = const [],
}) {
  return ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(
        TestProfileRepository(
          profile:
              profile ?? PlayerProfile(username: 'Host', playerId: playerId),
        ),
      ),
      deckRepositoryProvider.overrideWithValue(
        TestDeckRepository(decks: decks),
      ),
      settingsRepositoryProvider.overrideWithValue(TestSettingsRepository()),
    ],
  );
}

PlayerDeck _deck({
  required String id,
  required String commander,
  String? image,
}) {
  return PlayerDeck(
    id: id,
    displayName: commander,
    commanderName: commander,
    commanderImageUrl: image,
    format: 'commander',
    deckStyleId: 'voltron',
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

  test(
    'sitting as yourself uses the deck commander, then the profile photo',
    () {
      final withDeck = _container(
        profile: PlayerProfile(
          username: 'Host',
          playerId: 'local-1',
          profileAvatarImageUrl: 'https://example.com/face.png',
        ),
        decks: [
          _deck(
            id: 'deck-1',
            commander: 'Atraxa',
            image: 'https://example.com/atraxa.jpg',
          ),
        ],
      );
      addTearDown(withDeck.dispose);
      final decked = withDeck.read(oneViewProvider.notifier);
      decked.prepareSetup(playerCount: 1);
      decked.startTable();
      expect(decked.claimAsMe(0), isTrue);
      final seated = withDeck.read(oneViewProvider).seats[0];
      expect(seated.selectedDeckId, 'deck-1');
      expect(seated.commanderName, 'Atraxa');
      expect(seated.cardArtUrl, 'https://example.com/atraxa.jpg');

      final photoOnly = _container(
        profile: PlayerProfile(
          username: 'Host',
          playerId: 'local-1',
          profileAvatarImageUrl: 'https://example.com/face.png',
          selectedCommanderName: 'Atraxa',
          selectedCommanderImageUrl: 'https://example.com/atraxa.jpg',
        ),
      );
      addTearDown(photoOnly.dispose);
      final plain = photoOnly.read(oneViewProvider.notifier);
      plain.prepareSetup(playerCount: 1);
      plain.startTable();
      expect(plain.claimAsMe(0), isTrue);
      final face = photoOnly.read(oneViewProvider).seats[0];
      expect(face.selectedDeckId, isNull);
      expect(face.commanderImageUrl, 'https://example.com/atraxa.jpg');
      expect(face.cardArtUrl, 'https://example.com/atraxa.jpg');

      final avatarOnly = _container(
        profile: PlayerProfile(
          username: 'Host',
          playerId: 'local-1',
          profileAvatarImageUrl: 'https://example.com/face.png',
        ),
      );
      addTearDown(avatarOnly.dispose);
      final avatarNotifier = avatarOnly.read(oneViewProvider.notifier);
      avatarNotifier.prepareSetup(playerCount: 1);
      avatarNotifier.startTable();
      expect(avatarNotifier.claimAsMe(0), isTrue);
      final avatarSeat = avatarOnly.read(oneViewProvider).seats[0];
      expect(avatarSeat.commanderImageUrl, isNull);
      expect(avatarSeat.cardArtUrl, 'https://example.com/face.png');
    },
  );

  test(
    'a scanned profile keeps its own photo and does not take a local deck',
    () {
      final container = _container(
        decks: [
          _deck(
            id: 'deck-1',
            commander: 'Atraxa',
            image: 'https://example.com/atraxa.jpg',
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(oneViewProvider.notifier);
      notifier.prepareSetup(playerCount: 2);
      notifier.startTable();

      expect(
        notifier.claimFromSitCode(
          seatIndex: 0,
          playerId: 'friend-2',
          username: 'Nissa',
          avatarUrl: 'https://example.com/nissa.png',
        ),
        isTrue,
      );
      final friend = container.read(oneViewProvider).seats[0];
      expect(friend.selectedDeckId, isNull);
      expect(friend.commanderImageUrl, isNull);
      expect(friend.cardArtUrl, 'https://example.com/nissa.png');

      expect(
        notifier.claimFromSitCode(
          seatIndex: 1,
          playerId: 'local-1',
          username: 'Host',
          avatarUrl: 'https://example.com/face.png',
        ),
        isTrue,
      );
      final mine = container.read(oneViewProvider).seats[1];
      expect(mine.selectedDeckId, 'deck-1');
      expect(mine.cardArtUrl, 'https://example.com/atraxa.jpg');
    },
  );

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

  test('rename updates a guest seat and the local profile', () async {
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(oneViewProvider.notifier);
    final profiles =
        container.read(profileRepositoryProvider) as TestProfileRepository;
    notifier.prepareSetup(playerCount: 2);
    notifier.startTable();
    expect(notifier.claimAsMe(0), isTrue);
    expect(notifier.claimAsGuest(1, name: 'Nissa'), isTrue);

    await notifier.renameSeat(0, 'Ada');
    expect(container.read(oneViewProvider).seats[0].username, 'Ada');
    expect(profiles.profile!.username, 'Ada');
    expect(profiles.saveCount, 1);

    await notifier.renameSeat(1, '   ');
    expect(container.read(oneViewProvider).seats[1].username, 'Nissa');
    expect(profiles.saveCount, 1);

    await notifier.renameSeat(1, 'Jace');
    expect(container.read(oneViewProvider).seats[1].username, 'Jace');
    expect(profiles.profile!.username, 'Ada');
    expect(profiles.saveCount, 1);
  });
}
