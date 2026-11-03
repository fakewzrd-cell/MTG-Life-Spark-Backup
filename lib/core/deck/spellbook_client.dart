import 'dart:convert';

import 'package:http/http.dart' as http;

import '../debug/app_log.dart';
import 'bracket_floor.dart';

/// Two-card combos from Commander Spellbook. Unofficial public API.
class SpellbookClient {
  SpellbookClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint =
      'https://backend.commanderspellbook.com/find-my-combos';

  /// [failed] is true when the lookup did not complete. An empty combo list
  /// with [failed] false means the deck has no two-card combo.
  Future<({List<BracketCombo> combos, bool failed})> findTwoCardCombos({
    required List<String> commanders,
    required List<String> main,
  }) async {
    if (commanders.isEmpty && main.isEmpty) {
      return (combos: const <BracketCombo>[], failed: false);
    }
    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: const {
              'User-Agent': 'LifeSpark/1.0',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'commanders': [
                for (final name in commanders) {'card': name, 'quantity': 1},
              ],
              'main': [
                for (final name in main) {'card': name, 'quantity': 1},
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return (combos: const <BracketCombo>[], failed: true);
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) {
        return (combos: const <BracketCombo>[], failed: true);
      }
      final results = json['results'];
      if (results is! Map<String, dynamic>) {
        return (combos: const <BracketCombo>[], failed: true);
      }
      final included = results['included'];
      if (included is! List) {
        return (combos: const <BracketCombo>[], failed: true);
      }
      final combos = <BracketCombo>[];
      final seen = <String>{};
      for (final raw in included) {
        if (raw is! Map<String, dynamic>) continue;
        final uses = raw['uses'];
        if (uses is! List || uses.length != 2) continue;
        final names = <String>[];
        for (final use in uses) {
          if (use is! Map<String, dynamic>) continue;
          final card = use['card'];
          if (card is Map<String, dynamic>) {
            final name = (card['name'] as String?)?.trim() ?? '';
            if (name.isNotEmpty) names.add(name);
          }
        }
        if (names.length != 2) continue;
        names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final key = names.join('|');
        if (!seen.add(key)) continue;
        final mana = raw['manaValueNeeded'];
        combos.add(
          BracketCombo(
            cards: names,
            early: comboIsEarly(
              bracketTag: raw['bracketTag'] as String?,
              manaValueNeeded: mana is num ? mana.toInt() : null,
            ),
          ),
        );
      }
      return (combos: combos, failed: false);
    } catch (e, st) {
      appLog('Spellbook combo lookup failed', error: e, stackTrace: st);
      return (combos: const <BracketCombo>[], failed: true);
    }
  }
}
