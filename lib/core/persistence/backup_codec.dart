import '../models/collection_entry.dart';
import '../models/owned_album.dart';
import '../models/app_settings.dart';
import '../models/commander_stats.dart';
import '../models/deck_card_entry.dart';
import '../models/match_record.dart';
import '../models/player_deck.dart';
import '../models/player_profile.dart';

/// Marker + schema version for `.lifespark` backup files.
const kLifeSparkBackupFormat = 'life-spark-backup';

/// v1: profile, settings, decks, commanderStats.
/// v2: + match history + feedback ballots (sparks / behaviour source).
/// Deck card lists travel on the same versions as an optional `deckEntries` key
/// so an older app can still open the file.
const kLifeSparkBackupVersion = 2;

class LifeSparkBackup {
  const LifeSparkBackup({
    required this.version,
    required this.exportedAt,
    required this.profile,
    required this.settings,
    required this.decks,
    required this.commanderStats,
    this.matches = const [],
    this.feedbackByKey = const {},
    this.deckEntries = const [],
    this.collectionEntries = const [],
    this.ownedAlbums = const [],
    this.profileAvatarImageBase64,
    this.profileAvatarImageMime,
  });

  final int version;
  final DateTime exportedAt;
  final PlayerProfile profile;
  final AppSettings settings;
  final List<PlayerDeck> decks;
  final List<CommanderStats> commanderStats;
  final List<MatchRecord> matches;

  /// Cards inside each deck. Empty on backups made before lists existed.
  final List<DeckCardEntry> deckEntries;

  /// Cards the player owns, separate from any deck.
  final List<CollectionEntry> collectionEntries;

  /// Albums that group [collectionEntries]. Empty on older backups.
  final List<OwnedAlbum> ownedAlbums;

  /// Hive key → encoded [GameFeedback] JSON (preserves legacy keys).
  final Map<String, String> feedbackByKey;

  /// Local uploaded avatar bytes (when [profile.profileAvatarImageUrl] is a file).
  final String? profileAvatarImageBase64;
  final String? profileAvatarImageMime;

  Map<String, dynamic> toJson() => {
    'format': kLifeSparkBackupFormat,
    'version': version,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'profile': profileToJson(profile),
    'settings': settingsToJson(settings),
    'decks': decks.map(deckToJson).toList(),
    // Legacy key kept empty so older app builds can still parse exports.
    'pods': const <Map<String, dynamic>>[],
    'commanderStats': commanderStats.map(commanderStatsToJson).toList(),
    'matches': matches.map(matchToJson).toList(),
    'feedbackByKey': feedbackByKey,
    'deckEntries': deckEntries.map(deckEntryToJson).toList(),
    'collectionEntries': collectionEntries.map(collectionEntryToJson).toList(),
    'ownedAlbums': ownedAlbums.map(ownedAlbumToJson).toList(),
    if (profileAvatarImageBase64 != null &&
        profileAvatarImageBase64!.isNotEmpty)
      'profileAvatarImageBase64': profileAvatarImageBase64,
    if (profileAvatarImageMime != null && profileAvatarImageMime!.isNotEmpty)
      'profileAvatarImageMime': profileAvatarImageMime,
  };

