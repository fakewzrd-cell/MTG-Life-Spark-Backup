import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgt_life_spark/core/one_view/one_view_orientation.dart';
import 'package:mgt_life_spark/ui/theme/app_system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('phones are not large screens; tablets at breakpoint are', () {
    expect(OneViewOrientation.isLargeScreen(const Size(390, 844)), isFalse);
    expect(
      OneViewOrientation.isLargeScreen(
        const Size(kLargeScreenOrientationBreakpoint, 1024),
      ),
      isTrue,
    );
  });

  test('portrait detection uses height > width', () {
    expect(OneViewOrientation.isPortrait(const Size(390, 844)), isTrue);
    expect(OneViewOrientation.isPortrait(const Size(844, 390)), isFalse);
  });

  test('lockForTable is idempotent (safe to call from metrics)', () async {
    await OneViewOrientation.restoreAppDefault();
    await OneViewOrientation.lockForTable(const Size(844, 390));
    await OneViewOrientation.lockForTable(const Size(390, 844));
    await OneViewOrientation.restoreAppDefault();
  });

  test('the table keeps landscape available until it closes', () async {
    addTearDown(OneViewOrientation.restoreAppDefault);
    await OneViewOrientation.restoreAppDefault();
    expect(OneViewOrientation.tableIsActive, isFalse);
    expect(AppOrientationOverride.held, isFalse);

    await OneViewOrientation.lockForTable(const Size(844, 390));
    expect(OneViewOrientation.tableIsActive, isTrue);
    expect(AppOrientationOverride.held, isTrue);

    await OneViewOrientation.lockForTable(const Size(390, 844));
    expect(AppOrientationOverride.held, isTrue);

    await OneViewOrientation.restoreAppDefault();
    expect(OneViewOrientation.tableIsActive, isFalse);
    expect(AppOrientationOverride.held, isFalse);
  });
}
