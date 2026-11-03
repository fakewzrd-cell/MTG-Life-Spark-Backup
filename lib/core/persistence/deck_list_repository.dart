import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../deck/bracket_names.dart';
import '../deck/deck_list_text.dart';
import '../models/deck_card_entry.dart';

/// Hive box for the cards inside a deck. The deck cover stays on [PlayerDeck].
class DeckListRepository {
  static const boxName = 'deckCardEntries';

  Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<DeckCardEntry>(boxName);
    }
  }

  Box<DeckCardEntry> get _box => Hive.box<DeckCardEntry>(boxName);

  List<DeckCardEntry> getAll() {
    final list = _box.values.toList();
    list.sort((a, b) {
      final deck = a.deckId.compareTo(b.deckId);
      if (deck != 0) return deck;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  List<DeckCardEntry> entriesFor(String deckId) {
    final list = _box.values.where((entry) => entry.deckId == deckId).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<void> replaceDeckList(
    String deckId,
    List<ParsedDeckCard> cards,
  ) async {
    await init();
    await deleteForDeck(deckId);
    for (final card in cards) {
      final entry = DeckCardEntry(
        id: const Uuid().v4(),
        deckId: deckId,
        name: card.name,
        count: card.count,
        board: card.board.name,
      );
      await _box.put(entry.id, entry);
    }
  }

  /// Commander has no sideboard. Cards saved there move into the main deck.
  Future<bool> foldSideboardIntoMain(String deckId) async {
    await init();
    final side =
        entriesFor(
          deckId,
        ).where((entry) => entry.deckBoard == DeckBoard.sideboard).toList();
    if (side.isEmpty) return false;
    for (final entry in side) {
      await addToMain(deckId, entry.name, count: entry.count);
      await _box.delete(entry.id);
    }
    return true;
  }

  /// Puts one copy of [name] into the main deck.
  Future<void> addOneToMain(String deckId, String name) {
    return addToMain(deckId, name);
  }

  /// Adds [count] copies of [name] to the main deck.
  Future<void> addToMain(String deckId, String name, {int count = 1}) async {
    await init();
    if (count < 1) return;
    await _addToBoard(deckId, name, DeckBoard.main, count);
  }

  /// Moves one copy of [name] from one pile to the other.
  Future<bool> moveOne(
    String deckId,
    String name, {
    required DeckBoard from,
    required DeckBoard to,
  }) async {
    await init();
    if (from == to) return false;
    final key = bracketNameKey(name);
    DeckCardEntry? source;
    for (final entry in entriesFor(deckId)) {
      if (entry.deckBoard == from && bracketNameKey(entry.name) == key) {
        source = entry;
        break;
      }
    }
    if (source == null || source.count < 1) return false;
    final next = source.count - 1;
    if (next <= 0) {
      await _box.delete(source.id);
    } else {
      await _box.put(source.id, source.copyWith(count: next));
    }
    await _addToBoard(deckId, source.name, to, 1);
    return true;
  }

  Future<void> _addToBoard(
    String deckId,
    String name,
    DeckBoard board,
    int count,
  ) async {
    final key = bracketNameKey(name);
    for (final entry in entriesFor(deckId)) {
      if (entry.deckBoard == board && bracketNameKey(entry.name) == key) {
        final next = entry.count + count;
        await _box.put(entry.id, entry.copyWith(count: next > 99 ? 99 : next));
        return;
      }
    }
    final created = DeckCardEntry(
      id: const Uuid().v4(),
      deckId: deckId,
      name: name.trim(),
      count: count > 99 ? 99 : count,
      board: board.name,
    );
    await _box.put(created.id, created);
  }

  /// Changes the copy count of [name] on [board]. Returns true when the card
  /// is removed because the count fell to zero.
  Future<bool> changeCount(
    String deckId,
    String name, {
    required DeckBoard board,
    required int delta,
  }) async {
    await init();
    if (delta == 0) return false;
    final key = bracketNameKey(name);
    DeckCardEntry? existing;
    for (final entry in entriesFor(deckId)) {
      if (entry.deckBoard == board && bracketNameKey(entry.name) == key) {
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

  Future<void> copyDeck(String fromDeckId, String toDeckId) async {
    await init();
    for (final entry in entriesFor(fromDeckId)) {
      final copy = entry.copyWith(id: const Uuid().v4(), deckId: toDeckId);
      await _box.put(copy.id, copy);
    }
  }

  Future<void> deleteForDeck(String deckId) async {
    await init();
    final keys =
        _box.values
            .where((entry) => entry.deckId == deckId)
            .map((entry) => entry.id)
            .toList();
    await _box.deleteAll(keys);
  }

  /// Replace every saved card (used by backup restore).
  Future<void> replaceAll(List<DeckCardEntry> entries) async {
    await init();
    await _box.clear();
    for (final entry in entries) {
      await _box.put(entry.id, entry);
    }
  }
}
