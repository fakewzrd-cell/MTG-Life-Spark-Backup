import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/game_constants.dart';
import '../game/game_format.dart';
import '../game/lobby_state.dart';
import '../models/player_deck.dart';
import '../models/player_profile.dart';
import '../persistence/providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/utils/commander_image_resolver.dart';
import 'one_view_layout.dart';

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

  /// Commander art when the seat has one, otherwise the profile photo.
  String? get cardArtUrl {
    final commander = commanderImageUrl?.trim();
    if (commander != null && commander.isNotEmpty) return commander;
    final avatar = avatarUrl?.trim();
    if (avatar != null && avatar.isNotEmpty) return avatar;
    return null;
  }

  String get displayName {
    if (isEmpty) return '';
    if (isGuest)
      return username?.trim().isNotEmpty == true ? username! : 'Guest';
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
  factory OneViewSeat.empty({required int index, required int startingLife}) {
    return OneViewSeat(
      index: index,
      life: startingLife,
      seatColor: AppTheme.playerColor(index),
    );
  }
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// Deck and picture already saved on a profile.
///
/// One deck, or the deck whose commander matches the profile, is applied.
/// With no deck, the profile commander's picture is used. The profile photo
/// stays available when there is no commander art.
class OneViewProfileSeatIdentity {
  const OneViewProfileSeatIdentity({
    this.deckId,
    this.commanderName,
    this.commanderImageUrl,
    this.colorIdentity = const [],
    this.avatarUrl,
  });

  final String? deckId;
  final String? commanderName;
  final String? commanderImageUrl;
  final List<String> colorIdentity;
  final String? avatarUrl;
}

OneViewProfileSeatIdentity oneViewProfileSeatIdentity({
  required PlayerProfile profile,
  required Iterable<PlayerDeck> decks,
  required GameFormat format,
}) {
  final eligible = [
    for (final deck in decks)
      if (!isPreviewPlaceholderDeck(deck) &&
          deck.matchesLobbyFormat(format) &&
          deck.hasDeckStyle)
        deck,
  ];
  final selectedName =
      _trimmedOrNull(profile.selectedCommanderName)?.toLowerCase();
  PlayerDeck? deck;
  if (selectedName != null) {
    for (final candidate in eligible) {
      if (candidate.commanderName.trim().toLowerCase() == selectedName) {
        deck = candidate;
        break;
      }
    }
  }
  deck ??= eligible.length == 1 ? eligible.single : null;

  String? commanderName;
  String? commanderImageUrl;
  var colors = const <String>[];
  String? deckId;
  if (deck != null) {
    deckId = deck.id;
    commanderName = _trimmedOrNull(deck.commanderName);
    colors = List<String>.from(deck.commanderColorIdentity);
    commanderImageUrl = _trimmedOrNull(
      resolveDeckCommanderImageUrl(deck: deck, profile: profile),
    );
  } else {
    commanderImageUrl = _trimmedOrNull(profile.selectedCommanderImageUrl);
    if (commanderImageUrl != null) {
      commanderName = _trimmedOrNull(profile.selectedCommanderName);
    }
  }

  return OneViewProfileSeatIdentity(
    deckId: deckId,
    commanderName: commanderName,
    commanderImageUrl: commanderImageUrl,
    colorIdentity: colors,
    avatarUrl: _trimmedOrNull(profile.profileAvatarImageUrl),
  );
}

class OneViewState {
  final LobbyConfig config;
  final List<OneViewSeat> seats;
  final bool started;
  final DateTime? startTime;
  final OneViewSeatLayout layout;

  const OneViewState({
    this.config = const LobbyConfig(),
    this.seats = const [],
    this.started = false,
    this.startTime,
    this.layout = OneViewSeatLayout.grid2x2,
  });

  int get seatCount => seats.length;

  OneViewState copyWith({
    LobbyConfig? config,
    List<OneViewSeat>? seats,
    bool? started,
    Object? startTime = _sentinel,
    OneViewSeatLayout? layout,
  }) {
    return OneViewState(
      config: config ?? this.config,
      seats: seats ?? this.seats,
      started: started ?? this.started,
      startTime:
          identical(startTime, _sentinel)
              ? this.startTime
              : startTime as DateTime?,
      layout: layout ?? this.layout,
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
      state.config.copyWith(maxPlayers: LobbyConfig.clampMaxPlayers(count)),
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
      layout: OneViewSeatLayout.defaultFor(n),
    );
  }

  /// Sitting arrangement for the current player count. Ignored if it does not fit.
  void setLayout(OneViewSeatLayout layout) {
    final count = state.seats.length;
    if (count < 1 || !layout.fits(count)) return;
    state = state.copyWith(layout: layout);
  }

  void reset() {
    state = const OneViewState();
  }

  bool _profileAlreadySeated(String playerId) {
    return state.seats.any((s) => s.playerId == playerId);
  }

  /// Sit as the local profile on [seatIndex]. Returns false if blocked.
  ///
  /// Uses that profile's deck commander art, or their profile photo. The
  /// player is not asked to search for a card.
  bool claimAsMe(int seatIndex) {
    if (!_validSeat(seatIndex)) return false;
    final seat = state.seats[seatIndex];
    if (seat.isClaimed) return false;

    final profile = _ref.read(profileRepositoryProvider).getProfile();
    if (profile == null) return false;
    if (_profileAlreadySeated(profile.playerId)) return false;

    final identity = oneViewProfileSeatIdentity(
      profile: profile,
      decks: _ref.read(deckRepositoryProvider).getAll(),
      format: state.config.format,
    );
    _replaceSeat(
      seat.copyWith(
        playerId: profile.playerId,
        username: profile.username,
        avatarUrl: identity.avatarUrl,
        isGuest: false,
        selectedDeckId: identity.deckId,
        commanderName: identity.commanderName,
        commanderImageUrl: identity.commanderImageUrl,
        commanderColorIdentity: identity.colorIdentity,
      ),
    );
    return true;
  }

  /// Claim as guest with optional [name]. Guests skip deck pick.
  bool claimAsGuest(int seatIndex, {String? name}) {
    if (!_validSeat(seatIndex)) return false;
    final seat = state.seats[seatIndex];
    if (seat.isClaimed) return false;

    final guestId = 'guest-$seatIndex-${DateTime.now().millisecondsSinceEpoch}';
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

    final local = _ref.read(profileRepositoryProvider).getProfile();
    final scannedAvatar = _trimmedOrNull(avatarUrl);
    String? deckId;
    String? commanderName;
    String? commanderImageUrl;
    var colors = const <String>[];
    var avatar = scannedAvatar;
    // This phone only has decks for the local profile. Another player's
    // code contributes their photo and nothing else.
    if (local != null && local.playerId == id) {
      final identity = oneViewProfileSeatIdentity(
        profile: local,
        decks: _ref.read(deckRepositoryProvider).getAll(),
        format: state.config.format,
      );
      deckId = identity.deckId;
      commanderName = identity.commanderName;
      commanderImageUrl = identity.commanderImageUrl;
      colors = identity.colorIdentity;
      avatar ??= identity.avatarUrl;
    }

    _replaceSeat(
      seat.copyWith(
        playerId: id,
        username: username.trim().isEmpty ? 'Player' : username.trim(),
        avatarUrl: avatar,
        isGuest: false,
        selectedDeckId: deckId,
        commanderName: commanderName,
        commanderImageUrl: commanderImageUrl,
        commanderColorIdentity: colors,
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

  /// Commander or any card art for this seat, including guests.
  void setCommanderVisual({
    required int seatIndex,
    required String name,
    required String? imageUrl,
    List<String> colorIdentity = const [],
  }) {
    if (!_validSeat(seatIndex)) return;
    final seat = state.seats[seatIndex];
    if (seat.isEmpty) return;
    final trimmed = name.trim();
    _replaceSeat(
      seat.copyWith(
        commanderName: trimmed.isEmpty ? null : trimmed,
        commanderImageUrl: imageUrl,
        commanderColorIdentity: colorIdentity,
      ),
    );
  }

  void clearCommanderVisual(int seatIndex) {
    if (!_validSeat(seatIndex)) return;
    final seat = state.seats[seatIndex];
    if (seat.isEmpty) return;
    _replaceSeat(
      seat.copyWith(
        commanderName: null,
        commanderImageUrl: null,
        commanderColorIdentity: const <String>[],
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

  /// Rename a claimed seat. A blank name is ignored.
  ///
  /// When the seat is this phone's profile, the profile name is saved too.
  Future<void> renameSeat(int seatIndex, String name) async {
    if (!_validSeat(seatIndex)) return;
    final seat = state.seats[seatIndex];
    if (!seat.isClaimed) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == seat.username) return;
    _replaceSeat(seat.copyWith(username: trimmed));
    final profile = _ref.read(profileRepositoryProvider).getProfile();
    if (profile == null || profile.playerId != seat.playerId) return;
    profile.username = trimmed;
    await _ref.read(profileRepositoryProvider).saveProfile(profile);
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
    _replaceSeat(state.seats[seatIndex].copyWith(life: life.clamp(-999, 999)));
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
      layout: _layoutForCount(seats.length),
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
          commanderDamageFrom: _remapDamageKeys(
            s.commanderDamageFrom,
            seatIndex,
          ),
          teamIndex: s.teamIndex,
          seatColor: AppTheme.playerColor(i),
        ),
      );
    }
    state = state.copyWith(
      seats: reindexed,
      config: state.config.copyWith(maxPlayers: reindexed.length),
      layout: _layoutForCount(reindexed.length),
    );
    return true;
  }

  OneViewSeatLayout _layoutForCount(int count) {
    if (state.layout.fits(count)) return state.layout;
    return OneViewSeatLayout.defaultFor(count);
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

final oneViewProvider = StateNotifierProvider<OneViewNotifier, OneViewState>((
  ref,
) {
  return OneViewNotifier(ref);
});
