import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../deck/bracket_names.dart';
import 'scryfall_service.dart';

/// Local name → Scryfall card lookup so album art can start without a network
/// round-trip on the second open.
class ScryfallCardCache {
  ScryfallCardCache({Map<String, String>? memory}) : _memory = memory;

  static const boxName = 'scryfallCardCache';
  static const ttl = Duration(days: 30);

  final Map<String, String>? _memory;

  Future<void> init() async {
    if (_memory != null) return;
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<String>(boxName);
    }
    await purgeExpired();
  }

  ScryfallCard? read(String name) {
    final key = bracketNameKey(name);
    final raw = _readRaw(key);
    if (raw == null) return null;
    if (_isExpired(raw)) {
      _evict(key);
      return null;
    }
    return _decode(raw);
  }

  Map<String, ScryfallCard> readMany(Iterable<String> names) {
    final out = <String, ScryfallCard>{};
    for (final name in names) {
      final card = read(name);
      if (card == null) continue;
      out[bracketNameKey(card.name)] = card;
    }
    return out;
  }

  Future<void> writeAll(Iterable<ScryfallCard> cards) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final entries = <String, String>{};
    for (final card in cards) {
      final key = bracketNameKey(card.name);
      if (key.isEmpty) continue;
      entries[key] = jsonEncode({'fetchedAt': now, 'card': card.toJson()});
    }
    if (entries.isEmpty) return;
    if (_memory != null) {
      _memory.addAll(entries);
      return;
    }
    if (!Hive.isBoxOpen(boxName)) return;
    await Hive.box<String>(boxName).putAll(entries);
  }

  Future<void> clear() async {
    if (_memory != null) {
      _memory.clear();
      return;
    }
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<String>(boxName);
    }
    if (Hive.isBoxOpen(boxName)) {
      await Hive.box<String>(boxName).clear();
    }
  }

  Future<void> purgeExpired() async {
    final keys = <String>[];
    if (_memory != null) {
      keys.addAll(_memory.keys);
    } else if (Hive.isBoxOpen(boxName)) {
      keys.addAll(Hive.box<String>(boxName).keys.cast<String>());
    }
    for (final key in keys) {
      final raw = _readRaw(key);
      if (raw != null && _isExpired(raw)) {
        await _evictAsync(key);
      }
    }
  }

  String? _readRaw(String key) {
    if (key.isEmpty) return null;
    if (_memory != null) return _memory[key];
    if (!Hive.isBoxOpen(boxName)) return null;
    return Hive.box<String>(boxName).get(key);
  }

  bool _isExpired(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return true;
      final fetchedAtRaw = json['fetchedAt'] as String?;
      if (fetchedAtRaw == null) return true;
      final fetchedAt = DateTime.tryParse(fetchedAtRaw);
      if (fetchedAt == null) return true;
      return DateTime.now().toUtc().difference(fetchedAt) > ttl;
    } catch (_) {
      return true;
    }
  }

  void _evict(String key) {
    unawaited(_evictAsync(key));
  }

  Future<void> _evictAsync(String key) async {
    if (_memory != null) {
      _memory.remove(key);
      return;
    }
    if (!Hive.isBoxOpen(boxName)) return;
    await Hive.box<String>(boxName).delete(key);
  }

  ScryfallCard? _decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final cardJson = json['card'];
      if (cardJson is! Map<String, dynamic>) return null;
      final card = ScryfallCard.fromJson(cardJson);
      if (card.name.trim().isEmpty) return null;
      return card;
    } catch (_) {
      return null;
    }
  }
}
