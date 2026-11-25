import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game/game_session_events.dart';
import '../../core/one_view/one_view_state.dart';
import '../../features/game/widgets/table_tool_result_overlay.dart';
import '../../features/game/widgets/team_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';
import '../../ui/tokens/radius_tokens.dart';
import 'one_view_chrome.dart';

/// Mid-game LobbyConfig toggles from the center menu (plan: settings changeable).
Future<void> showOneViewSettingsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  await showOneViewDialog<void>(
    context: context,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final config = ref.watch(oneViewProvider.select((s) => s.config));
          final notifier = ref.read(oneViewProvider.notifier);
          final l10n = AppLocalizations.of(context);
          bool autoKoAll() =>
              config.autoKoFromLife &&
              config.autoKoFromPoison &&
              config.autoKoFromCommanderDamage;

          Widget tile({
            required String title,
            required String subtitle,
            required bool value,
            required ValueChanged<bool> onChanged,
          }) {
            return SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                vertical: LayoutTokens.gr1,
              ),
              title: Text(title, style: OneViewChrome.menuLabelStyle(context)),
              subtitle: Text(
                subtitle,
                style: OneViewChrome.dialogBodyStyle(context),
              ),
              value: value,
              onChanged: onChanged,
            );
          }

          return OneViewMenuDialog(
            title: l10n.oneViewMidGameSettings,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                tile(
                  title: l10n.hostToggleTeams,
                  subtitle: l10n.hostToggleTeamsSubtitle,
                  value: config.teamsEnabled,
                  onChanged:
                      (v) => notifier.updateConfig(
                        config.copyWith(teamsEnabled: v),
                      ),
                ),
                tile(
                  title: l10n.hostToggleAutoKo,
                  subtitle: l10n.hostToggleAutoKoSubtitle,
                  value: autoKoAll(),
                  onChanged:
                      (v) => notifier.updateConfig(
                        config.copyWith(
                          autoKoFromLife: v,
                          autoKoFromPoison: v,
                          autoKoFromCommanderDamage: v,
                        ),
                      ),
                ),
                tile(
                  title: l10n.hostToggleCommanderDmgLife,
                  subtitle: l10n.hostToggleCommanderDmgLifeSubtitle,
                  value: config.commanderDamageReducesLife,
                  onChanged:
                      (v) => notifier.updateConfig(
                        config.copyWith(commanderDamageReducesLife: v),
                      ),
                ),
                tile(
                  title: l10n.oneViewAttackSwipe,
                  subtitle: l10n.oneViewAttackSwipeSubtitle,
                  value: config.attackSwipeEnabled,
                  onChanged:
                      (v) => notifier.updateConfig(
                        config.copyWith(attackSwipeEnabled: v),
                      ),
                ),
                tile(
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
                  tilePadding: EdgeInsets.zero,
                  subtitle:
                      [
                            if (config.planechaseEnabled)
                              l10n.hostTogglePlanechase,
                            if (config.archenemyEnabled)
                              l10n.hostToggleArchenemy,
                            if (config.bountyEnabled) l10n.hostToggleBounty,
                          ].isEmpty
                          ? null
                          : Text(
                            [
                              if (config.planechaseEnabled)
                                l10n.hostTogglePlanechase,
                              if (config.archenemyEnabled)
                                l10n.hostToggleArchenemy,
                              if (config.bountyEnabled) l10n.hostToggleBounty,
                            ].join(' · '),
                            style: OneViewChrome.dialogBodyStyle(context),
                          ),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(
                    l10n.oneViewExtraModes,
                    style: OneViewChrome.menuLabelStyle(context),
                  ),
                  children: [
                    tile(
                      title: l10n.hostTogglePlanechase,
                      subtitle: l10n.hostTogglePlanechaseSubtitle,
                      value: config.planechaseEnabled,
                      onChanged:
                          (v) => notifier.updateConfig(
                            config.copyWith(planechaseEnabled: v),
                          ),
                    ),
                    tile(
                      title: l10n.hostToggleArchenemy,
                      subtitle: l10n.hostToggleArchenemySubtitle,
                      value: config.archenemyEnabled,
                      onChanged:
                          (v) => notifier.updateConfig(
                            config.copyWith(archenemyEnabled: v),
                          ),
                    ),
                    tile(
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
        },
      );
    },
  );
}

