import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/app_log.dart';
import 'package:http/http.dart' as http;

class ScryfallCard {
  /// Scryfall UUID — needed for `/cards/{id}/rulings`.
  final String? id;
  final String name;
  final String? imageUrl; // null = offline / not found

  /// Full card face (`normal`), distinct from the art crop in [imageUrl].
  final String? cardFaceUrl;
  final String? oracleText;

  /// Scryfall `mana_cost`, e.g. `{2}{W}{U}`; may be null on some card layouts.
  final String? manaCost;

  /// Scryfall `type_line`, e.g. `Instant` or `Legendary Creature — Human Wizard`.
  final String? typeLine;
  final bool isPartner;

  /// Scryfall `color_identity`: subset of `W`,`U`,`B`,`R`,`G` (empty = colorless).
  final List<String> colorIdentity;

  /// Scryfall `produced_mana`: colors this card can add (`W`,`U`,`B`,`R`,`G`,`C`).
  final List<String> producedMana;

  /// Names of tokens listed on this card (`all_parts` where component is token).
  final List<String> tokenNames;

  const ScryfallCard({
    this.id,
    required this.name,
    this.imageUrl,
    this.cardFaceUrl,
    this.oracleText,
    this.manaCost,
    this.typeLine,
    this.isPartner = false,
    this.colorIdentity = const [],
    this.producedMana = const [],
    this.tokenNames = const [],
  });

  /// Local placeholder path when the network is unavailable.
  static const offlineImageAsset = 'assets/placeholders/card_placeholder.png';

  /// Commander color identity union (partner decks): sorted WUBRG.
  static List<String> unionColorIdentity(
    ScryfallCard primary,
    ScryfallCard? partner,
  ) {
    const order = ['W', 'U', 'B', 'R', 'G'];
    final set = <String>{};
    for (final c in primary.colorIdentity) {
      if (order.contains(c)) set.add(c);
    }
    if (partner != null) {
      for (final c in partner.colorIdentity) {
        if (order.contains(c)) set.add(c);
      }
    }
    final out = order.where(set.contains).toList();
    return out;
  }
}

/// One official ruling from Scryfall (`/cards/{id}/rulings`).
class ScryfallRuling {
  const ScryfallRuling({required this.comment, this.publishedAt, this.source});

  final String comment;
  final String? publishedAt;
  final String? source;
}

class ScryfallService {
  static const _base = 'https://api.scryfall.com';

  /// Scryfall requires User-Agent and Accept headers; requests without them
  /// may be blocked or return 400/403.
  static final _headers = {
    'User-Agent': 'MGT-Life-Spark/1.0 (Commander life tracker)',
    'Accept': 'application/json',
  };

  final http.Client _client;

  ScryfallService({http.Client? client}) : _client = client ?? http.Client();

  // ── Search ────────────────────────────────────────────────────────────────

