import 'package:flutter/material.dart';

import '../../../core/game/game_phase.dart';
import '../../../core/game/game_state.dart';
import '../../../l10n/app_localizations.dart';
import 'game_colors.dart';
import '../../../shared/utils/game_haptics.dart';
import '../../../ui/tokens/font_tokens.dart';
import '../../../ui/tokens/layout_tokens.dart';
import '../../../ui/tokens/opacity_tokens.dart';
import '../../../ui/tokens/radius_tokens.dart';
import 'end_turn_bar.dart';
import 'phase_picker_sheet.dart';

/// Play-tab controls: quiet phase steps, then a full-width End turn.
class PhaseNavCluster extends StatelessWidget {
  const PhaseNavCluster({
    super.key,
    required this.game,
    required this.accentColor,
    this.onBack,
    this.onNext,
    this.onPickPhase,
    this.onEndTurn,
    this.endTurnEnabled = false,
    this.onHostSkip,
    this.endTurnSkipName,
  });

  final GameState game;
  final Color accentColor;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final void Function(GamePhase phase)? onPickPhase;
  final VoidCallback? onEndTurn;
  final bool endTurnEnabled;

  /// Host: visible Skip while another seat is active.
  final VoidCallback? onHostSkip;
  final String? endTurnSkipName;

  static const double phaseRowHeight = LayoutTokens.minTapTarget;

  /// Phase row + gap + End turn, without the optional host Skip button.
  static const double barHeight =
      phaseRowHeight + LayoutTokens.gr1 + EndTurnBar.barHeight;

  static double heightFor({required bool showSkip}) =>
      phaseRowHeight +
      LayoutTokens.gr1 +
      EndTurnBar.heightFor(showSkip: showSkip);

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final activeName = game.playerById(game.activePlayerId)?.username;
    final waitingName =
        endTurnEnabled
            ? null
            : (endTurnSkipName != null && endTurnSkipName!.isNotEmpty
                ? endTurnSkipName
                : activeName);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.94),
            borderRadius: RadiusTokens.radiusXl,
          ),
          child: ClipRRect(
            borderRadius: RadiusTokens.radiusXl,
            child: PhaseNavClusterStrip(
              game: game,
              accentColor: accentColor,
              onBack: onBack,
              onNext: onNext,
              onPickPhase: onPickPhase,
            ),
          ),
        ),
        SizedBox(height: LayoutTokens.gr1),
        EndTurnBar(
          accentColor: colors.primaryAccent,
          enabled: endTurnEnabled && !game.timeoutActive,
          onEndTurn: onEndTurn ?? () {},
          waitingForName: waitingName,
          onHostSkip: game.timeoutActive ? null : onHostSkip,
        ),
      ],
    );
  }
}

class PhaseNavClusterStrip extends StatelessWidget {
  const PhaseNavClusterStrip({
    super.key,
    required this.game,
    required this.accentColor,
    this.onBack,
    this.onNext,
    this.onPickPhase,
  });

  final GameState game;
  final Color accentColor;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final void Function(GamePhase phase)? onPickPhase;

  static const double _sideMinWidth = 72;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final dividerColor = colors.textSecondary.withValues(alpha: 0.14);

    return SizedBox(
      height: PhaseNavCluster.phaseRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PhaseNavCenter(
              game: game,
              accentColor: accentColor,
              onPickPhase: onPickPhase,
            ),
          ),
          if (onBack != null) ...[
            VerticalDivider(width: 1, thickness: 1, color: dividerColor),
            SizedBox(
              width: _sideMinWidth,
              child: _PhaseNavSideButton(
                label: l10n.gamePhaseBack,
                icon: Icons.chevron_left_rounded,
                iconFirst: true,
                enabled: !game.timeoutActive,
                onPressed: onBack,
              ),
            ),
          ],
          if (onNext != null) ...[
            VerticalDivider(width: 1, thickness: 1, color: dividerColor),
            SizedBox(
              width: _sideMinWidth,
              child: _PhaseNavSideButton(
                label: l10n.gamePhaseNext,
                icon: Icons.chevron_right_rounded,
                iconFirst: false,
                enabled: !game.timeoutActive,
                onPressed: onNext,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhaseNavSideButton extends StatelessWidget {
  const _PhaseNavSideButton({
    required this.label,
    required this.icon,
    required this.iconFirst,
    required this.enabled,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool iconFirst;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final fg =
        enabled
            ? colors.textPrimary
            : colors.textSecondary.withValues(alpha: OpacityTokens.disabled);
    final iconWidget = Icon(icon, size: 20, color: fg);
    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: FontTokens.hudXs,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.05,
        color: fg,
        height: 1.1,
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap:
              enabled
                  ? () {
                    context.gameHapticLight();
                    onPressed?.call();
                  }
                  : null,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children:
                    iconFirst
                        ? [
                          iconWidget,
                          SizedBox(width: LayoutTokens.gr0),
                          labelWidget,
                        ]
                        : [
                          labelWidget,
                          SizedBox(width: LayoutTokens.gr0),
                          iconWidget,
                        ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhaseNavCenter extends StatelessWidget {
  const _PhaseNavCenter({
    required this.game,
    required this.accentColor,
    this.onPickPhase,
  });

  final GameState game;
  final Color accentColor;
  final void Function(GamePhase phase)? onPickPhase;

  bool get _canPick => onPickPhase != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final l10n = AppLocalizations.of(context);
    final phaseColor =
        game.isLocalPlayersTurn ? accentColor : colors.textSecondary;

    Widget buildLabel(BoxConstraints constraints) {
      final narrow = constraints.maxWidth < 108;
      final phaseText =
          narrow ? game.currentPhase.shortName : game.currentPhase.displayName;
      final fontSize = narrow ? FontTokens.hudXs : FontTokens.hudSm;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              phaseText,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
                letterSpacing: 0.05,
                height: 1.1,
                color: phaseColor,
              ),
            ),
          ),
          if (_canPick) ...[
            const SizedBox(width: LayoutTokens.gr0),
            Icon(
              Icons.unfold_more_rounded,
              size: 14,
              color: phaseColor.withValues(alpha: OpacityTokens.nearOpaque),
            ),
          ],
        ],
      );
    }

    if (!_canPick) {
      return Semantics(
        header: true,
        label: l10n.phaseNavCurrentA11y(game.currentPhase.displayName),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gr1),
          child: LayoutBuilder(
            builder:
                (context, constraints) =>
                    Center(child: buildLabel(constraints)),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: '${l10n.gameChoosePhase}, ${game.currentPhase.displayName}',
      child: Material(
        color: colors.backgroundPrimary.withValues(alpha: 0.08),
        child: InkWell(
          onTap: () {
            context.gameHapticSelection();
            showPhasePickerSheet(
              context,
              currentPhase: game.currentPhase,
              accentColor: accentColor,
              onSelected: onPickPhase!,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: LayoutTokens.gr1),
            child: LayoutBuilder(
              builder:
                  (context, constraints) => Center(
                    child: Tooltip(
                      message: l10n.gameChoosePhase,
                      child: buildLabel(constraints),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
