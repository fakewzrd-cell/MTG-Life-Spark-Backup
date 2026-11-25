import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/game_constants.dart';
import '../game/game_format.dart';
import '../game/lobby_state.dart';
import '../models/player_deck.dart';
import '../persistence/providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/utils/commander_image_resolver.dart';

/// One claimed (or empty) seat on the One View table.
class OneViewSeat {
  final int index;
  final String? playerId;
  final String? username;
  final String? avatarUrl;
  final bool isGuest;
  final String? selectedDeckId;
  final String? commanderName;
  final String? commanderImageUrl;
  final List<String> commanderColorIdentity;
  final int life;
  final int poison;

  /// Commander damage dealt *to* this seat, keyed by source seat index.
  final Map<int, int> commanderDamageFrom;

  /// Team color index (0 = none). Center “colors” tool assigns this.
  final int teamIndex;
  final Color seatColor;

  const OneViewSeat({
    required this.index,
    this.playerId,
    this.username,
    this.avatarUrl,
    this.isGuest = false,
    this.selectedDeckId,
    this.commanderName,
    this.commanderImageUrl,
    this.commanderColorIdentity = const [],
    required this.life,
    this.poison = 0,
    this.commanderDamageFrom = const {},
    this.teamIndex = 0,
    required this.seatColor,
  });

  bool get isEmpty => playerId == null || playerId!.isEmpty;

  bool get isClaimed => !isEmpty;

  String get displayName {
    if (isEmpty) return '';
    if (isGuest) return username?.trim().isNotEmpty == true ? username! : 'Guest';
    return username ?? 'Player';
  }

  int get commanderDamageTotal =>
      commanderDamageFrom.values.fold(0, (a, b) => a + b);

  OneViewSeat copyWith({
    Object? playerId = _sentinel,
    Object? username = _sentinel,
    Object? avatarUrl = _sentinel,
    bool? isGuest,
    Object? selectedDeckId = _sentinel,
    Object? commanderName = _sentinel,
    Object? commanderImageUrl = _sentinel,
    Object? commanderColorIdentity = _sentinel,
    int? life,
    int? poison,
    Map<int, int>? commanderDamageFrom,
    int? teamIndex,
    Color? seatColor,
  }) {
    return OneViewSeat(
      index: index,
      playerId:
          identical(playerId, _sentinel) ? this.playerId : playerId as String?,
      username:
          identical(username, _sentinel) ? this.username : username as String?,
      avatarUrl:
          identical(avatarUrl, _sentinel)
              ? this.avatarUrl
              : avatarUrl as String?,
      isGuest: isGuest ?? this.isGuest,
      selectedDeckId:
          identical(selectedDeckId, _sentinel)
              ? this.selectedDeckId
              : selectedDeckId as String?,
      commanderName:
          identical(commanderName, _sentinel)
              ? this.commanderName
              : commanderName as String?,
      commanderImageUrl:
          identical(commanderImageUrl, _sentinel)
              ? this.commanderImageUrl
              : commanderImageUrl as String?,
      commanderColorIdentity:
          identical(commanderColorIdentity, _sentinel)
              ? this.commanderColorIdentity
              : List<String>.from(commanderColorIdentity as List<String>),
      life: life ?? this.life,
      poison: poison ?? this.poison,
      commanderDamageFrom:
          commanderDamageFrom ?? Map<int, int>.from(this.commanderDamageFrom),
      teamIndex: teamIndex ?? this.teamIndex,
      seatColor: seatColor ?? this.seatColor,
    );
  }

  static const Object _sentinel = Object();

  /// Empty placeholder seat for [seatCount] setup.
  factory OneViewSeat.empty({
    required int index,
    required int startingLife,
  }) {
    return OneViewSeat(
      index: index,
      life: startingLife,
      seatColor: AppTheme.playerColor(index),
    );
  }
}

class OneViewState {
  final LobbyConfig config;
  final List<OneViewSeat> seats;
  final bool started;
  final DateTime? startTime;

  const OneViewState({
    this.config = const LobbyConfig(),
    this.seats = const [],
    this.started = false,
    this.startTime,
  });

  int get seatCount => seats.length;

  OneViewState copyWith({
    LobbyConfig? config,
    List<OneViewSeat>? seats,
    bool? started,
    Object? startTime = _sentinel,
  }) {
    return OneViewState(
      config: config ?? this.config,
      seats: seats ?? this.seats,
      started: started ?? this.started,
      startTime:
          identical(startTime, _sentinel)
              ? this.startTime
              : startTime as DateTime?,
    );
  }

  static const Object _sentinel = Object();
}

class OneViewNotifier extends StateNotifier<OneViewState> {
  OneViewNotifier(this._ref) : super(const OneViewState());

  final Ref _ref;

