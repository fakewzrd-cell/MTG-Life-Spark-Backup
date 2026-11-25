import 'dart:convert';

/// Profile sit-code payload for One View seat claim (no Wi‑Fi game session).
///
/// Encoded as `lifespark-sit:` + JSON: `{pid, name, avatar?}`.
class OneViewSitCode {
  OneViewSitCode._();

  static const schemePrefix = 'lifespark-sit:';

  static String build({
    required String playerId,
    required String username,
    String? avatarUrl,
  }) {
    final payload = <String, dynamic>{
      'pid': playerId,
      'name': username,
      if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatar': avatarUrl,
    };
    return '$schemePrefix${jsonEncode(payload)}';
  }

  /// Returns null when [raw] is not a valid sit code.
  static ({String playerId, String username, String? avatarUrl})? parse(
    String raw,
  ) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(schemePrefix)) return null;
    final body = trimmed.substring(schemePrefix.length);
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final pid = (json['pid'] as String?)?.trim() ?? '';
      final name = (json['name'] as String?)?.trim() ?? '';
      if (pid.isEmpty) return null;
      final avatar = (json['avatar'] as String?)?.trim();
      return (
        playerId: pid,
        username: name.isEmpty ? 'Player' : name,
        avatarUrl: (avatar == null || avatar.isEmpty) ? null : avatar,
      );
    } catch (_) {
      return null;
    }
  }
}
