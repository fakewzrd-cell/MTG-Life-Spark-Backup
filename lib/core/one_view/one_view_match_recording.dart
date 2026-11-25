import '../game/game_state.dart';
import '../game/lobby_state.dart';
import '../game/player_game_state.dart';
import '../game/progression_service.dart';
import '../models/player_slot.dart';
import 'one_view_state.dart';

/// Builds lobby + game snapshots from One View for on-device match recording.
///
/// Plan: save names/ids/decks on this phone; no XP push to other phones.
/// Winner is unset on manual end-table (participation XP when 2+ seated).
({LobbyState lobby, GameState game})? oneViewRecordingSnapshots({
  required OneViewState oneView,
  required String? localPlayerId,
}) {
  final claimed = oneView.seats.where((s) => s.isClaimed).toList();
  if (claimed.isEmpty) return null;

  final players =
      claimed.map((s) {
        final cmdDmg = <String, List<int>>{};
        s.commanderDamageFrom.forEach((fromIndex, dmg) {
          if (fromIndex < 0 || fromIndex >= oneView.seats.length) return;
          final from = oneView.seats[fromIndex];
          if (!from.isClaimed || from.playerId == null) return;
          cmdDmg[from.playerId!] = [dmg, 0];
        });
        return PlayerGameState(
          playerId: s.playerId!,
          username: s.displayName,
          playerColor: s.seatColor,
          commanderName: s.commanderName,
          commanderImageUrl: s.commanderImageUrl,
          commanderColorIdentity: s.commanderColorIdentity,
          selectedDeckId: s.isGuest ? null : s.selectedDeckId,
          life: s.life,
          poison: s.poison,
          commanderDamage: cmdDmg,
        );
      }).toList();

  final slots =
      claimed
          .map(
            (s) => PlayerSlot(
              playerId: s.playerId!,
              username: s.displayName,
              playerColor: s.seatColor,
              commanderName: s.commanderName,
              commanderImageUrl: s.commanderImageUrl,
              commanderColorIdentity: s.commanderColorIdentity,
              selectedDeckId: s.isGuest ? null : s.selectedDeckId,
              isReady: true,
            ),
          )
          .toList();

  final localId = localPlayerId ?? '';
  final localSeated = players.any((p) => p.playerId == localId);

  final teamAssignments = <String, int>{
    for (final s in claimed)
      if (s.teamIndex > 0) s.playerId!: s.teamIndex,
  };

  final lobby = LobbyState(
    players: slots,
    config: oneView.config,
    isHost: true,
    isGameStarted: true,
  );

  final game = GameState(
    players: players,
    turnOrder: players.map((p) => p.playerId).toList(),
    activePlayerIndex: 0,
    alliancesEnabled: oneView.config.alliancesEnabled,
    teamsEnabled: oneView.config.teamsEnabled || teamAssignments.isNotEmpty,
    isHost: true,
    localPlayerId: localSeated ? localId : '',
    teamAssignments: teamAssignments,
    gameStartTime: oneView.startTime ?? DateTime.now(),
    autoKoFromLife: oneView.config.autoKoFromLife,
    autoKoFromPoison: oneView.config.autoKoFromPoison,
    autoKoFromCommanderDamage: oneView.config.autoKoFromCommanderDamage,
    commanderDamageReducesLife: oneView.config.commanderDamageReducesLife,
    turnTimeLimitSeconds: oneView.config.turnTimeLimitSeconds,
    trackTurnDuration: oneView.config.trackTurnDuration,
    phasesEnabled: oneView.config.phasesEnabled,
    planechaseEnabled: oneView.config.planechaseEnabled,
    archenemyEnabled: oneView.config.archenemyEnabled,
    bountyEnabled: oneView.config.bountyEnabled,
  );

  return (lobby: lobby, game: game);
}

/// Whether [ProgressionService.recordMatch] can award XP for this table.
bool oneViewCanAwardProgression(GameState game) =>
    matchAwardsProgression(game) && game.localPlayerId.isNotEmpty;
