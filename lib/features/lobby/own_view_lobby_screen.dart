import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/utils/app_router.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../../ui/tokens/typography_tokens.dart';

/// Own View entry — Host / Join (unchanged Wi‑Fi flows), reached from the lobby hub.
class OwnViewLobbyScreen extends StatelessWidget {
  const OwnViewLobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final navClearance =
        LayoutTokens.bottomNavHeight + MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            LayoutTokens.shellPageInset,
            LayoutTokens.shellPageInset,
            LayoutTokens.shellPageInset,
            navClearance,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AppRoutes.lobby);
                      }
                    },
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      l10n.ownViewTitle,
                      textAlign: TextAlign.center,
                      style: TypographyTokens.headline(context),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 1),
                    Expanded(
                      flex: 6,
                      child: _BigActionButton(
                        label: l10n.lobbyHostGame,
                        subtitle: l10n.lobbyHostGameSubtitle,
                        icon: Icons.groups_rounded,
                        filled: true,
                        onTap: () => context.push(AppRoutes.lobbyHost),
                      ),
                    ),
                    const Spacer(flex: 1),
                    Expanded(
                      flex: 6,
                      child: _BigActionButton(
                        label: l10n.lobbyJoinGame,
                        subtitle: l10n.lobbyJoinGameSubtitle,
                        icon: Icons.qr_code_scanner_rounded,
                        onTap: () => context.push(AppRoutes.lobbyJoin),
                      ),
                    ),
                    const Spacer(flex: 1),
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

class _BigActionButton extends StatelessWidget {
  const _BigActionButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final isCompact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.sizeOf(context).height < 600;
    final titleSize = FontTokens.headline;
    final titleColor = filled ? colors.onAccent : colors.textPrimary;
    final subtitleColor =
        filled ? colors.onAccent.withValues(alpha: 0.82) : colors.textSecondary;
    final iconColor = filled ? colors.onAccent : colors.primaryAccent;
    final badgeColor =
        filled
            ? colors.onAccent.withValues(alpha: OpacityTokens.soft)
            : colors.primaryAccent.withValues(alpha: OpacityTokens.subtle);

    return Material(
      color: filled ? colors.primaryAccent : colors.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: RadiusTokens.radiusXl,
        side: filled ? BorderSide.none : BorderSide(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: (filled ? colors.onAccent : colors.primaryAccent)
            .withValues(alpha: OpacityTokens.subtle),
        highlightColor: (filled ? colors.onAccent : colors.primaryAccent)
            .withValues(alpha: OpacityTokens.faint),
        child: Padding(
          padding: const EdgeInsets.all(LayoutTokens.gr2),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: isCompact ? 52.0 : 56.0,
                    height: isCompact ? 52.0 : 56.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          size: isCompact ? 26.0 : 30.0,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: LayoutTokens.gr3),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                      height: 1.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: LayoutTokens.gr1),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: subtitleColor,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
