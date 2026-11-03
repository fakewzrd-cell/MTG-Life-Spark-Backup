import 'package:hive/hive.dart';

/// Which board a saved card belongs to.
enum DeckBoard {
  commander,
  main,
  sideboard;

  static DeckBoard fromName(String? raw) {
    for (final board in DeckBoard.values) {
      if (board.name == raw) return board;
    }
    return DeckBoard.main;
  }
}

/// One card in a saved deck list. Images and rules stay on Scryfall.
@HiveType(typeId: 7)
class DeckCardEntry {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String deckId;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final int count;

  /// [DeckBoard.name].
  @HiveField(4)
  final String board;

  const DeckCardEntry({
    required this.id,
    required this.deckId,
    required this.name,
    required this.count,
    required this.board,
  });

  DeckBoard get deckBoard => DeckBoard.fromName(board);

  DeckCardEntry copyWith({
    String? id,
    String? deckId,
    String? name,
    int? count,
    String? board,
  }) {
    return DeckCardEntry(
      id: id ?? this.id,
      deckId: deckId ?? this.deckId,
      name: name ?? this.name,
      count: count ?? this.count,
      board: board ?? this.board,
    );
  }
}

class DeckCardEntryAdapter extends TypeAdapter<DeckCardEntry> {
  @override
  final int typeId = 7;

  @override
  DeckCardEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DeckCardEntry(
      id: fields[0] as String,
      deckId: fields[1] as String,
      name: fields[2] as String,
      count: fields[3] as int,
      board: fields[4] as String? ?? DeckBoard.main.name,
    );
  }

  @override
  void write(BinaryWriter writer, DeckCardEntry obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.deckId)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.count)
      ..writeByte(4)
      ..write(obj.board);
  }
}
