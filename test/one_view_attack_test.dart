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

  test(
    'attack cards stay on one row until a row would be too narrow to tap',
    () {
      expect(oneViewAttackGrid(count: 1, maxWidth: 320), (columns: 1, rows: 1));
      expect(oneViewAttackGrid(count: 5, maxWidth: 760), (columns: 5, rows: 1));
      expect(oneViewAttackGrid(count: 3, maxWidth: 330), (columns: 3, rows: 1));
      expect(oneViewAttackGrid(count: 5, maxWidth: 330), (columns: 3, rows: 2));
      expect(oneViewAttackGrid(count: 4, maxWidth: 330), (columns: 2, rows: 2));

      final height = oneViewAttackCardHeight(
        count: 5,
        rows: 2,
        cardWidth: 100,
        maxHeight: 280,
      );
      expect(height * 2 + 16, lessThanOrEqualTo(280));
    },
  );

  test('a drag keeps each opponent in the order the finger entered', () {
    bool claimed(int index) => index != 2;
    expect(
      oneViewAttackTargets(
        from: 0,
        samples: const [0, null, 1, 2, 1, 3, 3, 9],
        seatCount: 4,
        isClaimed: claimed,
      ),
      [1, 3],
    );
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

  testWidgets('damage waits for a first hit and Done closes it', (
    tester,
  ) async {
    ColorTokens.applyScheme(AppColorSchemeId.violet);
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 2);
    notifier.startTable();
    notifier.claimAsGuest(0, name: 'Ada');
    notifier.claimAsGuest(1, name: 'Nissa');
    var dismissed = false;
    await tester.pumpWidget(
      _host(
        container,
        OneViewAttackOverlay(
          attackerIndex: 0,
          defenderIndexes: const [1],
          faceAttackerUpsideDown: false,
          onDismiss: () => dismissed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(dismissed, isFalse);
    await tester.tap(find.text('Damage'));
    await tester.pump(const Duration(seconds: 10));
    expect(dismissed, isFalse);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
    expect(tester.takeException(), isNull);
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
          defenderIndexes: const [1],
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
          defenderIndexes: const [1],
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

  testWidgets('one attack deals a point to each player the drag reached', (
    tester,
  ) async {
    ColorTokens.applyScheme(AppColorSchemeId.violet);
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 3);
    notifier.setStartingLife(40);
    notifier.startTable();
    notifier.claimAsGuest(0, name: 'Ada');
    notifier.claimAsGuest(1, name: 'Nissa');
    notifier.claimAsGuest(2, name: 'Jace');
    notifier.adjustLife(1, -2);
    notifier.adjustLife(2, -7);

    await tester.pumpWidget(
      _host(
        container,
        OneViewAttackOverlay(
          attackerIndex: 0,
          defenderIndexes: const [1, 2],
          faceAttackerUpsideDown: false,
          onDismiss: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Damage'));
    await tester.pump();
    await tester.tap(find.text('38'));
    await tester.pump();
    await tester.tap(find.text('33'));
    await tester.pump();

    expect(container.read(oneViewProvider).seats[1].life, 37);
    expect(container.read(oneViewProvider).seats[2].life, 32);
    expect(container.read(oneViewProvider).seats[0].life, 40);

    await tester.tap(find.text('Commander damage'));
    await tester.pump();
    await tester.tap(find.text('37'));
    await tester.pump();
    await tester.tap(find.text('32'));
    await tester.pump();

    final nissa = container.read(oneViewProvider).seats[1];
    final jace = container.read(oneViewProvider).seats[2];
    expect(nissa.life, 36);
    expect(nissa.commanderDamageFrom[0], 1);
    expect(jace.life, 31);
    expect(jace.commanderDamageFrom[0], 1);
  });

  testWidgets('several target cards fit on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ColorTokens.applyScheme(AppColorSchemeId.violet);
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 4);
    notifier.setStartingLife(40);
    notifier.startTable();
    notifier.claimAsGuest(0, name: 'Ada');
    notifier.claimAsGuest(1, name: 'Nissa');
    notifier.claimAsGuest(2, name: 'Jace');
    notifier.claimAsGuest(3, name: 'Liliana');

    await tester.pumpWidget(
      _host(
        container,
        OneViewAttackOverlay(
          attackerIndex: 0,
          defenderIndexes: const [1, 2, 3],
          faceAttackerUpsideDown: true,
          onDismiss: _noopDismiss,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Damage'), findsOneWidget);
    expect(find.text('Commander damage'), findsOneWidget);
    expect(find.text('Nissa'), findsOneWidget);
    expect(find.text('Jace'), findsOneWidget);
    expect(find.text('Liliana'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.text('Nissa'), findsOneWidget);
    expect(find.text('Liliana'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('five targets fit without scrolling', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ColorTokens.applyScheme(AppColorSchemeId.violet);
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(oneViewProvider.notifier);
    notifier.prepareSetup(playerCount: 6);
    notifier.setStartingLife(40);
    notifier.startTable();
    const names = ['Ada', 'Nissa', 'Jace', 'Liliana', 'Chandra', 'Gideon'];
    for (var i = 0; i < names.length; i++) {
      notifier.claimAsGuest(i, name: names[i]);
    }

    await tester.pumpWidget(
      _host(
        container,
        OneViewAttackOverlay(
          attackerIndex: 0,
          defenderIndexes: const [1, 2, 3, 4, 5],
          faceAttackerUpsideDown: false,
          onDismiss: _noopDismiss,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsNothing);
    for (final name in names.skip(1)) {
      final rect = tester.getRect(find.text(name));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(844));
    }
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsNothing);
    for (final name in names.skip(1)) {
      final rect = tester.getRect(find.text(name));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(390));
    }
    expect(tester.takeException(), isNull);
  });
}

void _noopDismiss() {}

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
