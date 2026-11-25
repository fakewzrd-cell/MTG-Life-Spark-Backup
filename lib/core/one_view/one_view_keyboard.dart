import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the Android window from resizing while the One View table is open.
///
/// `adjustResize` shrinks the Flutter view when the keyboard opens, so the
/// seats reflow even when the scaffold ignores [MediaQuery.viewInsets].
/// Dialogs still lift: Flutter reports the keyboard as an inset either way.
abstract final class OneViewKeyboardLayout {
  static const _channel = MethodChannel('app.lifespark.mtg/keyboard');
  static int _holds = 0;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> hold() async {
    if (!_android) return;
    _holds += 1;
    if (_holds > 1) return;
    try {
      await _channel.invokeMethod<void>('holdLayout');
    } catch (_) {
      _holds = (_holds - 1).clamp(0, 1 << 30);
    }
  }

  static Future<void> release() async {
    if (!_android) return;
    if (_holds == 0) return;
    _holds -= 1;
    if (_holds > 0) return;
    try {
      await _channel.invokeMethod<void>('releaseLayout');
    } catch (_) {}
  }
}
