import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game/game_session_events.dart';
import '../../core/one_view/one_view_state.dart';
import '../../features/game/widgets/game_modal_chrome.dart';
import '../../features/game/widgets/table_tool_result_overlay.dart';
import '../../features/game/widgets/team_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_color_tokens.dart';
import '../../ui/tokens/font_tokens.dart';
import '../../ui/tokens/layout_tokens.dart';

/// Mid-game LobbyConfig toggles from the center menu (plan: settings changeable).
Future<void> showOneViewSettingsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  await showGameBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final config = ref.watch(oneViewProvider.select((s) => s.config));
          final notifier = ref.read(oneViewProvider.notifier);
          final l10n = AppLocalizations.of(context);
          final colors = AppColorTokens.of(context);
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
              title: Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: FontTokens.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                subtitle,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: FontTokens.hudSm,
                  height: 1.3,
                ),
              ),
              value: value,
              onChanged: onChanged,
            );
          }

          return GameSheetBody(
            scrollable: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                GameSheetHeader(title: l10n.oneViewMidGameSettings),
                SizedBox(height: LayoutTokens.gr2),
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
  final rolled = await showGameBottomSheet<TableToolAnnouncement>(
    context: context,
    enableDrag: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          final colors = AppColorTokens.of(context);
          return GameSheetBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GameSheetHeader(
                  title: l10n.tableToolsTitle,
                  subtitle: l10n.tableToolsSubtitle,
                ),
                SizedBox(height: LayoutTokens.gr3),
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
                        child: ChoiceChip(
                          label: Text(entry.$2),
                          selected: kind == entry.$1,
                          onSelected: (_) => setLocal(() => kind = entry.$1),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: LayoutTokens.gr4),
                Text(
                  l10n.tableToolsResultHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
                SizedBox(height: LayoutTokens.gr3),
                FilledButton(
                  onPressed: () {
                    final rand = math.Random();
                    final announcement = switch (kind) {
                      TableToolKind.d6 => TableToolAnnouncement(
                        id: 'ov-${DateTime.now().microsecondsSinceEpoch}',
                        playerId: 'one-view',
                        username: rollerName,
                        kind: TableToolKind.d6,
                        dieValue: rand.nextInt(6) + 1,
                      ),
                      TableToolKind.d20 => TableToolAnnouncement(
                        id: 'ov-${DateTime.now().microsecondsSinceEpoch}',
                        playerId: 'one-view',
                        username: rollerName,
                        kind: TableToolKind.d20,
                        dieValue: rand.nextInt(20) + 1,
                      ),
                      TableToolKind.coin => TableToolAnnouncement(
                        id: 'ov-${DateTime.now().microsecondsSinceEpoch}',
                        playerId: 'one-view',
                        username: rollerName,
                        kind: TableToolKind.coin,
                        coinHeads: rand.nextBool(),
                      ),
                    };
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

/// Assign team colors to claimed seats. Only opened when teams are on.
Future<void> showOneViewColorsSheet(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  await showGameBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final seats = ref.watch(oneViewProvider.select((s) => s.seats));
          final claimed = seats.where((s) => s.isClaimed).toList();
          final colors = AppColorTokens.of(context);
          if (claimed.isEmpty) {
            return GameSheetBody(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GameSheetHeader(title: l10n.oneViewColorsTitle),
                  SizedBox(height: LayoutTokens.gr2),
                  Text(
                    l10n.oneViewColorsEmpty,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: FontTokens.body,
                    ),
                  ),
                ],
              ),
            );
          }
          return GameSheetBody(
            scrollable: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                GameSheetHeader(title: l10n.oneViewColorsTitle),
                SizedBox(height: LayoutTokens.gr3),
                for (final seat in claimed) ...[
                  Text(
                    seat.displayName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: FontTokens.headline,
                      fontWeight: FontWeight.w600,
                    ),
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
            ),
          );
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
                index == 0
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
  await showGameBottomSheet<void>(
    context: context,
    enableDrag: false,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          final seats = ref.watch(oneViewProvider.select((s) => s.seats));
          final colors = AppColorTokens.of(context);
          final notifier = ref.read(oneViewProvider.notifier);
          return GameSheetBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GameSheetHeader(title: l10n.oneViewPlayerCountTitle),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: Text(l10n.oneViewAddSeat),
                  enabled: seats.length < 6,
                  onTap:
                      seats.length >= 6
                          ? null
                          : () {
                            notifier.addSeats(1);
                            Navigator.pop(ctx);
                          },
                ),
                for (final seat in seats.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.person_remove_alt_1_rounded,
                      color: colors.error,
                    ),
                    title: Text(
                      seat.isEmpty
                          ? l10n.oneViewRemoveEmptySeat(seat.index + 1)
                          : l10n.oneViewRemoveFilledSeat(
                            seat.displayName,
                            seat.index + 1,
                          ),
                      style: TextStyle(color: colors.error),
                    ),
                    enabled: seats.length > 1,
                    onTap:
                        seats.length <= 1
                            ? null
                            : () async {
                              Navigator.pop(ctx);
                              await confirmAndRemoveSeat(
                                context,
                                ref,
                                seat.index,
                              );
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
    final ok = await showDialog<bool>(
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

/// Full-screen local dice/coin result for One View (no gameProvider).
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
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reuse Own View result chrome; dismiss is owned locally above.
    return Stack(
      children: [
        IgnorePointer(
          child: TableToolResultOverlay(announcement: widget.announcement),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
          ),
        ),
      ],
    );
  }
}