  /// Prepare setup defaults from Settings (format + starting life).
  void prepareSetup({int? playerCount}) {
    final settings = _ref.read(settingsRepositoryProvider).settings;
    final format =
        GameFormatDetails.fromDisplayName(settings.defaultFormat) ??
        state.config.format;
    final life = settings.defaultStartingLife.clamp(1, 999);
    final count = LobbyConfig.clampMaxPlayers(playerCount ?? 4);
    state = OneViewState(
      config: LobbyConfig(
        format: format,
        startingLife: life,
        maxPlayers: count,
      ),
      seats: const [],
      started: false,
      startTime: null,
    );
  }

  void updateConfig(LobbyConfig config) {
    final clamped = config.copyWith(
      maxPlayers: LobbyConfig.clampMaxPlayers(config.maxPlayers),
    );
    state = state.copyWith(config: clamped);
  }

  void setPlayerCount(int count) {
    updateConfig(
      state.config.copyWith(
        maxPlayers: LobbyConfig.clampMaxPlayers(count),
      ),
    );
  }

  void setStartingLife(int life) {
    updateConfig(state.config.copyWith(startingLife: life.clamp(1, 999)));
  }

  /// Seeds empty seats from setup and marks the table as started.
  void startTable() {
    final n = LobbyConfig.clampMaxPlayers(state.config.maxPlayers);
    final life = state.config.startingLife.clamp(1, 999);
    final seats = List<OneViewSeat>.generate(
      n,
      (i) => OneViewSeat.empty(index: i, startingLife: life),
    );
    state = state.copyWith(
      seats: seats,
      started: true,
      startTime: DateTime.now(),
      config: state.config.copyWith(maxPlayers: n, startingLife: life),
    );
  }

  void reset() {
    state = const OneViewState();
  }

  bool _profileAlreadySeated(String playerId) {
    return state.seats.any((s) => s.playerId == playerId);
  }

  /// Sit as the local profile on [seatIndex]. Returns false if blocked.
  bool claimAsMe(int seatIndex) {
    if (!_validSeat(seatIndex)) return false;
    final seat = state.seats[seatIndex];
    if (seat.isClaimed) return false;

    final profile = _ref.read(profileRepositoryProvider).getProfile();
    if (profile == null) return false;
    if (_profileAlreadySeated(profile.playerId)) return false;

    _replaceSeat(
      seat.copyWith(
        playerId: profile.playerId,
        username: profile.username,
        avatarUrl: profile.profileAvatarImageUrl,
        isGuest: false,
        selectedDeckId: null,
        commanderName: null,
        commanderImageUrl: null,
        commanderColorIdentity: const <String>[],
      ),
    );
    return true;
  }

  /// Claim as guest with optional [name]. Guests skip deck pick.
  bool claimAsGuest(int seatIndex, {String? name}) {
    if (!_validSeat(seatIndex)) return false;
    final seat = state.seats[seatIndex];
    if (seat.isClaimed) return false;

    final guestId =
        'guest-$seatIndex-${DateTime.now().millisecondsSinceEpoch}';
    final trimmed = name?.trim();
    _replaceSeat(
      seat.copyWith(
        playerId: guestId,
        username: (trimmed == null || trimmed.isEmpty) ? 'Guest' : trimmed,
        avatarUrl: null,
        isGuest: true,
        selectedDeckId: null,
        commanderName: null,
        commanderImageUrl: null,
        commanderColorIdentity: const <String>[],
      ),
    );
    return true;
  }

  /// Claim from a sit-code scan (profile id + name + avatar). No Wi‑Fi session.
  bool claimFromSitCode({
    required int seatIndex,
    required String playerId,
    required String username,
    String? avatarUrl,
  }) {
    if (!_validSeat(seatIndex)) return false;
    final seat = state.seats[seatIndex];
    if (seat.isClaimed) return false;
    final id = playerId.trim();
    if (id.isEmpty) return false;
    if (_profileAlreadySeated(id)) return false;

    _replaceSeat(
      seat.copyWith(
        playerId: id,
        username: username.trim().isEmpty ? 'Player' : username.trim(),
        avatarUrl: avatarUrl,
        isGuest: false,
        selectedDeckId: null,
        commanderName: null,
        commanderImageUrl: null,
        commanderColorIdentity: const <String>[],
      ),
    );
    return true;
  }

  void applyDeck({required int seatIndex, required PlayerDeck deck}) {
    if (!_validSeat(seatIndex)) return;
    final seat = state.seats[seatIndex];
    if (seat.isEmpty || seat.isGuest) return;

    final profile = _ref.read(profileRepositoryProvider).getProfile();
    final commanderImageUrl =
        resolveDeckCommanderImageUrl(deck: deck, profile: profile) ??
        deck.commanderImageUrl;

    _replaceSeat(
      seat.copyWith(
        selectedDeckId: deck.id,
        commanderName: deck.commanderName,
        commanderImageUrl: commanderImageUrl,
        commanderColorIdentity: List<String>.from(deck.commanderColorIdentity),
      ),
    );
  }

  void clearDeck(int seatIndex) {
    if (!_validSeat(seatIndex)) return;
    final seat = state.seats[seatIndex];
    if (seat.isEmpty || seat.isGuest) return;
    _replaceSeat(
      seat.copyWith(
        selectedDeckId: null,
        commanderName: null,
        commanderImageUrl: null,
        commanderColorIdentity: const <String>[],
      ),
    );
  }

