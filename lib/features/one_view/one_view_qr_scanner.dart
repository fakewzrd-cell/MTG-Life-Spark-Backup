import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import 'one_view_chrome.dart';

/// Shared framing and feedback for profile and XP claim scans.
class OneViewQrScanner<T> extends StatefulWidget {
  const OneViewQrScanner({
    super.key,
    required this.title,
    required this.hint,
    required this.invalidMessage,
    required this.parse,
  });
  final String title;
  final String hint;
  final String invalidMessage;
  final T? Function(String) parse;

  @override
  State<OneViewQrScanner<T>> createState() => _OneViewQrScannerState<T>();
}

class _OneViewQrScannerState<T> extends State<OneViewQrScanner<T>> {
  bool _handled = false;
  String? _invalid;

  void _detect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final result = widget.parse(raw);
      if (result != null) {
        _handled = true;
        Navigator.pop(context, result);
        return;
      }
    }
    if (_invalid == null && capture.barcodes.any((b) => b.rawValue != null)) {
      setState(() => _invalid = widget.invalidMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: OneViewChrome.dialogTitleStyle(context),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.min(
              260.0,
              constraints.biggest.shortestSide * 0.65,
            );
            final frame = Rect.fromCenter(
              center: Offset(
                constraints.maxWidth / 2,
                constraints.maxHeight / 2,
              ),
              width: side,
              height: side,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  scanWindow: frame,
                  onDetect: _detect,
                  errorBuilder:
                      (_, __) => ColoredBox(
                        color: colors.backgroundPrimary,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              l10n.oneViewCameraUnavailable,
                              textAlign: TextAlign.center,
                              style: OneViewChrome.dialogBodyStyle(context),
                            ),
                          ),
                        ),
                      ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: side,
                      height: side,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 24,
                  right: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _invalid ?? widget.hint,
                        semanticsLabel: _invalid ?? widget.hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
