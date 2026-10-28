import 'package:flutter/material.dart';

import '../../ui/tokens/motion_tokens.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/persistence/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../shared/utils/app_router.dart';
import '../../shared/widgets/block_system_app_exit.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/tokens/radius_tokens.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  List<_OnboardingSlide> _slidesFor(AppLocalizations l10n) => [
    _OnboardingSlide(
      frame: _OnboardingFrame.logo,
      title: l10n.onboardingSlide1Title,
      body: l10n.onboardingSlide1Body,
    ),
    _OnboardingSlide(
      frame: _OnboardingFrame.life,
      title: l10n.onboardingSlide3Title,
      body: l10n.onboardingSlide3Body,
    ),
    _OnboardingSlide(
      frame: _OnboardingFrame.join,
      title: l10n.onboardingSlide2Title,
      body: l10n.onboardingSlide2Body,
    ),
  ];

  Future<void> _finish() async {
    await ref.read(settingsRepositoryProvider).markOnboardingCompleted();
    bumpSettingsRevision(ref);
    if (mounted) context.go(AppRoutes.home);
  }

  void _next(int slideCount) {
    if (_currentPage < slideCount - 1) {
      _controller.nextPage(
        duration: MotionTokens.slow,
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final slides = _slidesFor(l10n);
    return BlockSystemAppExit(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemCount: slides.length,
                  itemBuilder: (context, i) => _SlideView(slide: slides[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children:
                    List.generate(slides.length, (i) {
                      return AnimatedContainer(
                        duration: MotionTokens.standard,
                        margin: EdgeInsets.symmetric(
                          horizontal: LayoutTokens.gr0,
                        ),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color:
                              _currentPage == i
                                  ? colors.primaryAccent
                                  : colors.textSecondary.withValues(
                                    alpha: OpacityTokens.moderate,
                                  ),
                          borderRadius: RadiusTokens.radiusXl,
                        ),
                      );
                    }).toList(),
              ),
              SizedBox(height: LayoutTokens.gr5),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: LayoutTokens.ctaHorizontal,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UiButton(
                      label:
                          _currentPage == slides.length - 1
                              ? l10n.onboardingReadyToPlay
                              : l10n.onboardingNext,
                      onPressed: () => _next(slides.length),
                    ),
                    TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        minimumSize: const Size(0, LayoutTokens.minTapTarget),
                      ),
                      child: Text(l10n.onboardingSkip),
                    ),
                  ],
                ),
              ),
              SizedBox(height: LayoutTokens.gr5),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OnboardingFrame { logo, life, join }

class _OnboardingSlide {
  final _OnboardingFrame frame;
  final String title;
  final String body;

  const _OnboardingSlide({
    required this.frame,
    required this.title,
    required this.body,
  });
}

class _SlideView extends StatelessWidget {
  final _OnboardingSlide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 360;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? LayoutTokens.gr4 : LayoutTokens.gr5,
      ),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _OnboardingFrameArt(frame: slide.frame),
              SizedBox(height: LayoutTokens.gr5),
              Text(
                slide.title,
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: LayoutTokens.gr4),
              Text(
                slide.body,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingFrameArt extends StatelessWidget {
  const _OnboardingFrameArt({required this.frame});

  final _OnboardingFrame frame;

  @override
  Widget build(BuildContext context) {
    return switch (frame) {
      _OnboardingFrame.logo => const BrandLogo(
        layout: BrandLogoLayout.vertical,
        height: 120,
      ),
      _OnboardingFrame.life => const _LifeFrame(),
      _OnboardingFrame.join => const _JoinFrame(),
    };
  }
}

class _LifeFrame extends StatelessWidget {
  const _LifeFrame();

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Container(
      width: 240,
      height: 132,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: RadiusTokens.radiusXl,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Icon(Icons.remove_rounded, color: colors.primaryAccent),
          ),
          Expanded(
            child: Text(
              '40',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: FontTokens.displayLife,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Icon(Icons.add_rounded, color: colors.primaryAccent),
          ),
        ],
      ),
    );
  }
}

class _JoinFrame extends StatelessWidget {
  const _JoinFrame();

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Container(
      width: 148,
      height: 148,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: RadiusTokens.radiusLg,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Icon(Icons.qr_code_2_rounded, size: 88, color: colors.textPrimary),
    );
  }
}