/// Local D6 / D20 / coin — same tool set as Own View table tools, no Wi‑Fi.
Future<TableToolAnnouncement?> showOneViewDiceSheet(
  BuildContext context, {
  required String rollerName,
}) async {
  var kind = TableToolKind.d6;
  final l10n = AppLocalizations.of(context);
  final rolled = await showOneViewDialog<TableToolAnnouncement>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return OneViewMenuDialog(
            title: l10n.tableToolsTitle,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (final entry in [
                      (TableToolKind.d6, l10n.tableToolsD6),
                      (TableToolKind.d20, l10n.tableToolsD20),
                      (TableToolKind.coin, l10n.tableToolsCoin),
                    ]) ...[
                      if (entry.$1 != TableToolKind.d6)
                        SizedBox(width: LayoutTokens.gr1),
                      Expanded(
                        child: _ToolChoice(
                          label: entry.$2,
                          selected: kind == entry.$1,
                          onTap: () => setLocal(() => kind = entry.$1),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: LayoutTokens.gr3),
                FilledButton(
                  onPressed: () {
                    final announcement = rollOneViewTool(kind, rollerName);
                    Navigator.pop(ctx, announcement);
                  },
                  child: Text(switch (kind) {
                    TableToolKind.d6 => l10n.tableToolsRollD6,
                    TableToolKind.d20 => l10n.tableToolsRollD20,
                    TableToolKind.coin => l10n.tableToolsFlipCoin,
                  }),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  return rolled;
}

TableToolAnnouncement rollOneViewTool(TableToolKind kind, String rollerName) {
  final random = math.Random();
  return TableToolAnnouncement(
    id: 'ov-${DateTime.now().microsecondsSinceEpoch}',
    playerId: 'one-view',
    username: rollerName,
    kind: kind,
    dieValue:
        kind == TableToolKind.coin
            ? null
            : random.nextInt(kind == TableToolKind.d20 ? 20 : 6) + 1,
    coinHeads: kind == TableToolKind.coin ? random.nextBool() : null,
  );
}

/// Assign team colors to claimed seats. Only opened when teams are on.
Future<void> showOneViewColorsSheet(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  await showOneViewDialog<void>(
    context: context,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final seats = ref.watch(oneViewProvider.select((s) => s.seats));
          final claimed = seats.where((s) => s.isClaimed).toList();
          final body =
              claimed.isEmpty
                  ? Text(
                    l10n.oneViewColorsEmpty,
                    style: OneViewChrome.dialogBodyStyle(context),
                  )
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final seat in claimed) ...[
                        Text(
                          seat.displayName,
                          style: OneViewChrome.menuLabelStyle(context),
                        ),
                        SizedBox(height: LayoutTokens.gr2),
                        Wrap(
                          spacing: LayoutTokens.gr2,
                          runSpacing: LayoutTokens.gr2,
                          children: [
                            for (final idx in [0, 1, 2, 3, 4])
                              _TeamChoice(
                                index: idx,
                                selected: seat.teamIndex == idx,
                                onTap:
                                    () => ref
                                        .read(oneViewProvider.notifier)
                                        .assignTeam(seat.index, idx),
                              ),
                          ],
                        ),
                        SizedBox(height: LayoutTokens.gr4),
                      ],
                    ],
                  );
          return OneViewMenuDialog(title: l10n.oneViewColorsTitle, child: body);
        },
      );
    },
  );
}

