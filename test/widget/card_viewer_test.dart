import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/features/profile/card_viewer.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';

import '../support/test_l10n.dart';

void main() {
  test('snapAlbumCardSpin prefers the nearer face', () {
    expect(snapAlbumCardSpin(0), 0);
    expect(snapAlbumCardSpin(0.4), 0);
    expect(snapAlbumCardSpin(math.pi * 0.6), math.pi);
    expect(snapAlbumCardSpin(math.pi), math.pi);
    expect(snapAlbumCardSpin(math.pi * 1.6), closeTo(2 * math.pi, 1e-9));
  });

  testWidgets('double-faced preview can flip to the other face', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed:
                    () => showAlbumCardViewer(
                      context,
                      name:
                          'Soundwave, Sonic Spy // Soundwave, Superior Captain',
                      backImageUrl: 'missing-back-face',
                    ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Flip'), findsOneWidget);
    expect(find.text('Soundwave, Sonic Spy'), findsWidgets);

    await tester.tap(find.text('Flip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Soundwave, Superior Captain'), findsWidgets);
  });

  testWidgets('single-faced preview has no flip control', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed:
                    () => showAlbumCardViewer(
                      context,
                      name: 'Sol Ring',
                      imageUrl: 'https://img/sol.jpg',
                    ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Flip'), findsNothing);
  });
}