  void clearSeat(int seatIndex) {
    if (!_validSeat(seatIndex)) return;
    final life = state.config.startingLife;
    _replaceSeat(OneViewSeat.empty(index: seatIndex, startingLife: life));
  }

  void adjustLife(int seatIndex, int delta) {
    if (!_validSeat(seatIndex)) return;
    final seat = state.seats[seatIndex];
    final next = (seat.life + delta).clamp(-999, 999);
    _replaceSeat(seat.copyWith(life: next));
  }

  void setLife(int seatIndex, int life) {
    if (!_validSeat(seatIndex)) return;
    _replaceSeat(
      state.seats[seatIndex].copyWith(life: life.clamp(-999, 999)),
    );
  }

  void adjustPoison(int seatIndex, int delta) {
    if (!_validSeat(seatIndex)) return;
    final seat = state.seats[seatIndex];
    _replaceSeat(seat.copyWith(poison: (seat.poison + delta).clamp(0, 99)));
  }

  void adjustCommanderDamage({
    required int targetSeatIndex,
    required int fromSeatIndex,
    required int delta,
  }) {
    if (!_validSeat(targetSeatIndex) || !_validSeat(fromSeatIndex)) return;
    final seat = state.seats[targetSeatIndex];
    final map = Map<int, int>.from(seat.commanderDamageFrom);
    final next = ((map[fromSeatIndex] ?? 0) + delta).clamp(0, 99);
    if (next == 0) {
      map.remove(fromSeatIndex);
    } else {
      map[fromSeatIndex] = next;
    }
    var updated = seat.copyWith(commanderDamageFrom: map);
    if (state.config.commanderDamageReducesLife && delta != 0) {
      updated = updated.copyWith(life: (updated.life - delta).clamp(-999, 999));
    }
    _replaceSeat(updated);
  }

  /// Add empty seats mid-game (up to max).
  void addSeats(int count) {
    if (count <= 0) return;
    final life = state.config.startingLife;
    final seats = List<OneViewSeat>.from(state.seats);
    final room = GameConstants.maxLobbyPlayers - seats.length;
    final add = count.clamp(0, room);
    for (var i = 0; i < add; i++) {
      seats.add(OneViewSeat.empty(index: seats.length, startingLife: life));
    }
    state = state.copyWith(
      seats: seats,
      config: state.config.copyWith(maxPlayers: seats.length),
    );
  }

  /// Remove last seat when empty, or [seatIndex] after confirm by caller.
  bool removeSeat(int seatIndex) {
    if (!_validSeat(seatIndex)) return false;
    if (state.seats.length <= 1) return false;
    final seats = List<OneViewSeat>.from(state.seats)..removeAt(seatIndex);
    // Re-index
    final reindexed = <OneViewSeat>[];
    for (var i = 0; i < seats.length; i++) {
      final s = seats[i];
      reindexed.add(
        OneViewSeat(
          index: i,
          playerId: s.playerId,
          username: s.username,
          avatarUrl: s.avatarUrl,
          isGuest: s.isGuest,
          selectedDeckId: s.selectedDeckId,
          commanderName: s.commanderName,
          commanderImageUrl: s.commanderImageUrl,
          commanderColorIdentity: s.commanderColorIdentity,
          life: s.life,
          poison: s.poison,
          commanderDamageFrom: _remapDamageKeys(s.commanderDamageFrom, seatIndex),
          teamIndex: s.teamIndex,
          seatColor: AppTheme.playerColor(i),
        ),
      );
    }
    state = state.copyWith(
      seats: reindexed,
      config: state.config.copyWith(maxPlayers: reindexed.length),
    );
    return true;
  }

  void resetLifeTotals() {
    final life = state.config.startingLife;
    state = state.copyWith(
      seats:
          state.seats
              .map(
                (s) => s.copyWith(
                  life: life,
                  poison: 0,
                  commanderDamageFrom: const {},
                ),
              )
              .toList(),
    );
  }

  void assignTeam(int seatIndex, int teamIndex) {
    if (!_validSeat(seatIndex)) return;
    final seat = state.seats[seatIndex];
    _replaceSeat(seat.copyWith(teamIndex: teamIndex.clamp(0, 4)));
  }

  Map<int, int> _remapDamageKeys(Map<int, int> src, int removedIndex) {
    final out = <int, int>{};
    src.forEach((from, dmg) {
      if (from == removedIndex) return;
      final newKey = from > removedIndex ? from - 1 : from;
      out[newKey] = dmg;
    });
    return out;
  }

  bool _validSeat(int index) => index >= 0 && index < state.seats.length;

  void _replaceSeat(OneViewSeat seat) {
    final seats = List<OneViewSeat>.from(state.seats);
    seats[seat.index] = seat;
    state = state.copyWith(seats: seats);
  }
}

final oneViewProvider =
    StateNotifierProvider<OneViewNotifier, OneViewState>((ref) {
  return OneViewNotifier(ref);
});
