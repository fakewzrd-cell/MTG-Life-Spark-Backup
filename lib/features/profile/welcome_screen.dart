import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/player_identity.dart';
import '../../core/models/player_profile.dart';
import '../../core/persistence/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/app_router.dart';
import '../../shared/widgets/block_system_app_exit.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/founder_note.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/tokens/layout_tokens.dart';

/// Calm brand-first first launch screen before profile setup.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _skipping = false;

  Future<void> _skip() async {
    setState(() => _skipping = true);
    final profile = PlayerProfile(
      username: generateSparkDisplayName(),
      playerId: generatePlayerId(),
    );
    await ref.read(profileRepositoryProvider).saveProfile(profile);
    bumpProfileRevision(ref);
    if (mounted) context.go(AppRoutes.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlockSystemAppExit(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: LayoutTokens.ctaHorizontal,
                    vertical: LayoutTokens.gr3,
                  ),
                  child: const Column(
                    children: [
                      BrandLogo(layout: BrandLogoLayout.vertical, height: 72),
                      SizedBox(height: LayoutTokens.gr4),
                      FounderNote(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  LayoutTokens.ctaHorizontal,
                  LayoutTokens.gr2,
                  LayoutTokens.ctaHorizontal,
                  LayoutTokens.gr5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UiButton(
                      label: l10n.welcomeReadyToPlay,
                      enabled: !_skipping,
                      onPressed:
                          _skipping
                              ? null
                              : () => context.go(AppRoutes.profileSetup),
                    ),
                    SizedBox(height: LayoutTokens.gr2),
                    UiButton(
                      label: l10n.welcomeSkip,
                      variant: UiButtonVariant.secondary,
                      loading: _skipping,
                      enabled: !_skipping,
                      onPressed: _skipping ? null : _skip,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
