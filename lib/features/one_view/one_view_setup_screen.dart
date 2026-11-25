import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/game/lobby_state.dart';
import '../../core/one_view/one_view_state.dart';
import '../../features/game/widgets/game_modal_chrome.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/app_router.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/opacity_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import '../../ui/tokens/typography_tokens.dart';

/// One View rules setup — players, life, gameplay toggles; then Start → table.
class OneViewSetupScreen extends ConsumerWidget {
  const OneViewSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(oneViewProvider.select((s) => s.config));
    final notifier = ref.read(oneViewProvider.notifier);
    final navClearance =
        LayoutTokens.bottomNavHeight + MediaQuery.paddingOf(context).bottom;

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
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  LayoutTokens.shellPageInset,
                  LayoutTokens.gr2,
                  LayoutTokens.shellPageInset,
                  navClearance + 88,
                ),
                children: [
                  Text(
                    l10n.oneViewPlayersLabel,
                    style: TypographyTokens.sectionTitle(colors.textPrimary),
                  ),
                  SizedBox(height: LayoutTokens.gr2),
                  Wrap(
                    spacing: LayoutTokens.gr2,
                    runSpacing: LayoutTokens.gr2,
                    children: [
                      for (var n = 1; n <= 6; n++)
                        ChoiceChip(
                          label: Text('$n'),
                          selected: config.maxPlayers == n,
                          onSelected: (_) => notifier.setPlayerCount(n),
                        ),
                    ],
                  ),
                  SizedBox(height: LayoutTokens.gr4),
                  Text(
                    l10n.hostStartingLife,
                    style: TypographyTokens.sectionTitle(colors.textPrimary),
                  ),
                  SizedBox(height: LayoutTokens.gr2),
                  Wrap(
                    spacing: LayoutTokens.gr2,
                    runSpacing: LayoutTokens.gr2,
                    children: [
                      for (final life in const [20, 25, 30, 40, 60])
                        ChoiceChip(
                          label: Text('$life'),
                          selected: config.startingLife == life,
                          onSelected: (_) => notifier.setStartingLife(life),
                        ),
                      ActionChip(
                        label: Text(l10n.hostCustomEllipsis),
                        onPressed:
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
                    style: TypographyTokens.sectionTitle(colors.textPrimary),
                  ),
                  SizedBox(height: LayoutTokens.gr2),
                  _GameplayToggles(config: config, notifier: notifier),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          LayoutTokens.shellPageInset,
          LayoutTokens.gr2,
          LayoutTokens.shellPageInset,
          LayoutTokens.gr2 + LayoutTokens.shellDockInset(context),
        ),
        child: FilledButton(
          onPressed: () {
            notifier.startTable();
            context.push(AppRoutes.oneViewTable);
          },
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: RadiusTokens.radiusXl,
            ),
          ),
          child: Text(l10n.oneViewStartTable),
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          final v = int.tryParse(controller.text);
          if (v != null && v >= 1 && v <= 999) {
            onChanged(v);
            Navigator.pop(dialogContext);
          }
        }

        return GameFormDialog(
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
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: RadiusTokens.radiusXl,
      ),
      child: Column(
        children: [
          _tile(
            context,
            title: l10n.hostTogglePlanechase,
            subtitle: l10n.hostTogglePlanechaseSubtitle,
            value: config.planechaseEnabled,
            onChanged:
                (v) =>
                    notifier.updateConfig(config.copyWith(planechaseEnabled: v)),
          ),
          _tile(
            context,
            title: l10n.hostToggleArchenemy,
            subtitle: l10n.hostToggleArchenemySubtitle,
            value: config.archenemyEnabled,
            onChanged:
                (v) =>
                    notifier.updateConfig(config.copyWith(archenemyEnabled: v)),
          ),
          _tile(
            context,
            title: l10n.hostToggleBounty,
            subtitle: l10n.hostToggleBountySubtitle,
            value: config.bountyEnabled,
            onChanged:
                (v) => notifier.updateConfig(config.copyWith(bountyEnabled: v)),
          ),
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
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: FontTokens.caption,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
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
