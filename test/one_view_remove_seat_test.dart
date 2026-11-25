import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/models/player_profile.dart';
import 'package:mgt_life_spark/core/one_view/one_view_state.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';

import 'support/test_profile_repository.dart';
import 'support/test_settings_repository.dart';

void main() {
  test('removeSeat keeps remaining life totals and reindexes', () {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(
          TestProfileRepository(
            profile: PlayerProfile(username: 'Host', playerId: 'local-1'),
          ),
        ),
        settingsRepositoryProvider.overrideWithValue(TestSettingsRepository()),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 3);
    notifier.startTable();
    notifier.claimAsGuest(0, name: 'A');
    notifier.claimAsGuest(1, name: 'B');
    notifier.adjustLife(0, -5);
    notifier.adjustLife(1, -2);

    expect(notifier.removeSeat(0), isTrue);
    final seats = container.read(oneViewProvider).seats;
    expect(seats, hasLength(2));
    expect(seats[0].username, 'B');
    expect(seats[0].life, 38);
    expect(seats[0].index, 0);
  });
}
