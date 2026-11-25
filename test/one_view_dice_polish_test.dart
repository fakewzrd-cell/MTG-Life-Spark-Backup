import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/game_session_events.dart';
import 'package:mgt_life_spark/features/game/widgets/table_tool_result_overlay.dart';
import 'package:mgt_life_spark/features/one_view/one_view_table_tools.dart';
import 'package:mgt_life_spark/ui/theme/app_theme.dart';

import 'support/test_l10n.dart';

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets('local roll again stays open, reduced motion: $reducedMotion', (
      tester,
    ) async {
      var dismissed = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: testLocalizationDelegates,
            supportedLocales: testSupportedLocales,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reducedMotion),
                  child: child!,
                ),
            home: Scaffold(
              body: OneViewDiceOverlay(
                announcement: const TableToolAnnouncement(
                  id: 'first',
                  playerId: 'one-view',
                  username: 'Table',
                  kind: TableToolKind.d6,
                  dieValue: 4,
                ),
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 8));
      expect(dismissed, isFalse);
      await tester.tap(find.text('Roll again'));
      await tester.pumpAndSettle();
      expect(dismissed, isFalse);
      final overlay = tester.widget<TableToolResultOverlay>(
        find.byType(TableToolResultOverlay),
      );
      expect(overlay.announcement.id, isNot('first'));
      expect(overlay.announcement.dieValue, inInclusiveRange(1, 6));
      await tester.tap(find.text('Tap to dismiss'));
      await tester.pump();
      expect(dismissed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
