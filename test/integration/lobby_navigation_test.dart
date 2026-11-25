import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/features/game_lobby/game_lobby_screen.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';

import '../support/test_l10n.dart';
import '../support/test_profile_repository.dart';
import '../support/test_settings_repository.dart';
import 'package:mgt_life_spark/core/models/player_profile.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';

void main() {
  testWidgets('game lobby hub shows One View and Own View', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            TestProfileRepository(
              profile: PlayerProfile(username: 'Host', playerId: 'p1'),
            ),
          ),
          settingsRepositoryProvider.overrideWithValue(TestSettingsRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          home: const GameLobbyScreen(),
        ),
      ),
    );

    expect(find.text('One View'), findsOneWidget);
    expect(find.text('Own View'), findsOneWidget);
    expect(find.text('Everyone shares this phone'), findsOneWidget);
    expect(find.text('Each player uses their own phone'), findsOneWidget);
  });
}