  static LifeSparkBackup fromJson(Map<String, dynamic> json) {
    final format = json['format'] as String?;
    if (format != kLifeSparkBackupFormat) {
      throw const FormatException('Not a Life Spark backup file.');
    }
    final version = json['version'] as int? ?? 0;
    if (version < 1 || version > kLifeSparkBackupVersion) {
      throw FormatException('Unsupported backup version: $version');
    }
    final exportedRaw = json['exportedAt'] as String?;
    final profileJson = json['profile'];
    final settingsJson = json['settings'];
    if (profileJson is! Map || settingsJson is! Map) {
      throw const FormatException('Backup is missing profile or settings.');
    }

    return LifeSparkBackup(
      version: version,
      exportedAt:
          exportedRaw != null
              ? DateTime.tryParse(exportedRaw)?.toUtc() ??
                  DateTime.now().toUtc()
              : DateTime.now().toUtc(),
      profile: profileFromJson(Map<String, dynamic>.from(profileJson)),
      settings: settingsFromJson(Map<String, dynamic>.from(settingsJson)),
      decks: _listOfMaps(json['decks']).map(deckFromJson).toList(),
      // Older backups may still include pods; they are ignored.
      commanderStats:
          _listOfMaps(
            json['commanderStats'],
          ).map(commanderStatsFromJson).toList(),
      matches: _listOfMaps(json['matches']).map(matchFromJson).toList(),
      feedbackByKey: _stringMap(json['feedbackByKey']),
      deckEntries:
          _listOfMaps(json['deckEntries']).map(deckEntryFromJson).toList(),
      collectionEntries:
          _listOfMaps(
            json['collectionEntries'],
          ).map(collectionEntryFromJson).toList(),
      ownedAlbums:
          _listOfMaps(json['ownedAlbums']).map(ownedAlbumFromJson).toList(),
      profileAvatarImageBase64: _stringOrNull(json['profileAvatarImageBase64']),
      profileAvatarImageMime: _stringOrNull(json['profileAvatarImageMime']),
    );
  }
}

List<Map<String, dynamic>> _listOfMaps(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('Expected a JSON list.');
  }
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Map<String, String> _stringMap(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw const FormatException('Expected a JSON object.');
  }
  return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
}

String? _stringOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.map((e) => e.toString()).toList();
}

Map<String, dynamic> profileToJson(PlayerProfile p) => {
  'username': p.username,
  'playerId': p.playerId,
  'level': p.level,
  'xp': p.xp,
  'tier': p.tier,
  'totalWins': p.totalWins,
  'totalLosses': p.totalLosses,
  'selectedCommanderName': p.selectedCommanderName,
  'selectedCommanderImageUrl': p.selectedCommanderImageUrl,
  'selectedPartnerCommanderName': p.selectedPartnerCommanderName,
  'selectedPartnerCommanderImageUrl': p.selectedPartnerCommanderImageUrl,
  'unlockedThemes': p.unlockedThemes,
  'unlockedBadges': p.unlockedBadges,
  'lifetimePoisonDealt': p.lifetimePoisonDealt,
  'lifetimeCommanderKills': p.lifetimeCommanderKills,
  'currentWinStreak': p.currentWinStreak,
  'totalGamesPlayed': p.totalGamesPlayed,
  'profileAvatarImageUrl': p.profileAvatarImageUrl,
  'likesReceived': p.likesReceived,
  'dislikesReceived': p.dislikesReceived,
  'honorsStarReceived': p.honorsStarReceived,
  'honorsTeamPlayerReceived': p.honorsTeamPlayerReceived,
  'honorsUnderdogReceived': p.honorsUnderdogReceived,
  'profileBannerImageUrl': p.profileBannerImageUrl,
  'profileExtraStatIds': p.profileExtraStatIds,
};

