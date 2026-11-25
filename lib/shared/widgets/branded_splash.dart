import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../core/debug/web_logo_splash.dart';
import '../../ui/tokens/color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';

/// Launch splash: play the Life Spark logo animation, then enter the app.
///
/// Completes only after the intro finishes **and** [ready] is true (bootstrap
/// done). The Lottie has no background, so it sits on [ColorTokens.backgroundPrimary]
/// and can be recolored by changing that surface.
///
/// The player mounts hidden, starts playback, then fades in so the mark is
/// never shown frozen before it moves.
class BrandedSplash extends StatefulWidget {
  const BrandedSplash({
    super.key,
    this.message = 'Loading Life Spark…',
    this.ready = false,
    this.onRevealComplete,
    this.useVideoIntro,
  });

  final String message;

  /// When true (and intro finished), invoke [onRevealComplete] after a short hold.
  final bool ready;

  final VoidCallback? onRevealComplete;

  /// Defaults to true. Set false in widget tests (no animation asset load).
  final bool? useVideoIntro;

  /// Transparent logo open animation (1920², 181 frames at 60fps).
  static const logoAnimationAsset = 'assets/animations/logo_splash.json';

  /// Source length of [logoAnimationAsset] (181 frames / 60fps).
  static const logoAnimationSourceDuration = Duration(milliseconds: 3017);

  /// On-screen intro length. The file plays at its authored speed.
  static const logoAnimationDuration = logoAnimationSourceDuration;

  /// Playback speed. 1 keeps the Lottie timing.
  static double get logoAnimationPlaybackRate =>
      logoAnimationSourceDuration.inMilliseconds /
      logoAnimationDuration.inMilliseconds;

  /// Max display size for the intro (scaled down on narrow screens).
  static const double introSize = 340;

  /// Fraction of the shortest screen side used for the intro box.
  static const double introViewportFraction = 0.72;

  /// Fade the clip in once the composition is ready (no freeze-frame).
  static const introFade = Duration(milliseconds: 160);

  /// If the file never loads, leave the surface rather than hang forever.
  static const videoStartTimeout = Duration(milliseconds: 2000);

  /// Brief hold after the clip ends before entering the app.
  static const taglineHold = Duration(milliseconds: 160);

  /// How long init may take before we show a loading cue under the intro.
  static const slowLoadThreshold = Duration(milliseconds: 1000);

  /// Brief hold when the intro cannot play (tests / decode failure).
  static const revealDuration = Duration(milliseconds: 300);

  /// Hold after the intro before entering the app.
  static const revealHold = Duration(milliseconds: 80);

  static bool get defaultUseVideoIntro => true;

  /// Navigation buttons stay. The bar matches the splash instead of a white plate.
  static SystemUiOverlayStyle get systemOverlay => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: ColorTokens.backgroundPrimary,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarDividerColor: Colors.transparent,
  );

  @override
  State<BrandedSplash> createState() => _BrandedSplashState();
}

class _BrandedSplashState extends State<BrandedSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _introDeadline;

  var _showLoadingCue = false;
  var _finishing = false;
  var _introFinished = false;
  var _compositionReady = false;
  var _introOpaque = false;

  bool get _playIntro =>
      widget.useVideoIntro ?? BrandedSplash.defaultUseVideoIntro;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(BrandedSplash.systemOverlay);
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener(_onStatus);

    if (_playIntro) {
      Future<void>.delayed(BrandedSplash.videoStartTimeout, () {
        if (!mounted || _introFinished || _introOpaque) return;
        _markIntroFinished();
      });
    } else if (kIsWeb) {
      listenForWebLogoSplashDone(() {
        if (!mounted) return;
        _markIntroFinished();
      });
    } else {
      Future<void>.delayed(BrandedSplash.revealDuration, () {
        if (!mounted) return;
        _markIntroFinished();
      });
    }

    if (!widget.ready) {
      Future<void>.delayed(BrandedSplash.slowLoadThreshold, () {
        if (!mounted || widget.ready || _finishing) return;
        setState(() => _showLoadingCue = true);
      });
    }
  }

  void _onComposition(LottieComposition composition) {
    if (!mounted || _introFinished || !_playIntro) return;
    final duration = composition.duration;
    _controller.duration = duration;
    _compositionReady = true;
    _introOpaque = true;
    setState(() {});
    _controller.forward();
    // Status can miss if a startup task blocks the ticker. Leave anyway once
    // the authored clip length has passed.
    _introDeadline?.cancel();
    _introDeadline = Timer(
      duration == Duration.zero
          ? BrandedSplash.revealDuration
          : duration + const Duration(milliseconds: 50),
      () {
        if (!mounted) return;
        _markIntroFinished();
      },
    );
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _markIntroFinished();
  }

  void _markIntroFinished() {
    if (_introFinished) return;
    _introFinished = true;
    if (mounted) setState(() {});
    if (_playIntro) {
      Future<void>.delayed(BrandedSplash.taglineHold, () {
        if (!mounted) return;
        _tryFinish();
      });
      return;
    }
    _tryFinish();
  }

  @override
  void didUpdateWidget(covariant BrandedSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) {
      _tryFinish();
    }
  }

  Future<void> _tryFinish() async {
    if (_finishing || !widget.ready || !_introFinished) return;
    _finishing = true;
    if (_showLoadingCue && mounted) {
      setState(() => _showLoadingCue = false);
    }
    // Yield so onRevealComplete never runs from didUpdateWidget (during build).
    await Future<void>.delayed(
      kIsWeb ? Duration.zero : BrandedSplash.revealHold,
    );
    if (!mounted) return;
    widget.onRevealComplete?.call();
  }

  @override
  void dispose() {
    _introDeadline?.cancel();
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  double _introBoxSize(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    return (shortest * BrandedSplash.introViewportFraction).clamp(
      220.0,
      BrandedSplash.introSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    final splashColor = ColorTokens.backgroundPrimary;
    final showLoading = _showLoadingCue && !_finishing;
    final introSize = _introBoxSize(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BrandedSplash.systemOverlay,
      child: Scaffold(
        backgroundColor: splashColor,
        body: ColoredBox(
          color: splashColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: introSize,
                  height: introSize,
                  child: _buildIntro(),
                ),
                if (showLoading) ...[
                  SizedBox(height: LayoutTokens.gr4),
                  Text(
                    widget.message,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: FontTokens.sm,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    if (!_playIntro) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: _introOpaque && _compositionReady ? 1 : 0,
      duration: BrandedSplash.introFade,
      curve: Curves.easeOut,
      child: Lottie.asset(
        BrandedSplash.logoAnimationAsset,
        controller: _controller,
        animate: false,
        repeat: false,
        fit: BoxFit.contain,
        onLoaded: _onComposition,
      ),
    );
  }
}
