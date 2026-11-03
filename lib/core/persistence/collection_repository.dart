import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../deck/bracket_names.dart';
import '../deck/deck_list_text.dart';
import '../models/collection_entry.dart';
import '../models/owned_album.dart';

class CollectionRepository {
  static const boxName = 'collectionEntries';
  static const albumBoxName = 'ownedAlbums';

  Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<CollectionEntry>(boxName);
    }
    if (!Hive.isBoxOpen(albumBoxName)) {
      await Hive.openBox<OwnedAlbum>(albumBoxName);
    }
  }

  Box<CollectionEntry> get _box => Hive.box<CollectionEntry>(boxName);
  Box<OwnedAlbum> get _albums => Hive.box<OwnedAlbum>(albumBoxName);

  List<OwnedAlbum> getAlbums() {
    final list = _albums.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<CollectionEntry> getAll() {
    final list = _box.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<CollectionEntry> forAlbum(String albumId) {
    final list =
        _box.values.where((entry) => entry.albumId == albumId).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  int cardCount(String albumId) =>
      _box.values.where((entry) => entry.albumId == albumId).length;

  /// Cards saved before albums existed are gathered into one album.
  Future<void> adoptLooseCards(String albumName) async {
    await init();
    final loose = _box.values.where((entry) => entry.albumId == null).toList();
    if (loose.isEmpty) return;
    final album = await createAlbum(albumName);
    for (final entry in loose) {
      await _box.put(entry.id, entry.copyWith(albumId: album.id));
    }
  }

  Future<OwnedAlbum> createAlbum(String name) async {
    await init();
    final album = OwnedAlbum(
      id: const Uuid().v4(),
      name: name.trim(),
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await _albums.put(album.id, album);
    return album;
  }

  Future<void> renameAlbum(String id, String name) async {
    await init();
    final album = _albums.get(id);
    if (album == null) return;
    await _albums.put(id, album.copyWith(name: name.trim()));
  }

  Future<void> deleteAlbum(String id) async {
    await init();
    final owned = _box.values.where((entry) => entry.albumId == id).toList();
    for (final entry in owned) {
      await _box.delete(entry.id);
    }
    await _albums.delete(id);
  }

  Future<void> replaceAlbum(String albumId, List<ParsedDeckCard> cards) async {
    await init();
    final existing = _box.values.where((entry) => entry.albumId == albumId);
    for (final entry in existing.toList()) {
      await _box.delete(entry.id);
    }
    await _putParsed(cards, albumId: albumId);
  }

  Future<void> _putParsed(List<ParsedDeckCard> cards, {String? albumId}) async {
    final merged = <String, int>{};
    final display = <String, String>{};
    for (final card in cards) {
      final key = bracketNameKey(card.name);
      if (key.isEmpty) continue;
      merged[key] = (merged[key] ?? 0) + card.count;
      display.putIfAbsent(key, () => card.name);
    }
    for (final entry in merged.entries) {
      final stored = CollectionEntry(
        id: const Uuid().v4(),
        name: display[entry.key]!,
        count: entry.value,
        albumId: albumId,
      );
      await _box.put(stored.id, stored);
    }
  }

  /// Adds [count] copies of [name] inside [albumId].
  Future<void> addOwned(String name, {int count = 1, String? albumId}) async {
    await init();
    if (count < 1) return;
    final key = bracketNameKey(name);
    if (key.isEmpty) return;
    CollectionEntry? existing;
    for (final entry in _box.values) {
      if (entry.albumId != albumId) continue;
      if (bracketNameKey(entry.name) == key) {
        existing = entry;
        break;
      }
    }
    if (existing == null) {
      final stored = CollectionEntry(
        id: const Uuid().v4(),
        name: name.trim(),
        count: count,
        albumId: albumId,
      );
      await _box.put(stored.id, stored);
      return;
    }
    final updated = existing.copyWith(count: existing.count + count);
    await _box.put(existing.id, updated);
  }

  /// Changes how many copies of [name] are in [albumId]. Returns true when
  /// the card is removed because the count fell to zero.
  Future<bool> changeOwned(
    String name, {
    required int delta,
    String? albumId,
  }) async {
    await init();
    if (delta == 0) return false;
    if (delta > 0) {
      await addOwned(name, count: delta, albumId: albumId);
      return false;
    }
    final key = bracketNameKey(name);
    CollectionEntry? existing;
    for (final entry in _box.values) {
      if (entry.albumId != albumId) continue;
      if (bracketNameKey(entry.name) == key) {
        existing = entry;
        break;
      }
    }
    if (existing == null) return false;
    final next = existing.count + delta;
    if (next <= 0) {
      await _box.delete(existing.id);
      return true;
    }
    await _box.put(
      existing.id,
      existing.copyWith(count: next > 99 ? 99 : next),
    );
    return false;
  }

  Future<void> replaceAll(List<CollectionEntry> entries) async {
    await init();
    await _box.clear();
    for (final entry in entries) {
      await _box.put(entry.id, entry);
    }
  }

  Future<void> replaceAlbums(List<OwnedAlbum> albums) async {
    await init();
    await _albums.clear();
    for (final album in albums) {
      await _albums.put(album.id, album);
    }
  }
}
