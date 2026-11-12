import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/game/game_format.dart';
import 'package:mgt_life_spark/core/models/deck_style.dart';
import 'package:mgt_life_spark/core/models/player_deck.dart';
import 'package:mgt_life_spark/core/persistence/providers.dart';
import 'package:mgt_life_spark/features/profile/deck_options_sheet.dart';
import 'package:mgt_life_spark/features/profile/decks_manage_screen.dart';
import 'package:mgt_life_spark/features/settings/settings_screen.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';
import 'package:mgt_life_spark/ui/theme/app_color_tokens.dart';
import 'package:mgt_life_spark/ui/tokens/layout_tokens.dart';

import 'support/test_deck_repository.dart';
import 'support/test_l10n.dart';
import 'support/test_settings_repository.dart';

PlayerDeck _testDeck({String name = 'Test Deck'}) => PlayerDeck(
  id: 'deck-1',
  displayName: name,
  commanderName: 'Atraxa, Praetors\' Voice',
  format: GameFormat.commander.name,
  deckStyleId: 'control',
);

void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('decks manage shows empty-state copy when no decks', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(TestDeckRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const DecksManageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build your deck library'), findsOneWidget);
    expect(find.text('Add deck'), findsOneWidget);
  });

  testWidgets('add deck button stays down when the keyboard opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(TestDeckRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const DecksManageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = tester.getBottomLeft(find.text('Add deck')).dy;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    expect(
      tester.getBottomLeft(find.text('Add deck')).dy,
      closeTo(before, 0.5),
    );
  });

  testWidgets('new deck sheet does not overflow when the keyboard opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 80);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(TestDeckRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => ShellDockScope(child: child!),
          home: const DecksManageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add deck'));
    await tester.pumpAndSettle();
    expect(find.text('Deck name'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Raffine Tempo');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Raffine Tempo'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('format picker does not overflow when the keyboard opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 80);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(
            TestDeckRepository(decks: [_testDeck()]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => ShellDockScope(child: child!),
          home: const DecksManageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('library-format-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Search formats…'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      ),
      'stan',
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Standard'), findsOneWidget);
  });

  testWidgets('decks manage filters which deck to open', (tester) async {
    _phoneSurface(tester);
    final commander = PlayerDeck(
      id: 'edh-1',
      displayName: 'Atraxa Counters',
      commanderName: 'Atraxa, Praetors\' Voice',
      format: GameFormat.commander.name,
      deckStyleId: 'control',
    );
    final standard = PlayerDeck(
      id: 'std-1',
      displayName: 'Azorius Tempo',
      commanderName: 'Teferi, Hero of Dominaria',
      format: GameFormat.standard.name,
      deckStyleId: 'control',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(
            TestDeckRepository(decks: [commander, standard]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const DecksManageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Format'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Bracket'), findsOneWidget);
    final formatY = tester.getTopLeft(find.text('Format')).dy;
    final styleY = tester.getTopLeft(find.text('Style')).dy;
    final bracketY = tester.getTopLeft(find.text('Bracket')).dy;
    expect(formatY, lessThan(styleY));
    expect(styleY, closeTo(bracketY, 0.5));
    expect(find.text('Azorius Tempo'), findsOneWidget);
    expect(find.text('Atraxa Counters', skipOffstage: false), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-format-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deck-format-standard')));
    await tester.pumpAndSettle();

    expect(find.text('Azorius Tempo'), findsOneWidget);
    expect(find.text('Atraxa Counters', skipOffstage: false), findsNothing);

    await tester.tap(find.byKey(const ValueKey('library-format-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deck-format-filter-all')));
    await tester.pumpAndSettle();

    expect(find.text('Azorius Tempo'), findsOneWidget);
    expect(find.text('Atraxa Counters', skipOffstage: false), findsOneWidget);
  });

  testWidgets('style filter All restores decks after Battlecruiser', (
    tester,
  ) async {
    _phoneSurface(tester);
    final battlecruiser = PlayerDeck(
      id: 'bc-1',
      displayName: 'Big Mana',
      commanderName: 'Ghalta, Stampede Tyrant',
      format: GameFormat.commander.name,
      deckStyleId: DeckStyle.battlecruiser.id,
    );
    final control = PlayerDeck(
      id: 'ctrl-1',
      displayName: 'Counterspell',
      commanderName: 'Talrand, Sky Summoner',
      format: GameFormat.commander.name,
      deckStyleId: DeckStyle.control.id,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(
            TestDeckRepository(decks: [battlecruiser, control]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const DecksManageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Big Mana'), findsOneWidget);
    expect(find.text('Counterspell'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-style-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deck-style-battlecruiser')));
    await tester.pumpAndSettle();

    expect(find.text('Big Mana'), findsOneWidget);
    expect(find.text('Counterspell', skipOffstage: false), findsNothing);

    await tester.tap(find.byKey(const ValueKey('library-style-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deck-style-filter-all')));
    await tester.pumpAndSettle();

    expect(find.text('Big Mana'), findsOneWidget);
    expect(find.text('Counterspell'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
  });

  testWidgets('bracket filter All restores decks after a level', (
    tester,
  ) async {
    _phoneSurface(tester);
    final bracketed = PlayerDeck(
      id: 'b3-1',
      displayName: 'Daredevil',
      commanderName: 'Daredevil, Man Without Fear',
      format: GameFormat.commander.name,
      deckStyleId: DeckStyle.counters.id,
      chosenBracket: 3,
    );
    final unset = PlayerDeck(
      id: 'nb-1',
      displayName: 'Cloud',
      commanderName: 'Cloud, Ex-SOLDIER',
      format: GameFormat.commander.name,
      deckStyleId: DeckStyle.voltron.id,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(
            TestDeckRepository(decks: [bracketed, unset]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const DecksManageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daredevil'), findsOneWidget);
    expect(find.text('Cloud'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-bracket-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deck-bracket-3')));
    await tester.pumpAndSettle();

    expect(find.text('Daredevil'), findsOneWidget);
    expect(find.text('Cloud', skipOffstage: false), findsNothing);

    await tester.tap(find.byKey(const ValueKey('library-bracket-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deck-bracket-filter-all')));
    await tester.pumpAndSettle();

    expect(find.text('Daredevil'), findsOneWidget);
    expect(find.text('Cloud'), findsOneWidget);
    expect(find.text('Bracket'), findsOneWidget);
  });

  testWidgets('bracket filter lists every row without cropping the last', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 80);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(
            TestDeckRepository(decks: [_testDeck()]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => ShellDockScope(child: child!),
          home: const DecksManageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('library-bracket-filter')));
    await tester.pumpAndSettle();

    final fourth = tester.getRect(find.byKey(const ValueKey('deck-bracket-4')));
    final fifth = tester.getRect(find.byKey(const ValueKey('deck-bracket-5')));
    expect(fifth.height, closeTo(fourth.height, 1));
    expect(fifth.bottom, lessThanOrEqualTo(900 - 24 + 0.5));

    await tester.tap(find.byKey(const ValueKey('deck-bracket-filter-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-format-filter')));
    await tester.pumpAndSettle();

    final vintage = tester.getRect(
      find.byKey(const ValueKey('deck-format-vintage')),
    );
    final commander = tester.getRect(
      find.byKey(const ValueKey('deck-format-commander')),
    );
    expect(commander.height, closeTo(vintage.height, 1));
  });

  testWidgets('clear filters restores decks when nothing matches', (
    tester,
  ) async {
    _phoneSurface(tester);
    final control = PlayerDeck(
      id: 'ctrl-1',
      displayName: 'Counterspell',
      commanderName: 'Talrand, Sky Summoner',
      format: GameFormat.commander.name,
      deckStyleId: DeckStyle.control.id,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(
            TestDeckRepository(decks: [control]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const DecksManageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Counterspell'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-style-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deck-style-battlecruiser')));
    await tester.pumpAndSettle();

    expect(find.text('Counterspell', skipOffstage: false), findsNothing);
    expect(find.text('No decks match these filters.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-clear-filters')));
    await tester.pumpAndSettle();

    expect(find.text('Counterspell'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
  });

  testWidgets('deck options sheet lists actions', (tester) async {
    final deck = _testDeck();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deckRepositoryProvider.overrideWithValue(TestDeckRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showDeckDetailSheet(context, deck),
                      child: const Text('Open options'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open options'));
    await tester.pumpAndSettle();

    expect(find.text('Change style'), findsOneWidget);
    expect(find.text('Edit commanders'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete deck'), findsOneWidget);
    expect(find.text('Pin to top'), findsNothing);
    expect(find.text('Change format'), findsOneWidget);
  });

  testWidgets('settings default format opens picker dialog', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            TestSettingsRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Default Format'));
    await tester.pumpAndSettle();

    expect(find.text('Default format'), findsOneWidget);
    expect(find.text('Standard'), findsWidgets);
    expect(find.text('Commander'), findsWidgets);

    final sheetContext = tester.element(find.text('Default format'));
    final colors = AppColorTokens.of(sheetContext);
    expect(colors.textPrimary, isNotNull);
  });

  testWidgets('settings screen renders gameplay section', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            TestSettingsRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: testLocalizationDelegates,
          supportedLocales: testSupportedLocales,
          locale: const Locale('en'),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Default Format'), findsOneWidget);
    expect(find.text('Keep display awake'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Language'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Language'), findsOneWidget);
  });
}
