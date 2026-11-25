import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/game/lobby_state.dart';
import '../../core/one_view/one_view_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/app_router.dart';
import '../../ui/components/ui_button.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../../ui/tokens/typography_tokens.dart';
import 'one_view_chrome.dart';

const _presetLives = [20, 25, 30, 40, 60];

/// One View rules setup — players, life, gameplay toggles; then Start → table.
class OneViewSetupScreen extends ConsumerWidget {
  const OneViewSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(oneViewProvider.select((s) => s.config));
    final notifier = ref.read(oneViewProvider.notifier);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                LayoutTokens.shellPageInset / 2,
                LayoutTokens.gr2,
                LayoutTokens.shellPageInset,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
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
                      l10n.oneViewSetupTitle,
                      textAlign: TextAlign.center,
                      style: TypographyTokens.headline(context),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  ListView(
                    padding: EdgeInsets.fromLTRB(
                      LayoutTokens.shellPageInset,
                      LayoutTokens.gr2,
                      LayoutTokens.shellPageInset,
                      _oneViewStartFooterHeight(context),
                    ),
                    children: [
                      Text(
                        l10n.oneViewPlayersLabel,
                        style: TypographyTokens.sectionTitle(
                          colors.textPrimary,
                        ),
                      ),
                      SizedBox(height: LayoutTokens.gr2),
                      _EqualChoiceRow(
                        choices: [
                          for (var n = 1; n <= 6; n++)
                            _EqualChoice(
                              label: '$n',
                              selected: config.maxPlayers == n,
                              onTap: () => notifier.setPlayerCount(n),
                            ),
                        ],
                      ),
                      SizedBox(height: LayoutTokens.gr4),
                      Text(
                        l10n.hostStartingLife,
                        style: TypographyTokens.sectionTitle(
                          colors.textPrimary,
                        ),
                      ),
                      SizedBox(height: LayoutTokens.gr2),
                      _EqualChoiceRow(
                        choices: [
                          for (final life in _presetLives)
                            _EqualChoice(
                              label: '$life',
                              selected: config.startingLife == life,
                              onTap: () => notifier.setStartingLife(life),
                            ),
                          _EqualChoice(
                            label:
                                !_presetLives.contains(config.startingLife)
                                    ? '${config.startingLife}'
                                    : null,
                            icon:
                                _presetLives.contains(config.startingLife)
                                    ? Icons.add_rounded
                                    : null,
                            semanticsLabel: l10n.hostCustomEllipsis,
                            selected:
                                !_presetLives.contains(config.startingLife),
                            onTap:
                                () => _showCustomLifeDialog(
                                  context,
                                  current: config.startingLife,
                                  onChanged: notifier.setStartingLife,
                                ),
                          ),
                        ],
                      ),
                      SizedBox(height: LayoutTokens.gr4),
                      Text(
                        l10n.hostGameplay,
                        style: TypographyTokens.sectionTitle(
                          colors.textPrimary,
                        ),
                      ),
                      SizedBox(height: LayoutTokens.gr2),
                      _GameplayToggles(config: config, notifier: notifier),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: LayoutTokens.shellDockInset(context),
                    child: _OneViewStartBar(
                      label: l10n.hostStartGame,
                      onPressed: () {
                        notifier.startTable();
                        context.push(AppRoutes.oneViewTable);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showCustomLifeDialog(
    BuildContext context, {
    required int current,
    required ValueChanged<int> onChanged,
  }) {
    final controller = TextEditingController(text: current.toString());
    final l10n = AppLocalizations.of(context);
    showOneViewDialog<void>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          final v = int.tryParse(controller.text);
          if (v != null && v >= 1 && v <= 999) {
            onChanged(v);
            Navigator.pop(dialogContext);
          }
        }

        return OneViewFormDialog(
          title: l10n.hostCustomStartingLifeTitle,
          submitLabel: 'OK',
          onSubmit: submit,
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.hostCustomStartingLifeHint,
            ),
            onSubmitted: (_) => submit(),
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }
}

/// Matches the online lobby glass bar: button, its padding, and the tab dock.
/// The setup list uses this as bottom padding so Turn timer can scroll clear.
double _oneViewStartFooterHeight(BuildContext context) {
  const buttonHeight = 52.0;
  return LayoutTokens.gr2 +
      buttonHeight +
      LayoutTokens.gr2 +
      LayoutTokens.shellDockInset(context);
}

class _OneViewStartBar extends StatelessWidget {
  const _OneViewStartBar({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.backgroundPrimary.withValues(alpha: 0.02),
                colors.backgroundPrimary.withValues(alpha: 0.55),
                colors.backgroundPrimary.withValues(alpha: 0.78),
              ],
              stops: const [0.0, 0.22, 1.0],
            ),
            border: Border(
              top: BorderSide(
                color: colors.borderSubtle.withValues(alpha: 0.16),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LayoutTokens.shellPageInset,
              LayoutTokens.gr2,
              LayoutTokens.shellPageInset,
              LayoutTokens.gr2,
            ),
            child: UiButton(label: label, onPressed: onPressed),
          ),
        ),
      ),
    );
  }
}

/// One row of equal choices. Each cell grows to share the line, so six
/// player counts stay together and can be taller than a default chip.
class _EqualChoiceRow extends StatelessWidget {
  const _EqualChoiceRow({required this.choices});

