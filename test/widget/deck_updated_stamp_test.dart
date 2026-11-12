import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/features/profile/deck_album_screen.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';

import '../support/test_l10n.dart';

void main() {
  testWidgets('deck profile stamp is hidden until an update exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: DeckProfileUpdatedStamp(updatedAtMillis: 0)),
      ),
    );
    expect(find.byKey(const ValueKey('deck-profile-updated')), findsNothing);
    expect(find.textContaining('Updated'), findsNothing);
  });

  testWidgets('deck profile stamp shows when the deck was updated', (
    tester,
  ) async {
    final when = DateTime(2026, 11, 11, 20, 30);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: DeckProfileUpdatedStamp(
            updatedAtMillis: when.millisecondsSinceEpoch,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('deck-profile-updated')), findsOneWidget);
    expect(find.textContaining('Updated'), findsOneWidget);
    expect(find.textContaining('Nov 11, 2026'), findsOneWidget);
  });
}