PlayerProfile profileFromJson(Map<String, dynamic> json) => PlayerProfile(
  username:
      (json['username'] as String?)?.trim().isNotEmpty == true
          ? (json['username'] as String).trim()
          : 'Planeswalker',
  playerId: (json['playerId'] as String?) ?? '',
  level: (json['level'] as num?)?.toInt() ?? 1,
  xp: (json['xp'] as num?)?.toInt() ?? 0,
  tier: (json['tier'] as String?) ?? 'Bronze',
  totalWins: (json['totalWins'] as num?)?.toInt() ?? 0,
  totalLosses: (json['totalLosses'] as num?)?.toInt() ?? 0,
  selectedCommanderName: _stringOrNull(json['selectedCommanderName']),
  selectedCommanderImageUrl: _stringOrNull(json['selectedCommanderImageUrl']),
  selectedPartnerCommanderName: _stringOrNull(
    json['selectedPartnerCommanderName'],
  ),
  selectedPartnerCommanderImageUrl: _stringOrNull(
    json['selectedPartnerCommanderImageUrl'],
  ),
  unlockedThemes:
      _stringList(json['unlockedThemes']).isEmpty
          ? const ['default']
          : _stringList(json['unlockedThemes']),
  unlockedBadges: _stringList(json['unlockedBadges']),
  lifetimePoisonDealt: (json['lifetimePoisonDealt'] as num?)?.toInt() ?? 0,
  lifetimeCommanderKills:
      (json['lifetimeCommanderKills'] as num?)?.toInt() ?? 0,
  currentWinStreak: (json['currentWinStreak'] as num?)?.toInt() ?? 0,
  totalGamesPlayed: (json['totalGamesPlayed'] as num?)?.toInt() ?? 0,
  profileAvatarImageUrl: _stringOrNull(json['profileAvatarImageUrl']),
  likesReceived: (json['likesReceived'] as num?)?.toInt() ?? 0,
  dislikesReceived: (json['dislikesReceived'] as num?)?.toInt() ?? 0,
  honorsStarReceived: (json['honorsStarReceived'] as num?)?.toInt() ?? 0,
  honorsTeamPlayerReceived:
      (json['honorsTeamPlayerReceived'] as num?)?.toInt() ?? 0,
  honorsUnderdogReceived:
      (json['honorsUnderdogReceived'] as num?)?.toInt() ?? 0,
  profileBannerImageUrl: _stringOrNull(json['profileBannerImageUrl']),
  profileExtraStatIds: _stringList(json['profileExtraStatIds']),
);

Map<String, dynamic> settingsToJson(AppSettings s) => {
  'hapticEnabled': s.hapticEnabled,
  'soundEnabled': s.soundEnabled,
  'defaultFormat': s.defaultFormat,
  'defaultStartingLife': s.defaultStartingLife,
  'scryfallCacheEnabled': s.scryfallCacheEnabled,
  'shakeToUndoEnabled': s.shakeToUndoEnabled,
  'onboardingCompleted': s.onboardingCompleted,
  'keepDisplayAwake': s.keepDisplayAwake,
  'hideSystemBars': s.hideSystemBars,
  'useDarkTheme': s.useDarkTheme,
  'colorSchemeId': s.colorSchemeId,
  'lifeGestureHintDismissed': s.lifeGestureHintDismissed,
  'hubGuideCompleted': s.hubGuideCompleted,
  'localeCode': s.localeCode,
};

AppSettings settingsFromJson(Map<String, dynamic> json) => AppSettings(
  hapticEnabled: json['hapticEnabled'] as bool? ?? true,
  soundEnabled: json['soundEnabled'] as bool? ?? true,
  defaultFormat: (json['defaultFormat'] as String?) ?? 'Commander',
  defaultStartingLife: (json['defaultStartingLife'] as num?)?.toInt() ?? 40,
  scryfallCacheEnabled: json['scryfallCacheEnabled'] as bool? ?? true,
  shakeToUndoEnabled: json['shakeToUndoEnabled'] as bool? ?? true,
  onboardingCompleted: json['onboardingCompleted'] as bool? ?? true,
  keepDisplayAwake: json['keepDisplayAwake'] as bool? ?? true,
  hideSystemBars: json['hideSystemBars'] as bool? ?? false,
  useDarkTheme: json['useDarkTheme'] as bool? ?? true,
  colorSchemeId: (json['colorSchemeId'] as String?) ?? 'violet',
  lifeGestureHintDismissed: json['lifeGestureHintDismissed'] as bool? ?? false,
  hubGuideCompleted: json['hubGuideCompleted'] as bool? ?? false,
  localeCode: (json['localeCode'] as String?) ?? 'system',
);

