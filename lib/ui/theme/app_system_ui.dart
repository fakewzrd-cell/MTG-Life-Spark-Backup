import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_color_tokens.dart';

const double kLargeScreenOrientationBreakpoint = 600;

/// Phones stay portrait for table readability. Android 16 ignores orientation
/// locks on large screens, so tablets, foldables, and desktop windows are left
/// unrestricted and must use the app's responsive layouts.
List<DeviceOrientation> preferredOrientationsForLogicalWidth(double width) {
  if (width >= kLargeScreenOrientationBreakpoint) {
    return const <DeviceOrientation>[];
  }
  return const <DeviceOrientation>[DeviceOrientation.portraitUp];
}

/// Set while a screen, such as the One View table, allows every orientation.
///
/// A phone in landscape is wider than [kLargeScreenOrientationBreakpoint], so
/// the app-wide rule would treat that turn as a tablet and then lock portrait
/// on the way back. [held] keeps that rule from running until the screen
/// restores the default itself.
abstract final class AppOrientationOverride {
  static bool _held = false;

  static bool get held => _held;

  static void hold() => _held = true;

  static void release() => _held = false;
}

/// Whether a size change should reapply the app-wide portrait lock.
///
/// [wasLargeScreen] is the last size class this rule saw. The first call
/// passes null and applies once.
bool shouldApplyAppOrientationLock({
  required bool orientationHeld,
  required bool? wasLargeScreen,
  required bool isLargeScreen,
}) {
  if (orientationHeld) return false;
  return wasLargeScreen != isLargeScreen;
}

/// System status / navigation bar styling aligned with app chrome.
abstract final class AppSystemUi {
  static Future<void> bootstrap() async {
    if (kIsWeb) return;
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) {
      await _applyOrientationForView(view);
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  static Future<void> _applyOrientationForView(ui.FlutterView view) {
    final display = view.display;
    final logicalWidth = display.size.width / display.devicePixelRatio;
    return SystemChrome.setPreferredOrientations(
      preferredOrientationsForLogicalWidth(logicalWidth),
    );
  }

  static SystemUiOverlayStyle overlayStyle(
    BuildContext context, {
    bool matchBottomNav = false,
  }) {
    final colors = AppColorTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Dock nav uses backgroundPrimary @ 78% over the same scaffold tone.
    final navBarColor =
        matchBottomNav
            ? Color.alphaBlend(
              colors.backgroundPrimary.withValues(alpha: 0.78),
              colors.backgroundPrimary,
            )
            : colors.backgroundPrimary;

    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: navBarColor,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarDividerColor: colors.borderSubtle.withValues(
        alpha: 0.22,
      ),
    );
  }
}

/// Reapplies orientation policy when a fold, rotation, or window resize changes
/// the display dimensions.
class AppAdaptiveOrientationScope extends StatefulWidget {
  const AppAdaptiveOrientationScope({super.key, required this.child});

  final Widget child;

  @override
  State<AppAdaptiveOrientationScope> createState() =>
      _AppAdaptiveOrientationScopeState();
}

class _AppAdaptiveOrientationScopeState
    extends State<AppAdaptiveOrientationScope>
    with WidgetsBindingObserver {
  bool? _wasLargeScreen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyOrientation();
  }

  @override
  void didChangeMetrics() {
    _applyOrientation();
  }

  void _applyOrientation() {
    if (kIsWeb || !mounted) return;
    final display = View.of(context).display;
    final logicalWidth = display.size.width / display.devicePixelRatio;
    final isLargeScreen = logicalWidth >= kLargeScreenOrientationBreakpoint;
    final apply = shouldApplyAppOrientationLock(
      orientationHeld: AppOrientationOverride.held,
      wasLargeScreen: _wasLargeScreen,
      isLargeScreen: isLargeScreen,
    );
    _wasLargeScreen = isLargeScreen;
    if (!apply) return;
    unawaited(
      SystemChrome.setPreferredOrientations(
        preferredOrientationsForLogicalWidth(logicalWidth),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Applies [AppSystemUi.overlayStyle] to a subtree (status + navigation bar).
///
/// Uses Flutter [SystemUiOverlayStyle] — not the deprecated Android XML
/// `android:navigationBarColor` / `android:statusBarColor` window attrs.
class AppSystemUiScope extends StatelessWidget {
  const AppSystemUiScope({
    super.key,
    required this.child,
    this.matchBottomNav = false,
  });

  final Widget child;
  final bool matchBottomNav;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUi.overlayStyle(context, matchBottomNav: matchBottomNav),
      child: child,
    );
  }
}
