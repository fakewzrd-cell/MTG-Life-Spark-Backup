import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/deck/deck_list_text.dart';
import 'package:mgt_life_spark/core/models/owned_album.dart';
import 'package:mgt_life_spark/core/persistence/backup_codec.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';
import 'package:mgt_life_spark/features/profile/album_listing.dart';
import 'package:mgt_life_spark/features/profile/collection_album_screen.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';
import 'package:mgt_life_spark/ui/tokens/layout_tokens.dart';

import 'support/test_collection_repository.dart';
import 'support/test_l10n.dart';

void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 80);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

void main() {
  test('recent albums are those opened or created in the last 30 days', () {
    final now = DateTime.utc(2026, 11, 12);
    final recent = OwnedAlbum(
      id: 'new',
      name: 'New',
      createdAtMillis: now.millisecondsSinceEpoch,
    );
    final old = const OwnedAlbum(id: 'old', name: 'Old', createdAtMillis: 1);
    expect(recent.isRecentAt(now), isTrue);
    expect(old.isRecentAt(now), isFalse);
  });

  test('backup keeps favorite and last opened', () {
    final album = OwnedAlbum(
      id: 'a1',
      name: 'Binders',
      createdAtMillis: 10,
      favorited: true,
      lastOpenedMillis: 20,
    );
    final restored = ownedAlbumFromJson(ownedAlbumToJson(album));
    expect(restored.favorited, isTrue);
    expect(restored.lastOpenedMillis, 20);
  });

  testWidgets('collection filter is All, Recent, Favorite', (tester) async {
    _phoneSurface(tester);
    final now = DateTime.now().millisecondsSinceEpoch;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(
            TestCollectionRepository(
              albums: [
                const OwnedAlbum(id: 'a1', name: 'Binders', createdAtMillis: 1),
                OwnedAlbum(id: 'a2', name: 'Trades', createdAtMillis: now),
              ],
              counts: const {'a1': 3, 'a2': 0},
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => ShellDockScope(child: child!),
          home: const Scaffold(body: CollectionAlbumView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Binders'), findsOneWidget);
    expect(find.text('Trades'), findsOneWidget);
    expect(find.text('New album'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collection-album-filter')));
    await tester.pumpAndSettle();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Favorite'), findsWidgets);
    expect(find.text('With cards'), findsNothing);
    expect(find.text('Empty'), findsNothing);

    final all = tester.getRect(
      find.byKey(const ValueKey('collection-album-filter-all')),
    );
    final favorite = tester.getRect(
      find.byKey(const ValueKey('collection-album-filter-favorite')),
    );
    expect(favorite.height, closeTo(all.height, 1));
    expect(favorite.bottom, lessThanOrEqualTo(900 - 24 + 0.5));

    await tester.tap(
      find.byKey(const ValueKey('collection-album-filter-recent')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trades'), findsOneWidget);
    expect(find.text('Binders', skipOffstage: false), findsNothing);

    await tester.tap(find.byKey(const ValueKey('collection-album-sort')));
    await tester.pumpAndSettle();
    expect(find.text('A–Z'), findsWidgets);
    expect(find.text('Z–A'), findsOneWidget);
    expect(find.text('Cards'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('collection-album-sort-nameAsc')),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('favoriting an album keeps it in the Favorite filter', (
    tester,
  ) async {
    _phoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(
            TestCollectionRepository(
              albums: const [
                OwnedAlbum(id: 'a1', name: 'Binders', createdAtMillis: 1),
                OwnedAlbum(id: 'a2', name: 'Trades', createdAtMillis: 2),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => ShellDockScope(child: child!),
          home: const Scaffold(body: CollectionAlbumView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('collection-album-favorite-a1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('collection-album-filter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('collection-album-filter-favorite')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Binders'), findsOneWidget);
    expect(find.text('Trades', skipOffstage: false), findsNothing);
  });

  testWidgets('collection listing has a star and no overflow menu', (
    tester,
  ) async {
    _phoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(
            TestCollectionRepository(
              albums: const [
                OwnedAlbum(id: 'a1', name: 'Binders', createdAtMillis: 1),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => ShellDockScope(child: child!),
          home: const Scaffold(body: CollectionAlbumView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('collection-album-favorite-a1')),
      findsOneWidget,
    );
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('album page has title star and options for rename and delete', (
    tester,
  ) async {
    _phoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(
            TestCollectionRepository(
              albums: const [
                OwnedAlbum(id: 'a1', name: 'Binders', createdAtMillis: 1),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => ShellDockScope(child: child!),
          home: const OwnedAlbumPage(albumId: 'a1', albumName: 'Binders'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Binders'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('collection-album-title-favorite')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('collection-album-title-favorite')),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collection-album-options')));
    await tester.pumpAndSettle();

    expect(find.text('Rename album'), findsOneWidget);
    expect(find.text('Delete album'), findsOneWidget);
    expect(find.text('Remove favorite'), findsOneWidget);
  });

  testWidgets('album type filter lists every row without cropping the last', (
    tester,
  ) async {
    _phoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        locale: const Locale('en'),
        builder: (context, child) => ShellDockScope(child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AlbumCardBrowser(
              cards: const [
                AlbumListCard(
                  name: 'Sol Ring',
                  count: 1,
                  group: DeckCardGroup.artifact,
                ),
                AlbumListCard(
                  name: 'Forest',
                  count: 1,
                  group: DeckCardGroup.land,
                ),
              ],
              listing: AlbumListing.types,
              onListing: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('album-type-filter')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('album-type-all')), findsOneWidget);
    final land = tester.getRect(find.byKey(const ValueKey('album-type-land')));
    final other = tester.getRect(
      find.byKey(const ValueKey('album-type-other')),
    );
    expect(other.height, closeTo(land.height, 1));
    expect(other.bottom, lessThanOrEqualTo(900 - 24 + 0.5));

    await tester.tap(find.byKey(const ValueKey('album-type-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('album-sort')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('album-sort-nameAsc')), findsOneWidget);
    expect(find.byKey(const ValueKey('album-sort-count')), findsOneWidget);
  });
}
