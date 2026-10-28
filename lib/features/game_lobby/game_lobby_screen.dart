import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/utils/app_router.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';

/// Game lobby — Host and Join split the viewport 50/50 with uniform page inset.
class GameLobbyScreen extends StatelessWidget {
  const GameLobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
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
            LayoutTokens.shellBottomInset(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: BrandLogo(
                  layout: BrandLogoLayout.horizontal,
                  height: 32,
                ),
              ),
              SizedBox(height: LayoutTokens.gr3),
              Expanded(
                child: _BigActionButton(
                  label: l10n.lobbyHostGame,
                  subtitle: l10n.lobbyHostGameSubtitle,
                  icon: Icons.groups_rounded,
                  filled: true,
                  onTap: () => context.push(AppRoutes.lobbyHost),
                ),
              ),
              SizedBox(height: LayoutTokens.gr2),
              Expanded(
                child: _BigActionButton(
                  label: l10n.lobbyJoinGame,
                  subtitle: l10n.lobbyJoinGameSubtitle,
                  icon: Icons.qr_code_scanner_rounded,
                  onTap: () => context.push(AppRoutes.lobbyJoin),
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

  /// Host is the filled primary. Join stays a quiet surface.
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _LobbyIconBadge(
                  icon: icon,
                  isCompact: isCompact,
                  iconColor: iconColor,
                  badgeColor: badgeColor,
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
    );
  }
}

/// Fixed-size circular badge so the Material icon is layout-centered.
class _LobbyIconBadge extends StatelessWidget {
  const _LobbyIconBadge({
    required this.icon,
    required this.isCompact,
    required this.iconColor,
    required this.badgeColor,
  });

  final IconData icon;
  final bool isCompact;
  final Color iconColor;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    final badgeSize = isCompact ? 52.0 : 56.0;
    final iconSize = isCompact ? 26.0 : 30.0;

    return SizedBox(
      width: badgeSize,
      height: badgeSize,
      child: DecoratedBox(
        decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
        child: Center(child: Icon(icon, size: iconSize, color: iconColor)),
      ),
    );
  }
}
