import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/game/scryfall_service.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';

/// Opens the card large enough to inspect, tilted by dragging.
///
/// Double-faced cards also spin on Y so the other printed face can be read.
/// [note] and [onAction] are used by suggested cards, which explain the
/// inclusion rate and add the card from the viewer.
Future<void> showAlbumCardViewer(
  BuildContext context, {
  required String name,
  String? imageUrl,
  String? backImageUrl,
  String? note,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context).commonClose,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder:
        (context, _, __) => _CardViewerPage(
          name: name,
          imageUrl: imageUrl,
          backImageUrl: backImageUrl,
          note: note,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _CardViewerPage extends StatelessWidget {
  const _CardViewerPage({
    required this.name,
    required this.imageUrl,
    this.backImageUrl,
    this.note,
    this.actionLabel,
    this.onAction,
  });

  final String name;
  final String? imageUrl;
  final String? backImageUrl;
  final String? note;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hasBack = backImageUrl != null && backImageUrl!.trim().isNotEmpty;
    final maxHeight = size.height * (hasBack ? 0.66 : 0.74);
    final maxWidth = size.width - 72;
    var width = maxWidth;
    var height = width * 88 / 63;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * 63 / 88;
    }

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TiltingCard(
                name: name,
                imageUrl: imageUrl,
                backImageUrl: backImageUrl,
                width: width,
                height: height,
              ),
              if (note != null && note!.isNotEmpty) ...[
                SizedBox(height: LayoutTokens.gr3),
                SizedBox(
                  width: width,
                  child: Text(
                    note!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: FontTokens.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (onAction != null && actionLabel != null) ...[
                SizedBox(height: LayoutTokens.gr3),
                SizedBox(
                  width: width,
                  child: UiButton(
                    label: actionLabel!,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onAction!();
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TiltingCard extends StatefulWidget {
  const _TiltingCard({
    required this.name,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.backImageUrl,
  });

  final String name;
  final String? imageUrl;
  final String? backImageUrl;
  final double width;
  final double height;

  bool get canFlip {
    final back = backImageUrl?.trim();
    return back != null && back.isNotEmpty;
  }

  @override
  State<_TiltingCard> createState() => _TiltingCardState();
}

class _TiltingCardState extends State<_TiltingCard>
    with TickerProviderStateMixin {
  Offset _tilt = Offset.zero;
  Offset _released = Offset.zero;
  double _spin = 0;
  double _spinFrom = 0;
  double _spinTo = 0;
  bool _precacheScheduled = false;
  late final AnimationController _settle;
  late final AnimationController _spinSnap;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..addListener(() {
      final t = Curves.easeOutCubic.transform(_settle.value);
      setState(() {
        _tilt = Offset.lerp(_released, Offset.zero, t)!;
      });
    });
    _spinSnap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(() {
      final t = Curves.easeInOutCubic.transform(_spinSnap.value);
      setState(() {
        _spin = _spinFrom + (_spinTo - _spinFrom) * t;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precacheScheduled) return;
    _precacheScheduled = true;
    _precache(widget.imageUrl);
    _precache(widget.backImageUrl);
  }

  void _precache(String? url) {
    if (url == null || url.isEmpty) return;
    precacheImage(CachedNetworkImageProvider(url), context);
  }

  @override
  void dispose() {
    _settle.dispose();
    _spinSnap.dispose();
    super.dispose();
  }

  Offset _tiltFromLocal(Offset local) {
    final nx = ((local.dx / widget.width) * 2 - 1).clamp(-1.0, 1.0);
    final ny = ((local.dy / widget.height) * 2 - 1).clamp(-1.0, 1.0);
    return Offset(nx, ny);
  }

  void _release() {
    _released = _tilt;
    _settle.forward(from: 0);
    if (widget.canFlip) _snapSpin();
  }

  void _snapSpin() {
    _spinSnap.stop();
    final n = _normalizedSpin(_spin);
    _spinFrom = n;
    _spinTo = snapAlbumCardSpin(n);
    if ((_spinTo - _spinFrom).abs() < 0.001) {
      _spin = _spinTo == 2 * math.pi ? 0 : _spinTo;
      return;
    }
    _spinSnap.forward(from: 0);
  }

  void _flip() {
    if (!widget.canFlip) return;
    _settle.stop();
    _spinSnap.stop();
    final n = _normalizedSpin(_spin);
    _spinFrom = n;
    _spinTo = n + math.pi;
    _spinSnap.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    const maxTilt = 0.42;
    final showingBack = math.cos(_spin) < 0;
    final transform =
        Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateX(-_tilt.dy * maxTilt)
          ..rotateY(widget.canFlip ? _spin : _tilt.dx * maxTilt);

    final front = ClipRRect(
      borderRadius: BorderRadius.circular(RadiusTokens.md),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: _CardFace(
          name: scryfallFrontName(widget.name),
          imageUrl: widget.imageUrl,
          colors: colors,
        ),
      ),
    );
    final back = Transform(
      alignment: Alignment.center,
      transform: Matrix4.rotationY(math.pi),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RadiusTokens.md),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: _CardFace(
            name: scryfallBackName(widget.name),
            imageUrl: widget.backImageUrl,
            colors: colors,
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {},
          onDoubleTap: widget.canFlip ? _flip : null,
          onPanStart: (details) {
            _settle.stop();
            _spinSnap.stop();
            setState(() => _tilt = _tiltFromLocal(details.localPosition));
          },
          onPanUpdate: (details) {
            setState(() {
              if (widget.canFlip) {
                _spin += details.delta.dx * (math.pi / (widget.width * 0.72));
              }
              _tilt = _tiltFromLocal(details.localPosition);
            });
          },
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: Transform(
            alignment: Alignment.center,
            transform: transform,
            child: Stack(
              children: [
                if (!widget.canFlip)
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.translationValues(0, 0, -12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161616),
                        borderRadius: BorderRadius.circular(RadiusTokens.md),
                        border: Border.all(color: const Color(0xFF3A3A3A)),
                      ),
                      child: SizedBox(
                        width: widget.width,
                        height: widget.height,
                      ),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(RadiusTokens.md),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: Offset(-_tilt.dx * 16, _tilt.dy * 18 + 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Offstage(offstage: showingBack, child: front),
                      Offstage(offstage: !showingBack, child: back),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(RadiusTokens.md),
                        gradient: LinearGradient(
                          begin: Alignment(
                            -(_tilt.dx == 0 ? 0.15 : _tilt.dx),
                            -(_tilt.dy == 0 ? 1.0 : _tilt.dy),
                          ),
                          end: Alignment(
                            _tilt.dx == 0 ? 0.15 : _tilt.dx,
                            _tilt.dy == 0 ? 1.0 : _tilt.dy,
                          ),
                          colors: [
                            Colors.white.withValues(alpha: 0.18),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.canFlip) ...[
          SizedBox(height: LayoutTokens.gr3),
          TextButton.icon(
            onPressed: _flip,
            icon: const Icon(Icons.flip_rounded, color: Colors.white),
            label: Text(
              l10n.cardViewerFlip,
              style: TextStyle(
                color: Colors.white,
                fontSize: FontTokens.body,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.name,
    required this.imageUrl,
    required this.colors,
  });

  final String name;
  final String? imageUrl;
  final AppColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _namePlate();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => _namePlate(),
      errorWidget: (_, __, ___) => _namePlate(),
    );
  }

  Widget _namePlate() {
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: FontTokens.title,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

double _normalizedSpin(double spin) {
  final twoPi = 2 * math.pi;
  var n = spin % twoPi;
  if (n < 0) n += twoPi;
  if (n > twoPi - 1e-9) return 0;
  return n;
}

/// Nearest face after a drag: 0 (front) or π (back). 2π is returned so the
/// snap can animate forward instead of spinning the long way around.
@visibleForTesting
double snapAlbumCardSpin(double spin) {
  final n = _normalizedSpin(spin);
  final dist0 = math.min(n, 2 * math.pi - n);
  final distPi = (n - math.pi).abs();
  if (distPi < dist0) return math.pi;
  return n > math.pi ? 2 * math.pi : 0;
}
