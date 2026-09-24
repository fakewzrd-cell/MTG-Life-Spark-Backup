import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/game_haptics.dart';
import '../../../ui/tokens/font_tokens.dart';
import '../../../ui/tokens/layout_tokens.dart';
import '../../../ui/tokens/opacity_tokens.dart';
import '../../../ui/tokens/radius_tokens.dart';
import '../../../ui/tokens/color_tokens.dart';
import 'game_colors.dart';

/// End turn control. Host skip is a separate text button.
///
/// When [onForfeit] is set, Forfeit sits in the same row at equal width,
/// using the same control shape in [forfeitColor].
class EndTurnBar extends StatelessWidget {
  const EndTurnBar({
    super.key,
    required this.accentColor,
    required this.enabled,
    required this.onEndTurn,
    this.waitingForName,
    this.onHostSkip,
    this.onForfeit,
    this.forfeitLabel,
    this.forfeitColor,
  });

  final Color accentColor;
  final bool enabled;
  final VoidCallback onEndTurn;
  final String? waitingForName;

  /// Host: tap to skip another player's turn. Shown only while waiting.
  final VoidCallback? onHostSkip;

  /// Table: forfeit shares the row with End turn.
  final VoidCallback? onForfeit;
  final String? forfeitLabel;
  final Color? forfeitColor;

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
    final bg =
        enabled
            ? accentColor
            : colors.backgroundSecondary.withValues(
              alpha: OpacityTokens.moderate,
            );
    final fg =
        enabled
            ? ColorTokens.onColor(accentColor)
            : colors.textSecondary.withValues(alpha: OpacityTokens.disabled);
    String? subtitle;
    if (!enabled && name != null && name.isNotEmpty) {
      subtitle = l10n.gameWaitingForPlayer(name);
    }
    final skipLabel =
        name != null && name.isNotEmpty
            ? l10n.gameSkipPlayer(name)
            : l10n.gameSkipTurn;

    final endTurn = _TurnActionButton(
      label: l10n.gameEndTurn,
      fill: bg,
      foreground: fg,
      enabled: enabled,
      subtitle: subtitle,
      onPressed: enabled ? onEndTurn : null,
    );

    final forfeit = onForfeit;
    final actions =
        forfeit == null
            ? endTurn
            : Row(
              children: [
                Expanded(child: endTurn),
                SizedBox(width: LayoutTokens.gr2),
                Expanded(
                  child: _TurnActionButton(
                    label: forfeitLabel ?? l10n.forfeitConfirm,
                    fill: forfeitColor ?? colors.error,
                    foreground: ColorTokens.onColor(
                      forfeitColor ?? colors.error,
                    ),
                    enabled: true,
                    onPressed: forfeit,
                  ),
                ),
              ],
            );

    if (!canSkip) return actions;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        actions,
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

/// Same filled control as End turn: modest corners, not a pill.
class _TurnActionButton extends StatelessWidget {
  const _TurnActionButton({
    required this.label,
    required this.fill,
    required this.foreground,
    required this.enabled,
    required this.onPressed,
    this.subtitle,
  });

  final String label;
  final Color fill;
  final Color foreground;
  final bool enabled;
  final VoidCallback? onPressed;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: RadiusTokens.radiusXl),
      child: ClipRRect(
        borderRadius: RadiusTokens.radiusXl,
        child: SizedBox(
          height: EndTurnBar.barHeight,
          child: Material(
            color: fill,
            child: InkWell(
              onTap:
                  onPressed == null
                      ? null
                      : () {
                        context.gameHapticLight();
                        onPressed!();
                      },
              child: Semantics(
                button: true,
                enabled: enabled,
                label: label,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LayoutTokens.gr2,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: FontTokens.title,
                            fontWeight: FontWeight.w700,
                            color: foreground,
                            height: 1.1,
                          ),
                        ),
                        if (subtitle != null) ...[
                          SizedBox(height: LayoutTokens.gr0),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: FontTokens.hudXs,
                              fontWeight: FontWeight.w500,
                              color: foreground.withValues(alpha: 0.85),
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
  }
}
