import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';
import 'package:mgt_life_spark/shared/widgets/deck_shuffle_overlay.dart';

import '../support/test_l10n.dart';

void main() {
  testWidgets('shuffle wait appears after 250ms and hides on end', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final wait = ShuffleWait(onChanged: () {});
    addTearDown(wait.dispose);
    wait.begin();
    await tester.pump(const Duration(milliseconds: 249));
    expect(wait.visible, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(wait.visible, isTrue);
    wait.end();
    expect(wait.visible, isFalse);
  });

  testWidgets('shuffle wait never appears if the fetch finishes first', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final wait = ShuffleWait(onChanged: () {});
    addTearDown(wait.dispose);
    wait.begin();
    await tester.pump(const Duration(milliseconds: 100));
    wait.end();
    await tester.pump(const Duration(milliseconds: 500));
    expect(wait.visible, isFalse);
  });

  testWidgets('overlay paints the shuffle animation when visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(
          body: Stack(children: [DeckShuffleOverlay(visible: true)]),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('deck-shuffle-overlay')), findsOneWidget);
  });
}
