import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/scryfall_service.dart';
import 'package:mgt_life_spark/features/profile/collection_add_sheet.dart';
import 'package:mgt_life_spark/l10n/app_localizations.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';

import '../support/test_l10n.dart';

Future<void> _tapSolRing(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('album-card-Sol Ring')));
}

class _FakeScryfallService extends ScryfallService {
  _FakeScryfallService() : super(client: null);

  static const solRing = ScryfallCard(
    name: 'Sol Ring',
    typeLine: 'Artifact',
    manaCost: '{1}',
  );

  @override
  Future<List<ScryfallCard>> searchCards(String query) async {
    if (query.toLowerCase().contains('sol')) return [solRing];
    return [];
  }
}

Future<int?> _openSearch(
  WidgetTester tester, {
  required Future<int> Function(String name, int count) onAdd,
  String? Function(ScryfallCard card)? rejectionFor,
}) async {
  int? added;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        scryfallServiceProvider.overrideWithValue(_FakeScryfallService()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: testLocalizationDelegates,
        supportedLocales: testSupportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    added = await Navigator.of(context).push<int>(
                      MaterialPageRoute<int>(
                        builder:
                            (_) => CollectionSearchPage(
                              checkoutLabel: 'Add to album',
                              onAdd: onAdd,
                              rejectionFor: rejectionFor,
                            ),
                      ),
                    );
                  },
                  child: const Text('Open search'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open search'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'sol');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  return added;
}

void main() {
  testWidgets('tap adds to cart without How many dialog', (tester) async {
    final written = <String, int>{};
    await _openSearch(
      tester,
      onAdd: (name, count) async {
        written[name] = count;
        return count;
      },
    );

    expect(find.byKey(const ValueKey('album-card-Sol Ring')), findsOneWidget);
    await _tapSolRing(tester);
    await tester.pump();

    expect(find.text('How many?'), findsNothing);
    expect(written, isEmpty);
    expect(find.text('List · 1'), findsOneWidget);
    expect(find.text('Add to album'), findsOneWidget);
  });

  testWidgets('checkout stays down when the keyboard opens', (tester) async {
    await _openSearch(tester, onAdd: (name, count) async => count);
    await _tapSolRing(tester);
    await tester.pump();

    final before = tester.getBottomLeft(find.text('Add to album')).dy;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(
      tester.getBottomLeft(find.text('Add to album')).dy,
      closeTo(before, 0.5),
    );
  });

  testWidgets('checkout writes the whole cart at once', (tester) async {
    final written = <String, int>{};
    int? addedCount;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scryfallServiceProvider.overrideWithValue(_FakeScryfallService()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      addedCount = await Navigator.of(context).push<int>(
                        MaterialPageRoute<int>(
                          builder:
                              (_) => CollectionSearchPage(
                                checkoutLabel: 'Add to album',
                                onAdd: (name, count) async {
                                  written[name] = count;
                                  return count;
                                },
                              ),
                        ),
                      );
                    },
                    child: const Text('Open search'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sol');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    await _tapSolRing(tester);
    await tester.pump();
    await _tapSolRing(tester);
    await tester.pump();
    expect(find.text('List · 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('card-cart-checkout')));
    await tester.pumpAndSettle();

    expect(written, {'Sol Ring': 2});
    expect(addedCount, 2);
    expect(find.text('Open search'), findsOneWidget);
  });

  testWidgets('rejected cards never enter the cart', (tester) async {
    final written = <String, int>{};
    await _openSearch(
      tester,
      onAdd: (name, count) async {
        written[name] = count;
        return count;
      },
      rejectionFor: (_) => 'Off color',
    );

    await _tapSolRing(tester);
    await tester.pump();

    expect(find.text('Off color'), findsOneWidget);
    expect(find.text('List · 1'), findsNothing);
    expect(written, isEmpty);
  });

  testWidgets('minus removes a copy from the cart', (tester) async {
    await _openSearch(tester, onAdd: (name, count) async => count);

    await _tapSolRing(tester);
    await tester.pump();
    await _tapSolRing(tester);
    await tester.pump();
    expect(find.text('List · 2'), findsOneWidget);

    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.deckAlbumViewTypes));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove a copy'));
    await tester.pump();
    expect(find.text('List · 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove a copy'));
    await tester.pump();
    expect(find.text('List · 1'), findsNothing);
  });

  testWidgets('opening the cart does not overflow', (tester) async {
    await _openSearch(tester, onAdd: (name, count) async => count);

    await _tapSolRing(tester);
    await tester.pump();
    await tester.tap(find.text('List · 1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('List'), findsWidgets);
    expect(find.text('Sol Ring'), findsWidgets);
  });

  testWidgets('partial checkout keeps leftover copies in the cart', (
    tester,
  ) async {
    await _openSearch(tester, onAdd: (name, count) async => count > 1 ? 1 : 0);

    await _tapSolRing(tester);
    await tester.pump();
    await _tapSolRing(tester);
    await tester.pump();
    expect(find.text('List · 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('card-cart-checkout')));
    await tester.pumpAndSettle();

    expect(find.text('List · 1'), findsOneWidget);
    expect(
      find.text('Added 1. Some cards could not be added.'),
      findsOneWidget,
    );
  });

  testWidgets('leave with a cart asks before discarding', (tester) async {
    await _openSearch(tester, onAdd: (name, count) async => count);

    await _tapSolRing(tester);
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Leave without adding?'), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Open search'), findsOneWidget);
  });

  testWidgets('search listing has types, grid, and A-Z', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _openSearch(tester, onAdd: (name, count) async => count);

    expect(find.text(l10n.deckAlbumViewGrid), findsOneWidget);
    expect(find.text(l10n.deckAlbumViewTypes), findsOneWidget);
    expect(find.text(l10n.deckAlbumViewAlpha), findsOneWidget);

    await tester.tap(find.text(l10n.deckAlbumViewTypes));
    await tester.pump();
    expect(find.text('Sol Ring'), findsOneWidget);
    expect(find.text(l10n.deckAlbumArtifacts), findsOneWidget);

    await tester.tap(find.text(l10n.deckAlbumViewAlpha));
    await tester.pump();
    expect(find.text('Sol Ring'), findsOneWidget);
  });
}
