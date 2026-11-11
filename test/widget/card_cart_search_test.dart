import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/scryfall_service.dart';
import 'package:mgt_life_spark/features/profile/collection_add_sheet.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';

import '../support/test_l10n.dart';

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

    expect(find.text('Sol Ring'), findsOneWidget);
    await tester.tap(find.text('Sol Ring'));
    await tester.pump();

    expect(find.text('How many?'), findsNothing);
    expect(written, isEmpty);
    expect(find.text('Cart · 1'), findsOneWidget);
    expect(find.text('Add to album'), findsOneWidget);
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

    await tester.tap(find.text('Sol Ring'));
    await tester.pump();
    await tester.tap(find.text('Sol Ring'));
    await tester.pump();
    expect(find.text('Cart · 2'), findsOneWidget);

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

    await tester.tap(find.text('Sol Ring'));
    await tester.pump();

    expect(find.text('Off color'), findsOneWidget);
    expect(find.text('Cart · 1'), findsNothing);
    expect(written, isEmpty);
  });

  testWidgets('minus removes a copy from the cart', (tester) async {
    await _openSearch(tester, onAdd: (name, count) async => count);

    await tester.tap(find.text('Sol Ring'));
    await tester.pump();
    await tester.tap(find.text('Sol Ring'));
    await tester.pump();
    expect(find.text('Cart · 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove one'));
    await tester.pump();
    expect(find.text('Cart · 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove one'));
    await tester.pump();
    expect(find.text('Cart · 1'), findsNothing);
  });

  testWidgets('opening the cart does not overflow', (tester) async {
    await _openSearch(tester, onAdd: (name, count) async => count);

    await tester.tap(find.text('Sol Ring'));
    await tester.pump();
    await tester.tap(find.text('Cart · 1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cart'), findsWidgets);
    expect(find.text('Sol Ring'), findsWidgets);
  });

  testWidgets('partial checkout keeps leftover copies in the cart', (
    tester,
  ) async {
    await _openSearch(tester, onAdd: (name, count) async => count > 1 ? 1 : 0);

    await tester.tap(find.text('Sol Ring'));
    await tester.pump();
    await tester.tap(find.text('Sol Ring'));
    await tester.pump();
    expect(find.text('Cart · 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('card-cart-checkout')));
    await tester.pumpAndSettle();

    expect(find.text('Cart · 1'), findsOneWidget);
    expect(
      find.text('Added 1. Some cards could not be added.'),
      findsOneWidget,
    );
  });

  testWidgets('leave with a cart asks before discarding', (tester) async {
    await _openSearch(tester, onAdd: (name, count) async => count);

    await tester.tap(find.text('Sol Ring'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Leave without adding?'), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Open search'), findsOneWidget);
  });
}
