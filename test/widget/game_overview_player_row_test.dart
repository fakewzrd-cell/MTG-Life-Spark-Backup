import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/game_providers.dart';
import 'package:mgt_life_spark/features/game/widgets/game_overview_view.dart';

import '../support/game_widget_harness.dart';

void main() {
  testWidgets('monarch badge sits under the name and does not overlap tax', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final alice = harnessPlayer(id: 'alice').copyWith(commanderCastCount: 2);
    final game = harnessGame(
      localId: 'alice',
      players: [alice, harnessPlayer(id: 'bob')],
    ).copyWith(monarchPlayerId: 'alice');

    await tester.pumpWidget(
      wrapGameWidget(
        game: game,
        child: Scaffold(
          body: Consumer(
            builder:
                (context, ref, _) => GameOverviewView(
                  game: ref.watch(gameProvider),
                  onClose: () {},
                ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final politics = tester.getRect(
      find.byKey(const ValueKey('overview-politics-alice')),
    );
    final tax = tester.getRect(
      find.byKey(const ValueKey('overview-tax-alice')),
    );
    expect(politics.overlaps(tax), isFalse);

    final trailing = tester.getRect(
      find.byKey(const ValueKey('overview-trailing-alice')),
    );
    expect(politics.right, lessThanOrEqualTo(trailing.left + 8));
    expect(trailing.right, greaterThan(politics.right));
  });

  testWidgets('solo practice hides the empty player menu', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final alice = harnessPlayer(id: 'alice');
    final game = harnessGame(localId: 'alice', players: [alice]);

    await tester.pumpWidget(
      wrapGameWidget(
        game: game,
        child: Scaffold(
          body: Consumer(
            builder:
                (context, ref, _) => GameOverviewView(
                  game: ref.watch(gameProvider),
                  onClose: () {},
                ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('opponent row shows a readable player menu', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = harnessGame(
      localId: 'alice',
      players: [harnessPlayer(id: 'alice'), harnessPlayer(id: 'bob')],
    );

    await tester.pumpWidget(
      wrapGameWidget(
        game: game,
        child: Scaffold(
          body: Consumer(
            builder:
                (context, ref, _) => GameOverviewView(
                  game: ref.watch(gameProvider),
                  onClose: () {},
                ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PopupMenuButton<String>), findsWidgets);
    expect(find.byIcon(Icons.more_vert), findsWidgets);
  });
}