  /// Returns any MTG cards matching [query] (for avatar selection, etc.).
  /// Throws on network/parse errors; returns empty list only when no results.
  Future<List<ScryfallCard>> searchCards(String query) async {
    if (query.trim().isEmpty) return [];
    final encoded = Uri.encodeComponent('name:${query.trim()} game:paper');
    final uri = Uri.parse(
      '$_base/cards/search?q=$encoded&order=name&unique=cards',
    );
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      throw Exception('Scryfall API error: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];
    return data
        .map((card) => _parseCard(card as Map<String, dynamic>))
        .toList();
  }

  /// Returns commanders matching [query].
  /// Filters to legendary creatures that can be your commander.
  /// Throws on network/parse errors; returns empty list only when no results.
  Future<List<ScryfallCard>> searchCommanders(String query) async {
    if (query.trim().isEmpty) return [];
    final encoded = Uri.encodeComponent(
      'is:commander name:${query.trim()} game:paper',
    );
    final uri = Uri.parse(
      '$_base/cards/search?q=$encoded&order=name&unique=cards',
    );
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return []; // No results
    if (response.statusCode != 200) {
      throw Exception('Scryfall API error: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];

    return data
        .map((card) => _parseCard(card as Map<String, dynamic>))
        .toList();
  }

  // ── Variant decks (Planechase, Archenemy, Bounty) ─────────────────────────

  /// Fetches all planar and phenomenon cards for Planechase.
  /// Requires internet. Returns empty list on error.
  Future<List<ScryfallCard>> fetchPlanarDeck() async {
    return _fetchVariantDeck(
      '(type:plane OR type:phenomenon) game:paper',
      includeExtras: true,
    );
  }

  /// Fetches all scheme cards for Archenemy.
  Future<List<ScryfallCard>> fetchSchemeDeck() async {
    return _fetchVariantDeck('type:scheme game:paper');
  }

  /// Fetches all bounty cards for Bounty minigame.
  Future<List<ScryfallCard>> fetchBountyDeck() async {
    return _fetchVariantDeck('is:bounty game:paper');
  }

  Future<List<ScryfallCard>> _fetchVariantDeck(
    String query, {
    bool includeExtras = false,
  }) async {
    final cards = <ScryfallCard>[];
    String? nextPage =
        '$_base/cards/search?q=${Uri.encodeComponent(query)}&order=name&unique=cards${includeExtras ? '&include_extras=true' : ''}';

    while (nextPage != null) {
      final uri = Uri.parse(nextPage);
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return cards;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? [];
      for (final c in data) {
        cards.add(_parseCard(c as Map<String, dynamic>));
      }
      nextPage = json['next_page'] as String?;
    }
    return cards;
  }

  // ── Fetch by exact name ───────────────────────────────────────────────────

  /// Fuzzy match for a single card name (stack picker confirm).
  Future<ScryfallCard?> fetchCardFuzzy(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    try {
      final encoded = Uri.encodeComponent(trimmed);
      final uri = Uri.parse('$_base/cards/named?fuzzy=$encoded');
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseCard(json);
    } catch (e, st) {
      appLog('Scryfall fuzzy fetch failed for $name', error: e, stackTrace: st);
      return null;
    }
  }

  /// Fetches a single card by exact name (for loading saved commanders).
  Future<ScryfallCard?> fetchCardByName(String name) async {
    try {
      final encoded = Uri.encodeComponent(name);
      final uri = Uri.parse('$_base/cards/named?exact=$encoded');
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseCard(json);
    } catch (e, st) {
      appLog('Scryfall exact fetch failed for $name', error: e, stackTrace: st);
      return null;
    }
  }

  /// Exact-name lookup for a deck list. Scryfall accepts 75 names per request.
  ///
  /// Cards that are not found are omitted. A failed request returns the cards
  /// collected so far so a partial album can still render.
  Future<List<ScryfallCard>> fetchCardsByNames(List<String> names) async {
    final unique = <String>[];
    final seen = <String>{};
    for (final raw in names) {
      final name = raw.trim();
      final key = name.toLowerCase();
      if (name.isEmpty || !seen.add(key)) continue;
      unique.add(name);
    }
    if (unique.isEmpty) return const [];

    final found = <ScryfallCard>[];
    const batchSize = 75;
    for (var start = 0; start < unique.length; start += batchSize) {
      if (start > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final end =
          start + batchSize > unique.length ? unique.length : start + batchSize;
      final chunk = unique.sublist(start, end);
      try {
        final uri = Uri.parse('$_base/cards/collection');
        final response = await _client
            .post(
              uri,
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'identifiers': [
                  for (final name in chunk) {'name': name},
                ],
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) continue;
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as List<dynamic>? ?? [];
        for (final raw in data) {
          if (raw is Map<String, dynamic>) found.add(_parseCard(raw));
        }
      } catch (e, st) {
        appLog('Scryfall collection fetch failed', error: e, stackTrace: st);
      }
    }
    return found;
  }

  /// Official Wizards / Scryfall rulings for a card UUID from [ScryfallCard.id].
  ///
  /// Empty list: the card has no rulings, or [cardId] is missing.
  /// Null: the request failed, so the UI must not claim there are no rulings.
  Future<List<ScryfallRuling>?> fetchRulings(String? cardId) async {
    final id = cardId?.trim();
    if (id == null || id.isEmpty) return const [];
    try {
      final uri = Uri.parse('$_base/cards/$id/rulings');
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) return const [];
      if (response.statusCode != 200) {
        throw Exception('Scryfall rulings error: ${response.statusCode}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? [];
      return [
        for (final raw in data)
          if (raw is Map<String, dynamic>)
            ScryfallRuling(
              comment: (raw['comment'] as String?)?.trim() ?? '',
              publishedAt: raw['published_at'] as String?,
              source: raw['source'] as String?,
            ),
      ].where((r) => r.comment.isNotEmpty).toList();
    } catch (e, st) {
      appLog('Scryfall rulings fetch failed for $id', error: e, stackTrace: st);
      return null;
    }
  }

  static String? _imageUri(Map<String, dynamic>? uris, List<String> keys) {
    if (uris == null) return null;
    for (final key in keys) {
      final value = uris[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  ScryfallCard _parseCard(Map<String, dynamic> card) {
    final id = card['id'] as String?;
    final name = card['name'] as String? ?? '';

    // Double-faced cards store images in card_faces[].
    final imageUris = card['image_uris'] as Map<String, dynamic>?;
    Map<String, dynamic>? faceUris;
    final earlyFaces = card['card_faces'] as List<dynamic>?;
    if (imageUris == null && earlyFaces != null && earlyFaces.isNotEmpty) {
      faceUris =
          (earlyFaces[0] as Map<String, dynamic>)['image_uris']
              as Map<String, dynamic>?;
    }
    final uris = imageUris ?? faceUris;
    final imageUrl = _imageUri(uris, const ['art_crop', 'normal']);
    final cardFaceUrl = _imageUri(uris, const [
      'normal',
      'large',
      'png',
      'border_crop',
      'art_crop',
    ]);

    final faces = card['card_faces'] as List<dynamic>?;
    final firstFace =
        faces != null && faces.isNotEmpty
            ? faces[0] as Map<String, dynamic>
            : null;

    final oracleText =
        card['oracle_text'] as String? ??
        (firstFace != null ? firstFace['oracle_text'] as String? : null);

    var manaCost = card['mana_cost'] as String?;
    if (manaCost == null || manaCost.isEmpty) {
      manaCost = firstFace != null ? firstFace['mana_cost'] as String? : null;
    }

    var typeLine = card['type_line'] as String?;
    if (typeLine == null || typeLine.isEmpty) {
      typeLine = firstFace != null ? firstFace['type_line'] as String? : null;
    }

    final keywords = List<String>.from(card['keywords'] as List? ?? []);
    final isPartner =
        keywords.contains('Partner') || keywords.contains('Friends forever');

    final ciRaw = card['color_identity'];
    final colorIdentity =
        ciRaw is List
            ? ciRaw
                .map((e) => e.toString())
                .where((s) => s.length == 1)
                .toList()
            : <String>[];

    final producedRaw = card['produced_mana'];
    final producedMana =
        producedRaw is List
            ? producedRaw.map((e) => e.toString()).toList()
            : <String>[];

    final tokenNames = <String>[];
    final parts = card['all_parts'];
    if (parts is List) {
      final seenTokens = <String>{};
      for (final part in parts) {
        if (part is! Map) continue;
        if (part['component'] != 'token') continue;
        final tokenName = part['name'] as String?;
        if (tokenName == null ||
            tokenName.isEmpty ||
            !seenTokens.add(tokenName)) {
          continue;
        }
        tokenNames.add(tokenName);
      }
    }

    return ScryfallCard(
      id: id,
      name: name,
      imageUrl: imageUrl,
      cardFaceUrl: cardFaceUrl,
      oracleText: oracleText,
      manaCost: manaCost,
      typeLine: typeLine,
      isPartner: isPartner,
      colorIdentity: colorIdentity,
      producedMana: producedMana,
      tokenNames: tokenNames,
    );
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final scryfallServiceProvider = Provider<ScryfallService>((ref) {
  return ScryfallService();
});
