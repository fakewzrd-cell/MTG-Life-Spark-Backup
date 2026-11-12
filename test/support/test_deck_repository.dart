import 'package:mgt_life_spark/core/models/player_deck.dart';
import 'package:mgt_life_spark/core/persistence/deck_repository.dart';

/// In-memory deck repo for widget/integration tests (no Hive).
class TestDeckRepository extends DeckRepository {
  TestDeckRepository({List<PlayerDeck>? decks})
    : _decks = List<PlayerDeck>.from(decks ?? const []);

  final List<PlayerDeck> _decks;

  @override
  List<PlayerDeck> getAll() => List<PlayerDeck>.from(_decks);

  @override
  PlayerDeck? getById(String id) {
    for (final d in _decks) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  Future<void> save(PlayerDeck deck) async {
    deck.updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
    final index = _decks.indexWhere((d) => d.id == deck.id);
    if (index >= 0) {
      _decks[index] = deck;
    } else {
      _decks.add(deck);
    }
  }

  @override
  Future<void> markUpdated(String id) async {
    final deck = getById(id);
    if (deck == null) return;
    await save(deck);
  }
}