  final List<_EqualChoice> choices;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(width: LayoutTokens.gr1),
          Expanded(child: choices[i]),
        ],
      ],
    );
  }
}

class _EqualChoice extends StatelessWidget {
  const _EqualChoice({
    required this.selected,
    required this.onTap,
    this.label,
    this.icon,
    this.semanticsLabel,
  }) : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final String? semanticsLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final ink =
        selected ? Theme.of(context).colorScheme.onPrimary : colors.textPrimary;
    final shownLabel = label;
    final shownIcon = icon;
    return Semantics(
      button: true,
      label: semanticsLabel ?? shownLabel,
      child: Material(
        color: selected ? colors.primaryAccent : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: RadiusTokens.radiusLg,
          side: BorderSide(
            color: selected ? colors.primaryAccent : colors.borderSubtle,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child:
                  shownIcon != null
                      ? Icon(shownIcon, color: ink, size: 28)
                      : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          shownLabel!,
                          maxLines: 1,
                          style: TextStyle(
                            color: ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1,
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

class _GameplayToggles extends StatelessWidget {
  const _GameplayToggles({required this.config, required this.notifier});

  final LobbyConfig config;
  final OneViewNotifier notifier;

  bool get _autoKoAll =>
      config.autoKoFromLife &&
      config.autoKoFromPoison &&
      config.autoKoFromCommanderDamage;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: RadiusTokens.radiusXl),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _tile(
            context,
            title: l10n.hostToggleAutoKo,
            subtitle: l10n.hostToggleAutoKoSubtitle,
            value: _autoKoAll,
            onChanged:
                (v) => notifier.updateConfig(
                  config.copyWith(
                    autoKoFromLife: v,
                    autoKoFromPoison: v,
                    autoKoFromCommanderDamage: v,
                  ),
                ),
          ),
          _tile(
            context,
            title: l10n.hostToggleCommanderDmgLife,
            subtitle: l10n.hostToggleCommanderDmgLifeSubtitle,
            value: config.commanderDamageReducesLife,
            onChanged:
                (v) => notifier.updateConfig(
                  config.copyWith(commanderDamageReducesLife: v),
                ),
          ),
          _tile(
            context,
            title: l10n.oneViewAttackSwipe,
            subtitle: l10n.oneViewAttackSwipeSubtitle,
            value: config.attackSwipeEnabled,
            onChanged:
                (v) => notifier.updateConfig(
                  config.copyWith(attackSwipeEnabled: v),
                ),
          ),
          _tile(
            context,
            title: l10n.hostToggleTurnTimer,
            subtitle: l10n.hostToggleTurnTimerSubtitle,
            value: config.trackTurnDuration,
            onChanged:
                (v) => notifier.updateConfig(
                  config.copyWith(
                    trackTurnDuration: v,
                    turnTimeLimitSeconds:
                        v ? config.turnTimeLimitSeconds : null,
                  ),
                ),
          ),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: Text(
              l10n.oneViewExtraModes,
              style: OneViewChrome.menuLabelStyle(context),
            ),
            subtitle:
                [
                      if (config.planechaseEnabled) l10n.hostTogglePlanechase,
                      if (config.archenemyEnabled) l10n.hostToggleArchenemy,
                      if (config.bountyEnabled) l10n.hostToggleBounty,
                    ].isEmpty
                    ? null
                    : Text(
                      [
                        if (config.planechaseEnabled) l10n.hostTogglePlanechase,
                        if (config.archenemyEnabled) l10n.hostToggleArchenemy,
                        if (config.bountyEnabled) l10n.hostToggleBounty,
                      ].join(' · '),
                      style: OneViewChrome.dialogBodyStyle(context),
                    ),
            shape: const Border(),
            collapsedShape: const Border(),
            children: [
              _tile(
                context,
                title: l10n.hostTogglePlanechase,
                subtitle: l10n.hostTogglePlanechaseSubtitle,
                value: config.planechaseEnabled,
                onChanged:
                    (v) => notifier.updateConfig(
                      config.copyWith(planechaseEnabled: v),
                    ),
              ),
              _tile(
                context,
                title: l10n.hostToggleArchenemy,
                subtitle: l10n.hostToggleArchenemySubtitle,
                value: config.archenemyEnabled,
                onChanged:
                    (v) => notifier.updateConfig(
                      config.copyWith(archenemyEnabled: v),
                    ),
              ),
              _tile(
                context,
                title: l10n.hostToggleBounty,
                subtitle: l10n.hostToggleBountySubtitle,
                value: config.bountyEnabled,
                onChanged:
                    (v) => notifier.updateConfig(
                      config.copyWith(bountyEnabled: v),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = AppColorTokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < 360;
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: compact ? FontTokens.body : FontTokens.title,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colors.textSecondary, fontSize: 14),
      ),
      value: value,
      onChanged: onChanged,
      activeTrackColor: colors.primaryAccent.withValues(
        alpha: OpacityTokens.half,
      ),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.primaryAccent;
        }
        return null;
      }),
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? LayoutTokens.gr2 : LayoutTokens.gr3,
        vertical: LayoutTokens.gr1,
      ),
    );
  }
}
