import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../debug/app_log.dart';
import 'bracket_names.dart';

/// Cached commander page from EDHREC's unofficial JSON. Commander only.
class CommanderMeta {
  const CommanderMeta({
    required this.themeTags,
    required this.inclusionByKey,
    required this.commonCards,
  });

  final List<String> themeTags;
  final Map<String, double> inclusionByKey;
  final List<String> commonCards;

  double? inclusionFor(String name) => inclusionByKey[bracketNameKey(name)];
}

class EdhrecClient {
  EdhrecClient({http.Client? client, Duration? cacheFor})
    : _client = client ?? http.Client(),
      _cacheFor = cacheFor ?? const Duration(days: 7);

  static const boxName = 'edhrecCache';

  final http.Client _client;
  final Duration _cacheFor;

  Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<String>(boxName);
    }
  }

  /// Null when the feed is unavailable and nothing is cached.
  Future<CommanderMeta?> commanderMeta(String commanderName) async {
    final slug = commanderSlug(commanderName);
    if (slug.isEmpty) return null;
    await init();
    final box = Hive.box<String>(boxName);
    final cached = box.get(slug);
    if (cached != null) {
      final stored = _decode(cached);
      if (stored != null &&
          DateTime.now().toUtc().difference(stored.fetchedAt) < _cacheFor) {
        return stored.meta;
      }
    }
    try {
      final uri = Uri.parse(
        'https://json.edhrec.com/pages/commanders/$slug.json',
      );
      final response = await _client
          .get(
            uri,
            headers: const {
              'User-Agent': 'LifeSpark/1.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return _metaOrNull(cached);
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return _metaOrNull(cached);
      final meta = _parse(json);
      await box.put(
        slug,
        jsonEncode({
          'fetchedAt': DateTime.now().toUtc().toIso8601String(),
          'themeTags': meta.themeTags,
          'inclusion': meta.inclusionByKey,
          'commonCards': meta.commonCards,
        }),
      );
      return meta;
    } catch (e, st) {
      appLog(
        'EDHREC lookup failed for $commanderName',
        error: e,
        stackTrace: st,
      );
      return _metaOrNull(cached);
    }
  }

  CommanderMeta? _metaOrNull(String? cached) => _decode(cached)?.meta;

  _StoredMeta? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final fetched = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
      if (fetched == null) return null;
      final tags =
          (json['themeTags'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      final inclusionRaw = json['inclusion'];
      final inclusion = <String, double>{};
      if (inclusionRaw is Map) {
        inclusionRaw.forEach((key, value) {
          if (value is num) inclusion[key.toString()] = value.toDouble();
        });
      }
      final common =
          (json['commonCards'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      return _StoredMeta(
        fetchedAt: fetched.toUtc(),
        meta: CommanderMeta(
          themeTags: tags,
          inclusionByKey: inclusion,
          commonCards: common,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  CommanderMeta _parse(Map<String, dynamic> json) {
    final tags = <String>[];
    final tagCounts = json['tag_counts'];
    if (tagCounts is List) {
      final rows = <({String name, int count})>[];
      for (final raw in tagCounts) {
        if (raw is! Map) continue;
        final name = (raw['value'] as String?)?.trim() ?? '';
        final count = (raw['count'] as num?)?.toInt() ?? 0;
        if (name.isEmpty) continue;
        rows.add((name: name, count: count));
      }
      rows.sort((a, b) => b.count.compareTo(a.count));
      tags.addAll(rows.take(4).map((row) => row.name));
    }

    final inclusion = <String, double>{};
    final named = <String, double>{};
    final container = json['container'];
    final dict = container is Map ? container['json_dict'] : null;
    final lists = dict is Map ? dict['cardlists'] : null;
    if (lists is List) {
      for (final list in lists) {
        if (list is! Map) continue;
        final views = list['cardviews'];
        if (views is! List) continue;
        for (final view in views) {
          if (view is! Map) continue;
          final name = (view['name'] as String?)?.trim() ?? '';
          if (name.isEmpty) continue;
          final rate = _inclusion(view);
          final key = bracketNameKey(name);
          final previous = inclusion[key];
          if (previous == null || rate > previous) {
            inclusion[key] = rate;
            named[name] = rate;
          }
        }
      }
    }
    final ranked =
        named.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return CommanderMeta(
      themeTags: tags,
      inclusionByKey: inclusion,
      commonCards: ranked.take(99).map((entry) => entry.key).toList(),
    );
  }

  double _inclusion(Map view) {
    final direct = view['inclusion'];
    if (direct is num) return direct.toDouble();
    final decks = view['num_decks'];
    final potential = view['potential_decks'];
    if (decks is num && potential is num && potential > 0) {
      return decks / potential;
    }
    return 0;
  }
}

class _StoredMeta {
  const _StoredMeta({required this.fetchedAt, required this.meta});

  final DateTime fetchedAt;
  final CommanderMeta meta;
}

String commanderSlug(String name) => bracketNameKey(name)
    .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '-');
