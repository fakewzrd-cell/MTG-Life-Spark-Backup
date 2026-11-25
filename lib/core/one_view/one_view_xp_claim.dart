import 'dart:convert';

import '../game/progression_service.dart';

/// Offline cross-phone XP handoff for sit-code seats (no cloud / Wi‑Fi game).
///
/// Host phone shows a claim QR after end-table; the friend scans it on their
/// Life Spark install. Payload scheme: `lifespark-xp:` + JSON.
class OneViewXpClaim {
  OneViewXpClaim._();

  static const schemePrefix = 'lifespark-xp:';

  static String build({
    required String matchId,
    required String playerId,
    required String username,
    required bool won,
    required int playerCount,
    required String format,
    required int startingLife,
    String? commanderName,
    List<String> opponentNames = const [],
    int durationSeconds = 0,
  }) {
    final payload = <String, dynamic>{
      'matchId': matchId,
      'pid': playerId,
      'name': username,
      'won': won,
      'playerCount': playerCount,
      'format': format,
      'startingLife': startingLife,
      if (commanderName != null && commanderName.isNotEmpty)
        'commander': commanderName,
      if (opponentNames.isNotEmpty) 'opponents': opponentNames,
      if (durationSeconds > 0) 'durationSec': durationSeconds,
    };
    return '$schemePrefix${jsonEncode(payload)}';
  }

  static OneViewXpClaimData? parse(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(schemePrefix)) return null;
    final body = trimmed.substring(schemePrefix.length);
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final matchId = (json['matchId'] as String?)?.trim() ?? '';
      final pid = (json['pid'] as String?)?.trim() ?? '';
      if (matchId.isEmpty || pid.isEmpty) return null;
      final opponents = json['opponents'];
      return OneViewXpClaimData(
        matchId: matchId,
        playerId: pid,
        username: ((json['name'] as String?)?.trim().isNotEmpty ?? false)
            ? (json['name'] as String).trim()
            : 'Player',
        won: json['won'] as bool? ?? false,
        playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
        format: (json['format'] as String?)?.trim() ?? 'Commander',
        startingLife: (json['startingLife'] as num?)?.toInt() ?? 40,
        commanderName: (json['commander'] as String?)?.trim(),
        opponentNames:
            opponents is List
                ? opponents.map((e) => e.toString()).toList()
                : const [],
        durationSeconds: (json['durationSec'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// XP the claiming device should award (first-win bonus applied there).
  static int xpForClaim({
    required bool won,
    required bool isFirstWin,
    required int playerCount,
  }) {
    if (playerCount < 2) return 0;
    var xp = kXpParticipate;
    if (won) {
      xp += kXpWin;
      if (isFirstWin) xp += kXpFirstWin;
    }
    return xp;
  }
}

class OneViewXpClaimData {
  const OneViewXpClaimData({
    required this.matchId,
    required this.playerId,
    required this.username,
    required this.won,
    required this.playerCount,
    required this.format,
    required this.startingLife,
    this.commanderName,
    this.opponentNames = const [],
    this.durationSeconds = 0,
  });

  final String matchId;
  final String playerId;
  final String username;
  final bool won;
  final int playerCount;
  final String format;
  final int startingLife;
  final String? commanderName;
  final List<String> opponentNames;
  final int durationSeconds;

  String get claimKey => '$matchId:$playerId';

  bool get didWin => won;
}
