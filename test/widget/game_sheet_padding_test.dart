import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/features/game/widgets/game_modal_chrome.dart';

void main() {
  test('keyboard skips shell dock padding so sheets do not overflow ~77px', () {
    expect(
      gameSheetPaddingBottom(
        viewInsetsBottom: 320,
        paddingBottom: 24,
        shellDock: 96,
      ),
      0,
    );
  });

  test('closed keyboard uses the larger of padding and dock', () {
    expect(
      gameSheetPaddingBottom(
        viewInsetsBottom: 0,
        paddingBottom: 24,
        shellDock: 96,
      ),
      96,
    );
    expect(
      gameSheetPaddingBottom(
        viewInsetsBottom: 0,
        paddingBottom: 120,
        shellDock: 96,
      ),
      120,
    );
  });

  test('in-game sheets with no dock keep their padding', () {
    expect(
      gameSheetPaddingBottom(
        viewInsetsBottom: 0,
        paddingBottom: 24,
        shellDock: 0,
      ),
      24,
    );
  });
}
