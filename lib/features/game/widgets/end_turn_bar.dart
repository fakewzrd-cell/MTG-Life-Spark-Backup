import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/game_haptics.dart';
import '../../../ui/tokens/font_tokens.dart';
import '../../../ui/tokens/layout_tokens.dart';
import '../../../ui/tokens/opacity_tokens.dart';
import '../../../ui/tokens/radius_tokens.dart';
import '../../../ui/tokens/color_tokens.dart';
import 'game_colors.dart';

/// Full-width End turn control. Host skip is a separate text button.
class EndTurnBar extends StatelessWidget {
  const EndTurnBar({
    super.key,
    required this.accentColor,
    required this.enabled,
    required this.onEndTurn,
    this.waitingForName,
    this.onHostSkip,
  });

  final Color accentColor;
  final bool enabled;
  final VoidCallback onEndTurn;
  final String? waitingForName;

  /// Host: tap to skip another player's turn. Shown only while waiting.
  final VoidCallback? onHostSkip;

  static const double barHeight = 60;

  static double heightFor({required bool showSkip}) =>
      barHeight + (showSkip ? LayoutTokens.minTapTarget : 0);

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final canSkip = onHostSkip != null;
    final name = waitingForName;
    // Solid theme accent fill so the control stays visible on light surfaces.
    final bg = enabled
        ? accentColor
        : colors.backgroundSecondary.withValues(alpha: OpacityTokens.moderate);
    final fg = enabled
        ? ColorTokens.onColor(accentColor)
        : colors.textSecondary.withValues(alpha: OpacityTokens.disabled);
    String? subtitle;
    if (!enabled && name != null && name.isNotEmpty) {
      subtitle = l10n.gameWaitingForPlayer(name);
    }
    final skipLabel = name != null && name.isNotEmpty
        ? l10n.gameSkipPlayer(name)
        : l10n.gameSkipTurn;

    final bar = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.94),
        borderRadius: RadiusTokens.radiusControlSm,
      ),
      child: ClipRRect(
        borderRadius: RadiusTokens.radiusControlSm,
        child: SizedBox(
          height: barHeight,
          child: Material(
            color: bg,
            child: InkWell(
              onTap: enabled
                  ? () {
                      context.gameHapticLight();
                      onEndTurn();
                    }
                  : null,
              child: Semantics(
                button: true,
                enabled: enabled,
                label: l10n.gameEndTurn,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LayoutTokens.gr3,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.gameEndTurn,
                          style: TextStyle(
                            fontSize: FontTokens.title,
                            fontWeight: FontWeight.w700,
                            color: fg,
                            height: 1.1,
                          ),
                        ),
                        if (subtitle != null) ...[
                          SizedBox(height: LayoutTokens.gr0),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: FontTokens.hudXs,
                              fontWeight: FontWeight.w500,
                              color: fg.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!canSkip) return bar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        TextButton(
          onPressed: () {
            context.gameHapticMedium();
            onHostSkip!();
          },
          style: TextButton.styleFrom(
            foregroundColor: colors.textPrimary,
            minimumSize: const Size(0, LayoutTokens.minTapTarget),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            skipLabel,
            style: const TextStyle(
              fontSize: FontTokens.hudSm,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
