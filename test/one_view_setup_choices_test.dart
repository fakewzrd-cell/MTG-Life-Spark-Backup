import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/one_view/one_view_state.dart';
import 'package:mgt_life_spark/features/one_view/one_view_setup_screen.dart';
import 'package:mgt_life_spark/ui/theme/app_theme.dart';
import 'package:mgt_life_spark/ui/tokens/app_color_palettes.dart';
import 'package:mgt_life_spark/ui/tokens/color_tokens.dart';

import 'support/test_l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => ColorTokens.applyScheme(AppColorSchemeId.violet));

  testWidgets('player count and starting life each fit on one line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          home: const OneViewSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final players = [for (var n = 1; n <= 6; n++) _choiceRect(tester, '$n')];
    expect(players.map((rect) => rect.top).toSet(), hasLength(1));
    expect(players.first.height, 56);
    expect(players.last.right, lessThanOrEqualTo(390));
    expect(players.first.left, greaterThanOrEqualTo(0));
    expect(
      players.map((rect) => rect.width),
      everyElement(closeTo(players.first.width, 0.5)),
    );

    final lives = [
      for (final label in ['20', '25', '30', '40', '60'])
        _choiceRect(tester, label),
      _choiceRectOf(tester, find.byIcon(Icons.add_rounded)),
    ];
    expect(find.text('Custom…'), findsNothing);
    expect(lives.map((rect) => rect.top).toSet(), hasLength(1));
    expect(lives.first.top, greaterThan(players.first.bottom));
    expect(lives.last.right, lessThanOrEqualTo(390));

    expect(find.text('Planechase'), findsNothing);
    final context = tester.element(find.byType(OneViewSetupScreen));
    ProviderScope.containerOf(
      context,
    ).read(oneViewProvider.notifier).setStartingLife(75);
    await tester.pumpAndSettle();
    expect(find.text('75'), findsOneWidget);

    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pump();
    final timer = tester.getRect(
      find.ancestor(
        of: find.text('Extra modes'),
        matching: find.byType(ExpansionTile),
      ),
    );
    final start = tester.getRect(find.text('Start Game'));
    // The final collapsed group scrolls clear of the start bar.
    expect(timer.bottom, lessThanOrEqualTo(start.top + 1));
    expect(start.top - timer.bottom, lessThan(40));
    expect(tester.takeException(), isNull);
  });
}

Rect _choiceRect(WidgetTester tester, String label) {
  return _choiceRectOf(tester, find.text(label));
}

Rect _choiceRectOf(WidgetTester tester, Finder finder) {
  return tester.getRect(
    find.ancestor(
      of: finder,
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 56,
      ),
    ),
  );
}
