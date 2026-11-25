import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui/theme/app_system_ui.dart';

/// One View table orientation policy.
///
/// Phones: lock to landscape (table sits in the middle).
/// Large screens (tablets / folds ≥ [kLargeScreenOrientationBreakpoint]):
/// prefer landscape but leave unlocked — Android may ignore locks there.
abstract final class OneViewOrientation {
  static bool isLargeScreen(Size size) =>
      size.shortestSide >= kLargeScreenOrientationBreakpoint;

  static bool isPortrait(Size size) => size.height > size.width;

  /// Apply while the One View table is open.
  static Future<void> lockForTable(Size size) {
    if (isLargeScreen(size)) {
      // Prefer landscape; empty list = unrestricted (OS may ignore locks).
      return SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    return SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// Restore app-wide phone-portrait / large-screen unrestricted policy.
  static Future<void> restoreAppDefault() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) {
      return SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
    final logicalWidth = view.display.size.width / view.display.devicePixelRatio;
    return SystemChrome.setPreferredOrientations(
      preferredOrientationsForLogicalWidth(logicalWidth),
    );
  }
}