Map<String, dynamic> deckToJson(PlayerDeck d) => {
  'id': d.id,
  'displayName': d.displayName,
  'commanderName': d.commanderName,
  'commanderImageUrl': d.commanderImageUrl,
  'partnerCommanderName': d.partnerCommanderName,
  'partnerCommanderImageUrl': d.partnerCommanderImageUrl,
  'wins': d.wins,
  'losses': d.losses,
  'gamesPlayed': d.gamesPlayed,
  'commanderManaCost': d.commanderManaCost,
  'partnerManaCost': d.partnerManaCost,
  'commanderColorIdentity': d.commanderColorIdentity,
  'format': d.format,
  'deckStyleId': d.deckStyleId,
  'isPinned': d.isPinned,
  'chosenBracket': d.chosenBracket,
};

PlayerDeck deckFromJson(Map<String, dynamic> json) {
  final id = (json['id'] as String?)?.trim();
  final displayName = (json['displayName'] as String?)?.trim();
  final commanderName = (json['commanderName'] as String?)?.trim();
  if (id == null ||
      id.isEmpty ||
      displayName == null ||
      displayName.isEmpty ||
      commanderName == null ||
      commanderName.isEmpty) {
    throw const FormatException('Deck entry is missing required fields.');
  }
  return PlayerDeck(
    id: id,
    displayName: displayName,
    commanderName: commanderName,
    commanderImageUrl: _stringOrNull(json['commanderImageUrl']),
    partnerCommanderName: _stringOrNull(json['partnerCommanderName']),
    partnerCommanderImageUrl: _stringOrNull(json['partnerCommanderImageUrl']),
    wins: (json['wins'] as num?)?.toInt() ?? 0,
    losses: (json['losses'] as num?)?.toInt() ?? 0,
    gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
    commanderManaCost: _stringOrNull(json['commanderManaCost']),
    partnerManaCost: _stringOrNull(json['partnerManaCost']),
    commanderColorIdentity: _stringList(json['commanderColorIdentity']),
    format: (json['format'] as String?) ?? 'commander',
    deckStyleId: (json['deckStyleId'] as String?) ?? '',
    isPinned: json['isPinned'] as bool? ?? false,
    chosenBracket: (json['chosenBracket'] as num?)?.toInt(),
  );
}

Map<String, dynamic> deckEntryToJson(DeckCardEntry entry) => {
  'id': entry.id,
  'deckId': entry.deckId,
  'name': entry.name,
  'count': entry.count,
  'board': entry.board,
};

DeckCardEntry deckEntryFromJson(Map<String, dynamic> json) {
  final id = (json['id'] as String?)?.trim();
  final deckId = (json['deckId'] as String?)?.trim();
  final name = (json['name'] as String?)?.trim();
  if (id == null ||
      id.isEmpty ||
      deckId == null ||
      deckId.isEmpty ||
      name == null ||
      name.isEmpty) {
    throw const FormatException('Deck card entry is missing required fields.');
  }
  final count = (json['count'] as num?)?.toInt() ?? 1;
  return DeckCardEntry(
    id: id,
    deckId: deckId,
    name: name,
    count: count < 1 ? 1 : count,
    board: (json['board'] as String?) ?? DeckBoard.main.name,
  );
}

Map<String, dynamic> collectionEntryToJson(CollectionEntry entry) => {
  'id': entry.id,
  'name': entry.name,
  'count': entry.count,
  if (entry.albumId != null && entry.albumId!.isNotEmpty)
    'albumId': entry.albumId,
};

Map<String, dynamic> ownedAlbumToJson(OwnedAlbum album) => {
  'id': album.id,
  'name': album.name,
  'createdAtMillis': album.createdAtMillis,
};

