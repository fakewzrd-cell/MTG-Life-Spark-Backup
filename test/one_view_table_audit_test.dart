import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/models/app_settings.dart';
import 'package:mgt_life_spark/core/models/player_profile.dart';
import 'package:mgt_life_spark/core/one_view/one_view_state.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';
import 'package:mgt_life_spark/features/one_view/one_view_table_screen.dart';
import 'package:mgt_life_spark/ui/theme/app_theme.dart';
import 'package:mgt_life_spark/ui/tokens/app_color_palettes.dart';
import 'package:mgt_life_spark/ui/tokens/color_tokens.dart';

import 'support/test_l10n.dart';
import 'support/test_profile_repository.dart';
import 'support/test_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ColorTokens.applyScheme(AppColorSchemeId.violet);
    _mockWakelock();
  });

  testWidgets('a slide onto another player does not change life', (
    tester,
  ) async {
    await _openTable(tester, const Size(390, 844));
    final lives = find.text('40');
    expect(lives, findsNWidgets(2));

    final from = tester.getCenter(lives.first);
    final to = tester.getCenter(lives.at(1));
    final gesture = await tester.startGesture(from);
    await gesture.moveTo(to);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_cardScale(tester, 1), closeTo(1.04, 0.02));
    expect(_cardBorder(tester, 1).width, 3);
    expect(_cardScale(tester, 0), closeTo(1, 0.02));
    expect(_cardBorder(tester, 0).width, 1);
    await gesture.up();
    await tester.pump();

    expect(find.text('39'), findsNothing);
    expect(find.text('41'), findsNothing);
    expect(find.text('Damage'), findsOneWidget);
    expect(find.text('Commander damage'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _letGesturesFinish(tester);
  });

  testWidgets('coming back onto your card still does not change life', (
    tester,
  ) async {
    await _openTable(tester, const Size(390, 844));
    final lives = find.text('40');
    final from = tester.getCenter(lives.at(1));
    final other = tester.getCenter(lives.first);

    final gesture = await tester.startGesture(from);
    await gesture.moveTo(other);
    await gesture.moveTo(from);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_cardBorder(tester, 0).width, 2);
    expect(_cardScale(tester, 0), closeTo(1, 0.02));
    expect(_cardScale(tester, 1), closeTo(1, 0.02));
    await gesture.up();
    await tester.pump();

    expect(find.text('39'), findsNothing);
    expect(find.text('41'), findsNothing);
    expect(find.text('Damage'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _letGesturesFinish(tester);
  });

  testWidgets('a slide that starts on + does not attack or change life', (
    tester,
  ) async {
    await _openTable(tester, const Size(390, 844));
    final adds = find.byIcon(Icons.add_rounded);
    expect(adds, findsNWidgets(2));
    final first = tester.getCenter(adds.at(0));
    final second = tester.getCenter(adds.at(1));
    final plus = first.dy > second.dy ? first : second;
    final other = tester.getCenter(find.text('40').first);

    final gesture = await tester.startGesture(plus);
    await gesture.moveTo(other);
    await gesture.up();
    await tester.pump();

    expect(find.text('40'), findsNWidgets(2));
    expect(find.text('41'), findsNothing);
    expect(find.text('39'), findsNothing);
    expect(find.text('Damage'), findsNothing);
    expect(tester.takeException(), isNull);
    await _letGesturesFinish(tester);
  });

  testWidgets('+ still changes life, and a swipe that stays does too', (
    tester,
  ) async {
    await _openTable(tester, const Size(390, 844));
    final adds = find.byIcon(Icons.add_rounded);
    final first = tester.getCenter(adds.at(0));
    final second = tester.getCenter(adds.at(1));
    final plus = first.dy > second.dy ? first : second;

    await tester.tapAt(plus);
    await tester.pump();
    expect(find.text('41'), findsOneWidget);

    final mine = tester.getCenter(find.text('41'));
    // These seats are wider than they are tall, so life follows a sideways swipe.
    // The drag recognizer spends the first move crossing the touch slop, so a
    // real finger's later moves are what change life.
    final gesture = await tester.startGesture(mine);
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(const Offset(10, 0));
    }
    await gesture.up();
    await tester.pump();

    expect(find.text('41'), findsNothing);
    expect(find.text('Damage'), findsNothing);
    expect(tester.takeException(), isNull);
    await _letGesturesFinish(tester);
  });

  testWidgets('a slide can mark two opponents', (tester) async {
    await _openTable(tester, const Size(390, 844), players: 4);
    final nissa = tester.getCenter(find.text('Nissa'));
    final jace = tester.getCenter(find.text('Jace'));
    final liliana = tester.getCenter(find.text('Liliana'));

    final gesture = await tester.startGesture(nissa);
    await gesture.moveTo(jace);
    await gesture.moveTo(liliana);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_cardScale(tester, 3), closeTo(1.04, 0.02));
    expect(_cardBorder(tester, 2).width, 2);
    expect(_cardScale(tester, 2), closeTo(1, 0.02));
    expect(_cardBorder(tester, 1).width, 1);
    await gesture.up();
    await tester.pump();

    expect(find.text('Damage'), findsOneWidget);
    expect(find.text('Jace'), findsNWidgets(2));
    expect(find.text('Liliana'), findsNWidgets(2));
    expect(find.text('Nissa'), findsOneWidget);
    expect(find.text('39'), findsNothing);
    expect(tester.takeException(), isNull);
    await _letGesturesFinish(tester);
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('up/down life swipes work on $size without attacking', (
      tester,
    ) async {
      final container = await _openTable(tester, size, players: 4);
      final from = tester.getCenter(find.text('40').at(2));
      final initial = container.read(oneViewProvider).seats[2].life;
      final gesture = await tester.startGesture(from);
      for (var step = 1; step <= 4; step++) {
        await gesture.moveTo(from + Offset(0, -step * 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
      expect(container.read(oneViewProvider).seats[2].life, initial + 1);
      expect(find.text('Damage'), findsNothing);
      final down = await tester.startGesture(
        tester.getCenter(find.text('${initial + 1}')),
      );
      for (var step = 1; step <= 4; step++) {
        await down.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await down.up();
      await tester.pump();
      expect(container.read(oneViewProvider).seats[2].life, initial);
      expect(find.text('Damage'), findsNothing);
      expect(tester.takeException(), isNull);
      await _letGesturesFinish(tester);
    });
  }

  testWidgets('landscape life keypad scrolls without overflowing', (
    tester,
  ) async {
    await _openTable(tester, const Size(780, 360), players: 4);
    await tester.tap(find.text('40').at(2));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('40').at(2));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('landscape keeps life large and slides between seated players', (
    tester,
  ) async {
    await _openTable(tester, const Size(780, 360), players: 4);
    final life = tester.widget<Text>(find.text('40').first);
    expect(life.style!.fontSize, greaterThanOrEqualTo(64));
    final lives = find.text('40');
    final from = tester.getCenter(lives.at(2));
    final to = tester.getCenter(lives.at(3));
    final gesture = await tester.startGesture(from);
    for (var step = 1; step <= 12; step++) {
      await gesture.moveTo(Offset.lerp(from, to, step / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Damage'), findsOneWidget);
    expect(find.text('Commander damage'), findsOneWidget);
    expect(find.text('39'), findsNothing);
    expect(find.text('41'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player and table menus open without overflow', (tester) async {
    await _openTable(tester, const Size(390, 844));
    await tester.longPress(find.text('Nissa'));
    await tester.pumpAndSettle();
    expect(find.text('Poison'), findsOneWidget);
    expect(find.text('Commander damage'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(OneViewTableScreen)));
    await tester.pumpAndSettle();
    expect(find.text('Table menu'), findsOneWidget);
    expect(find.text('End table'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape table menu stays inside the safe area', (
    tester,
  ) async {
    await _openTable(tester, const Size(844, 390));
    const safe = FakeViewPadding(left: 48, right: 32, bottom: 24);
    tester.view.viewPadding = safe;
    tester.view.padding = safe;
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final menu = tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    expect(menu.left, greaterThanOrEqualTo(48));
    expect(menu.right, lessThanOrEqualTo(844 - 32));
    expect(menu.top, greaterThanOrEqualTo(16));
    expect(menu.bottom, lessThanOrEqualTo(390 - 24 + 0.5));
    expect(menu.width, closeTo(600, 1));

    final tools = _inkRect(tester, 'Tools');
    final settings = _inkRect(tester, 'Table settings');
    final end = _inkRect(tester, 'End table');
    final divider = tester.getRect(find.byType(Divider));
    expect(tools.top, closeTo(settings.top, 1));
    expect(tools.height, closeTo(settings.height, 1));
    expect(settings.left - tools.right, closeTo(16, 1));
    expect(end.left, closeTo(tools.left, 1));
    expect(end.right, closeTo(settings.right, 1));
    expect(end.width, greaterThan(tools.width * 1.5));
    expect(divider.left, closeTo(end.left, 1));
    expect(divider.right, closeTo(end.right, 1));
    expect(end.left, greaterThanOrEqualTo(menu.left));
    expect(end.right, lessThanOrEqualTo(menu.right));
  });

  testWidgets('landscape typing stays above the keyboard', (tester) async {
    await _openTable(tester, const Size(844, 390));
    addTearDown(tester.view.resetViewInsets);

    await tester.longPress(find.text('Nissa'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Rename'));
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    final nameDialog = tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    expect(nameDialog.bottom, lessThanOrEqualTo(390 - 240 + 0.5));

    await tester.enterText(find.byType(TextField), 'Chandra');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Chandra'), findsOneWidget);
    expect(find.text('Nissa'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.longPress(find.text('Chandra'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Card art'));
    await tester.tap(find.text('Card art'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    final field = find.byKey(const ValueKey('one-view-art-search'));
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(390 - 240 + 0.5));

    Navigator.of(tester.element(field), rootNavigator: true).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 640),
    const Size(640, 320),
    const Size(390, 844),
  ]) {
    for (final count in [2, 4, 6]) {
      testWidgets('$count seats fit $size with larger text', (tester) async {
        await _openTable(tester, size, players: count, textScale: 1.3);
        expect(tester.takeException(), isNull);
        expect(find.text('40'), findsNWidgets(count));
      });
    }
  }

  testWidgets('reset requires confirmation and preserves the table on cancel', (
    tester,
  ) async {
    final container = await _openTable(tester, const Size(390, 844));
    container.read(oneViewProvider.notifier).adjustLife(0, -7);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset life'));
    await tester.pumpAndSettle();
    expect(container.read(oneViewProvider).seats.first.life, 33);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(container.read(oneViewProvider).seats.first.life, 33);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset life'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset life'));
    await tester.pumpAndSettle();
    expect(container.read(oneViewProvider).seats.first.life, 40);
    expect(tester.takeException(), isNull);
  });
}

Rect _inkRect(WidgetTester tester, String label) {
  return tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
  );
}

double _cardScale(WidgetTester tester, int index) {
  final transform = tester.widget<Transform>(
    find.byKey(ValueKey('one-view-attack-scale-$index')),
  );
  return transform.transform.getMaxScaleOnAxis();
}

BorderSide _cardBorder(WidgetTester tester, int index) {
  final materials = tester.widgetList<Material>(
    find.descendant(
      of: find.byKey(ValueKey('one-view-attack-scale-$index')),
      matching: find.byType(Material),
    ),
  );
  final card = materials.firstWhere(
    (material) => material.shape is RoundedRectangleBorder,
  );
  return (card.shape! as RoundedRectangleBorder).side;
}

/// The attack popup closes itself after a few seconds, and a tap leaves a
/// short double-tap timer. Advance past both so the test ends cleanly.
Future<void> _letGesturesFinish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
}

Future<ProviderContainer> _openTable(
  WidgetTester tester,
  Size size, {
  int players = 2,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
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
  addTearDown(container.dispose);
  final notifier = container.read(oneViewProvider.notifier);
  notifier.prepareSetup(playerCount: players);
  notifier.setStartingLife(40);
  notifier.startTable();
  const names = ['Ada', 'Nissa', 'Jace', 'Liliana', 'Chandra', 'Gideon'];
  for (var i = 0; i < players; i++) {
    notifier.claimAsGuest(i, name: names[i]);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        home: const OneViewTableScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void _mockWakelock() {
  final binding = TestDefaultBinaryMessengerBinding.instance;
  for (final name in [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
  ]) {
    binding.defaultBinaryMessenger.setMockMessageHandler(name, (
      ByteData? message,
    ) async {
      return const StandardMessageCodec().encodeMessage(<Object?>[null]);
    });
  }
}
