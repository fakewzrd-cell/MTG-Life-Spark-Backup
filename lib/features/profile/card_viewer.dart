import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';

/// Opens the card large enough to inspect, tilted by dragging.
///
/// [note] and [onAction] are used by suggested cards, which explain the
/// inclusion rate and add the card from the viewer.
Future<void> showAlbumCardViewer(
  BuildContext context, {
  required String name,
  String? imageUrl,
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
    this.note,
    this.actionLabel,
    this.onAction,
  });

  final String name;
  final String? imageUrl;
  final String? note;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxHeight = size.height * 0.74;
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
  });

  final String name;
  final String? imageUrl;
  final double width;
  final double height;

  @override
  State<_TiltingCard> createState() => _TiltingCardState();
}

class _TiltingCardState extends State<_TiltingCard>
    with SingleTickerProviderStateMixin {
  Offset _tilt = Offset.zero;
  Offset _released = Offset.zero;
  late final AnimationController _settle;

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
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _track(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final nx = ((local.dx / box.size.width) * 2 - 1).clamp(-1.0, 1.0);
    final ny = ((local.dy / box.size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() => _tilt = Offset(nx, ny));
  }

  void _release() {
    _released = _tilt;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    const maxTilt = 0.42;
    final transform =
        Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateX(-_tilt.dy * maxTilt)
          ..rotateY(_tilt.dx * maxTilt);

    final face = ClipRRect(
      borderRadius: BorderRadius.circular(RadiusTokens.md),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: _CardFace(
          name: widget.name,
          imageUrl: widget.imageUrl,
          colors: colors,
        ),
      ),
    );

    return GestureDetector(
      onTap: () {},
      onPanStart: (details) {
        _settle.stop();
        _track(details.globalPosition);
      },
      onPanUpdate: (details) => _track(details.globalPosition),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: Stack(
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.translationValues(0, 0, -12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(RadiusTokens.md),
                  border: Border.all(color: const Color(0xFF3A3A3A)),
                ),
                child: SizedBox(width: widget.width, height: widget.height),
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
              child: face,
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
    if (url == null || url.isEmpty) {
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
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => ColoredBox(color: colors.surface),
      errorWidget:
          (_, __, ___) => ColoredBox(
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
          ),
    );
  }
}
