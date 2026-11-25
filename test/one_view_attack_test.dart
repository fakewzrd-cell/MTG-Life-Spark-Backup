import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/models/app_settings.dart';
import 'package:mgt_life_spark/core/models/player_profile.dart';
import 'package:mgt_life_spark/core/one_view/one_view_state.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';
import 'package:mgt_life_spark/features/one_view/one_view_attack.dart';
import 'package:mgt_life_spark/ui/theme/app_theme.dart';
import 'package:mgt_life_spark/ui/tokens/app_color_palettes.dart';
import 'package:mgt_life_spark/ui/tokens/color_tokens.dart';

import 'support/test_l10n.dart';
import 'support/test_profile_repository.dart';
import 'support/test_settings_repository.dart';

void main() {
  test('an attack starts in the middle of the card, not on the life bands', () {
    expect(oneViewAttackMinTravel, 48);

    final tall = oneViewAttackCenter(const Size(200, 400));
    expect(tall.contains(const Offset(100, 200)), isTrue);
    expect(tall.contains(const Offset(100, 20)), isFalse);
    expect(tall.contains(const Offset(100, 380)), isFalse);

    final wide = oneViewAttackCenter(const Size(400, 200));
    expect(wide.contains(const Offset(200, 100)), isTrue);
    expect(wide.contains(const Offset(20, 100)), isFalse);
    expect(wide.contains(const Offset(380, 100)), isFalse);
  });

  test('the attack center uses the same bands as the seat', () {
    expect(oneViewSeatIsTall(200, 400), isTrue);
    expect(oneViewSeatIsTall(400, 200), isFalse);
    expect(oneViewLifeBand(tall: true, maxWidth: 200, maxHeight: 400), 72);
    expect(oneViewLifeBand(tall: false, maxWidth: 400, maxHeight: 200), 64);

    final tall = oneViewAttackCenter(const Size(200, 400));
    expect(tall.top, 72);
    expect(tall.bottom, 400 - 72);

    final wide = oneViewAttackCenter(const Size(400, 200));
    expect(wide.left, 64);
    expect(wide.right, 400 - 64);
  });

  testWidgets('each tap deals one point of the chosen damage', (tester) async {
    ColorTokens.applyScheme(AppColorSchemeId.violet);
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 2);
    notifier.setStartingLife(40);
    notifier.startTable();
    notifier.claimAsGuest(0, name: 'Ada');
    notifier.claimAsGuest(1, name: 'Nissa');

    await tester.pumpWidget(
      _host(
        container,
        OneViewAttackOverlay(
          attackerIndex: 0,
          defenderIndex: 1,
          faceAttackerUpsideDown: false,
          onDismiss: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Damage'));
    await tester.pump();
    expect(container.read(oneViewProvider).seats[1].life, 40);

    await tester.tap(find.text('40'));
    await tester.pump();
    expect(container.read(oneViewProvider).seats[1].life, 39);
    expect(
      container.read(oneViewProvider).seats[1].commanderDamageFrom[0],
      isNull,
    );

    await tester.tap(find.text('Commander damage'));
    await tester.pump();
    expect(container.read(oneViewProvider).seats[1].life, 39);

    await tester.tap(find.text('39'));
    await tester.pump();
    final defender = container.read(oneViewProvider).seats[1];
    expect(defender.life, 38);
    expect(defender.commanderDamageFrom[0], 1);
  });

  testWidgets('commander damage can be tracked without changing life', (
    tester,
  ) async {
    ColorTokens.applyScheme(AppColorSchemeId.violet);
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 2);
    notifier.setStartingLife(40);
    notifier.startTable();
    notifier.updateConfig(
      container
          .read(oneViewProvider)
          .config
          .copyWith(commanderDamageReducesLife: false),
    );
    notifier.claimAsGuest(0, name: 'Ada');
    notifier.claimAsGuest(1, name: 'Nissa');

    await tester.pumpWidget(
      _host(
        container,
        OneViewAttackOverlay(
          attackerIndex: 0,
          defenderIndex: 1,
          faceAttackerUpsideDown: false,
          onDismiss: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Commander damage'));
    await tester.pump();
    await tester.tap(find.text('40'));
    await tester.pump();

    final defender = container.read(oneViewProvider).seats[1];
    expect(defender.life, 40);
    expect(defender.commanderDamageFrom[0], 1);
  });
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(
        TestProfileRepository(
          profile: PlayerProfile(username: 'Host', playerId: 'local-1'),
        ),
      ),
      settingsRepositoryProvider.overrideWithValue(
        TestSettingsRepository(AppSettings(hapticEnabled: false)),
      ),
    ],
  );
}

Widget _host(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: testLocalizationDelegates,
      supportedLocales: testSupportedLocales,
      home: child,
    ),
  );
}
