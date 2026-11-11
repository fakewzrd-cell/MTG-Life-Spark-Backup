import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/deck/deck_list_text.dart';
import 'package:mgt_life_spark/features/profile/album_listing.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';

import '../support/test_l10n.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required AlbumListing listing,
    required List<AlbumListCard> faceCards,
    required String faceTitle,
    List<AlbumListCard> cards = const [],
    void Function(AlbumListCard card, int delta)? onCount,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ListView(
                children: albumListingChildren(
                  context: context,
                  listing: listing,
                  cards: cards,
                  faceCards: faceCards,
                  faceTitle: faceTitle,
                  onCount: onCount,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  const creature = AlbumListCard(
    name: 'Birds of Paradise',
    count: 1,
    group: DeckCardGroup.creature,
  );

  const commanderFace = AlbumListCard(
    name: 'Atraxa, Praetors\' Voice',
    count: 1,
    group: DeckCardGroup.creature,
    isFaceSlot: true,
    canAddCopy: false,
  );

  const blankFace = AlbumListCard(
    name: 'Choose commander',
    count: 0,
    group: DeckCardGroup.other,
    isFaceSlot: true,
    isBlank: true,
    canAddCopy: false,
  );

  testWidgets('pins commander above creatures in Types', (tester) async {
    await pumpHost(
      tester,
      listing: AlbumListing.types,
      faceTitle: 'Commander',
      faceCards: const [commanderFace],
      cards: const [creature],
    );

    expect(find.text('Commander'), findsOneWidget);
    expect(find.text('Creatures'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Commander')).dy,
      lessThan(tester.getTopLeft(find.text('Creatures')).dy),
    );
    expect(find.text('Atraxa, Praetors\' Voice'), findsOneWidget);
    expect(find.text('Birds of Paradise'), findsOneWidget);
  });

  testWidgets('blank commander slot sits at the top of Grid', (tester) async {
    await pumpHost(
      tester,
      listing: AlbumListing.grid,
      faceTitle: 'Commander',
      faceCards: const [blankFace],
      cards: const [creature],
    );

    expect(find.byKey(const ValueKey('album-card-face-blank')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('album-card-Birds of Paradise')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('album-card-face-blank'))).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('album-card-Birds of Paradise')),
            )
            .dy,
      ),
    );
  });

  testWidgets('tapping a blank face slot asks to pick', (tester) async {
    var picks = 0;
    await pumpHost(
      tester,
      listing: AlbumListing.types,
      faceTitle: 'Commander',
      faceCards: const [blankFace],
      onCount: (card, delta) {
        if (card.isFaceSlot && card.isBlank && delta > 0) picks++;
      },
    );

    await tester.tap(find.text('Choose commander'));
    await tester.pump();
    expect(picks, 1);
  });

  testWidgets('minus on a filled face slot clears it', (tester) async {
    var cleared = 0;
    await pumpHost(
      tester,
      listing: AlbumListing.types,
      faceTitle: 'Cover',
      faceCards: const [commanderFace],
      onCount: (card, delta) {
        if (card.isFaceSlot && delta < 0) cleared++;
      },
    );

    await tester.tap(find.byTooltip('Remove a copy'));
    await tester.pump();
    expect(cleared, 1);
  });
}