OwnedAlbum ownedAlbumFromJson(Map<String, dynamic> json) {
  final id = (json['id'] as String?)?.trim();
  final name = (json['name'] as String?)?.trim();
  if (id == null || id.isEmpty || name == null || name.isEmpty) {
    throw const FormatException('Collection album is missing required fields.');
  }
  return OwnedAlbum(
    id: id,
    name: name,
    createdAtMillis: (json['createdAtMillis'] as num?)?.toInt() ?? 0,
  );
}

CollectionEntry collectionEntryFromJson(Map<String, dynamic> json) {
  final id = (json['id'] as String?)?.trim();
  final name = (json['name'] as String?)?.trim();
  if (id == null || id.isEmpty || name == null || name.isEmpty) {
    throw const FormatException('Collection entry is missing required fields.');
  }
  final count = (json['count'] as num?)?.toInt() ?? 1;
  final albumId = (json['albumId'] as String?)?.trim();
  return CollectionEntry(
    id: id,
    name: name,
    count: count < 1 ? 1 : count,
    albumId: albumId == null || albumId.isEmpty ? null : albumId,
  );
}

Map<String, dynamic> commanderStatsToJson(CommanderStats s) => {
  'commanderName': s.commanderName,
  'wins': s.wins,
  'losses': s.losses,
  'gamesPlayed': s.gamesPlayed,
};

CommanderStats commanderStatsFromJson(Map<String, dynamic> json) {
  final name = (json['commanderName'] as String?)?.trim();
  if (name == null || name.isEmpty) {
    throw const FormatException('Commander stats entry is missing a name.');
  }
  return CommanderStats(
    commanderName: name,
    wins: (json['wins'] as num?)?.toInt() ?? 0,
    losses: (json['losses'] as num?)?.toInt() ?? 0,
    gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
  );
}

Map<String, dynamic> matchToJson(MatchRecord m) => {
  'matchId': m.matchId,
  'date': m.date.toUtc().toIso8601String(),
  'commanderName': m.commanderName,
  'partnerCommanderName': m.partnerCommanderName,
  'opponentNames': m.opponentNames,
  'result': m.result,
  'eliminationReason': m.eliminationReason,
  'format': m.format,
  'durationMinutes': m.durationMinutes,
  'startingLifeTotal': m.startingLifeTotal,
  'playerCount': m.playerCount,
  'durationSeconds': m.durationSeconds,
  'participantsJson': m.participantsJson,
  'labelSnapshot': m.labelSnapshot,
  'locationSnapshot': m.locationSnapshot,
  'localDeckIdSnapshot': m.localDeckIdSnapshot,
};

MatchRecord matchFromJson(Map<String, dynamic> json) {
  final matchId = (json['matchId'] as String?)?.trim();
  if (matchId == null || matchId.isEmpty) {
    throw const FormatException('Match entry is missing matchId.');
  }
  final dateRaw = json['date'] as String?;
  final date =
      dateRaw != null
          ? DateTime.tryParse(dateRaw)?.toUtc() ?? DateTime.now().toUtc()
          : DateTime.now().toUtc();
  return MatchRecord(
    matchId: matchId,
    date: date,
    commanderName: (json['commanderName'] as String?) ?? '',
    partnerCommanderName: _stringOrNull(json['partnerCommanderName']),
    opponentNames: _stringList(json['opponentNames']),
    result: (json['result'] as String?) ?? 'loss',
    eliminationReason: (json['eliminationReason'] as String?) ?? 'survived',
    format: (json['format'] as String?) ?? 'Commander',
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    startingLifeTotal: (json['startingLifeTotal'] as num?)?.toInt() ?? 40,
    playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
    durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
    participantsJson: _stringOrNull(json['participantsJson']),
    labelSnapshot: _stringOrNull(json['labelSnapshot']),
    locationSnapshot: _stringOrNull(json['locationSnapshot']),
    localDeckIdSnapshot: _stringOrNull(json['localDeckIdSnapshot']),
  );
}
