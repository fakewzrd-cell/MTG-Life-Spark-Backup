import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';
import 'package:mgt_life_spark/features/feedback/life_spark_help_mail.dart';
import 'package:mgt_life_spark/features/profile/welcome_screen.dart';
import 'package:mgt_life_spark/features/settings/about_screen.dart';
import 'package:mgt_life_spark/features/settings/settings_screen.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';

import '../support/test_l10n.dart';
import '../support/test_settings_repository.dart';

void main() {
  testWidgets('welcome shows the founder note before account creation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const WelcomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A note from Federick'), findsOneWidget);
    expect(find.textContaining('personal project'), findsOneWidget);
    expect(find.text('Ready to play'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('settings Help lists About above Feedback and Report a bug', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            TestSettingsRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var foundHelp = false;
    for (var i = 0; i < 24; i++) {
      if (find.text('About').evaluate().isNotEmpty &&
          find.text('Feedback').evaluate().isNotEmpty &&
          find.text('Report a bug').evaluate().isNotEmpty) {
        foundHelp = true;
        break;
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -350));
      await tester.pumpAndSettle();
    }
    expect(
      foundHelp,
      isTrue,
      reason: 'Help rows should appear after scrolling',
    );
    expect(find.textContaining(kLifeSparkHelpEmail), findsOneWidget);

    final aboutY = tester.getTopLeft(find.text('About')).dy;
    final feedbackY = tester.getTopLeft(find.text('Feedback')).dy;
    final reportY = tester.getTopLeft(find.text('Report a bug')).dy;
    expect(aboutY, lessThan(feedbackY));
    expect(feedbackY, lessThan(reportY));
  });

  testWidgets('about screen repeats the founder note and report action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        locale: const Locale('en'),
        home: const AboutScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A note from Federick'), findsOneWidget);
    expect(find.byKey(const ValueKey('about-report-bug')), findsOneWidget);
  });
}
