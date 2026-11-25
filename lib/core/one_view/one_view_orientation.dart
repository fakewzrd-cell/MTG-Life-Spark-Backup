import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui/theme/app_system_ui.dart';

/// One View table orientation policy.
///
/// While the table is open, the phone may rotate. The sitting layout chosen
/// in the menu does not change with that rotation. Leaving the table restores
/// the app-wide orientation policy.
abstract final class OneViewOrientation {
  static bool _tableActive = false;

  static bool get tableIsActive => _tableActive;

  static bool isLargeScreen(Size size) =>
      size.shortestSide >= kLargeScreenOrientationBreakpoint;

  static bool isPortrait(Size size) => size.height > size.width;

  /// Apply while the One View table is open — allow every orientation.
  ///
  /// Safe to call on every metrics change. Repeating it puts landscape back
  /// if another policy locked the phone to portrait.
  static Future<void> lockForTable(Size size) {
    // Size is unused but kept so callers (metrics) stay stable.
    _tableActive = true;
    AppOrientationOverride.hold();
    return SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  /// Restore app-wide phone-portrait / large-screen unrestricted policy.
  static Future<void> restoreAppDefault() {
    _tableActive = false;
    AppOrientationOverride.release();
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) {
      return SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
    final logicalWidth =
        view.display.size.width / view.display.devicePixelRatio;
    return SystemChrome.setPreferredOrientations(
      preferredOrientationsForLogicalWidth(logicalWidth),
    );
  }
}