class _TeamChoice extends StatelessWidget {
  const _TeamChoice({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final fill = index == 0 ? colors.backgroundSecondary : teamColor(index);
    final label =
        index == 0 ? l10n.overviewTeamNone : l10n.overviewTeamN('$index');
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: fill,
        shape: CircleBorder(
          side: BorderSide(
            color: selected ? colors.textPrimary : colors.borderSubtle,
            width: selected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 56,
            child:
                selected
                    ? Icon(
                      Icons.check_rounded,
                      color:
                          index == 0
                              ? colors.textPrimary
                              : ThemeData.estimateBrightnessForColor(fill) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black,
                    )
                    : index == 0
                    ? Icon(Icons.close_rounded, color: colors.textSecondary)
                    : null,
          ),
        ),
      ),
    );
  }
}

/// Add empty seats or remove a seat (confirm when filled).
Future<void> showOneViewPlayerCountSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context);
  await showOneViewDialog<void>(
    context: context,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final seats = ref.watch(oneViewProvider.select((s) => s.seats));
          final colors = AppColorTokens.of(context);
          final notifier = ref.read(oneViewProvider.notifier);
          final canRemove = seats.length > 1;
          return OneViewMenuDialog(
            title: l10n.oneViewPlayerCountTitle,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OneViewMenuAction(
                  icon: Icons.person_add_alt_1_rounded,
                  label: l10n.oneViewAddSeat,
                  enabled: seats.length < 6,
                  onTap: () {
                    notifier.addSeats(1);
                    Navigator.pop(ctx);
                  },
                ),
                for (final seat in seats.reversed)
                  OneViewMenuAction(
                    icon: Icons.person_remove_alt_1_rounded,
                    label:
                        seat.isEmpty
                            ? l10n.oneViewRemoveEmptySeat(seat.index + 1)
                            : l10n.oneViewRemoveFilledSeat(
                              seat.displayName,
                              seat.index + 1,
                            ),
                    color: colors.error,
                    enabled: canRemove,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await confirmAndRemoveSeat(context, ref, seat.index);
                    },
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _ToolChoice extends StatelessWidget {
  const _ToolChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorTokens.of(context);
    return Material(
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
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OneViewChrome.menuLabelStyle(
                context,
                color: selected ? colors.onAccent : colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plan: removing a filled seat asks to confirm; life totals stay on others.
Future<bool> confirmAndRemoveSeat(
  BuildContext context,
  WidgetRef ref,
  int seatIndex,
) async {
  final state = ref.read(oneViewProvider);
  if (seatIndex < 0 || seatIndex >= state.seats.length) return false;
  if (state.seats.length <= 1) return false;
  final seat = state.seats[seatIndex];
  final l10n = AppLocalizations.of(context);

  if (seat.isClaimed) {
    final ok = await showOneViewDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.oneViewRemoveSeatTitle),
            content: Text(l10n.oneViewRemoveSeatBody(seat.displayName)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.oneViewRemoveSeatConfirm),
              ),
            ],
          ),
    );
    if (ok != true) return false;
  }
  return ref.read(oneViewProvider.notifier).removeSeat(seatIndex);
}

/// Local result owns its dismissal and can roll again without opening a menu.
class OneViewDiceOverlay extends StatefulWidget {
  const OneViewDiceOverlay({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });
  final TableToolAnnouncement announcement;
  final VoidCallback onDismiss;

  @override
  State<OneViewDiceOverlay> createState() => _OneViewDiceOverlayState();
}

class _OneViewDiceOverlayState extends State<OneViewDiceOverlay> {
  late TableToolAnnouncement _announcement;

  @override
  void initState() {
    super.initState();
    _announcement = widget.announcement;
  }

  @override
  void didUpdateWidget(OneViewDiceOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.announcement.id != widget.announcement.id) {
      _announcement = widget.announcement;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      TableToolResultOverlay(
        announcement: _announcement,
        autoDismiss: null,
        onDismiss: widget.onDismiss,
        onRollAgain:
            () => setState(() {
              _announcement = rollOneViewTool(
                _announcement.kind,
                _announcement.username,
              );
            }),
      ),
    ],
  );
}
