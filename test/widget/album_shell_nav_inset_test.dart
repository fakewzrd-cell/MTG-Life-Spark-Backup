import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/features/game/widgets/game_modal_chrome.dart';
import 'package:mgt_life_spark/features/profile/album_listing.dart';
import 'package:mgt_life_spark/shared/theme/app_theme.dart';
import 'package:mgt_life_spark/ui/tokens/layout_tokens.dart';

void main() {
  testWidgets('album action height includes the shell dock', (tester) async {
    late double withDock;
    late double withoutDock;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          extendBody: true,
          body: Builder(
            builder: (context) {
              withDock = BlurredBottomAction.height(
                context,
                aboveShellDock: true,
              );
              withoutDock = BlurredBottomAction.height(context);
              return const SizedBox.expand();
            },
          ),
          bottomNavigationBar: const SizedBox(
            height: LayoutTokens.bottomNavHeight,
            child: ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );

    expect(
      withDock,
      greaterThanOrEqualTo(
        BlurredBottomAction.buttonHeight + LayoutTokens.bottomNavHeight,
      ),
    );
    expect(withDock, greaterThan(withoutDock));
  });

  testWidgets('shell dock inset is at least the nav bar height', (
    tester,
  ) async {
    late double inset;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: Builder(
            builder: (context) {
              inset = LayoutTokens.shellDockInset(context);
              return const SizedBox.expand();
            },
          ),
          bottomNavigationBar: const SizedBox(
            height: LayoutTokens.bottomNavHeight,
            child: ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );
    expect(inset, greaterThanOrEqualTo(LayoutTokens.bottomNavHeight));
  });

  testWidgets('root sheets pad for the shell dock only under the shell', (
    tester,
  ) async {
    late double withScope;
    late double withoutScope;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (outside) {
            withoutScope = shellDockPaddingForSheet(outside);
            return ShellDockScope(
              child: Builder(
                builder: (inside) {
                  withScope = shellDockPaddingForSheet(inside);
                  return const SizedBox.expand();
                },
              ),
            );
          },
        ),
      ),
    );
    expect(withoutScope, 0);
    expect(withScope, greaterThanOrEqualTo(LayoutTokens.bottomNavHeight));
  });
}
