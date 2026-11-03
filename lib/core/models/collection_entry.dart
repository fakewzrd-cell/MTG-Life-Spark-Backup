import 'package:hive/hive.dart';

/// A card the player owns. Owning it is separate from putting it in a deck.
@HiveType(typeId: 8)
class CollectionEntry {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final int count;

  /// Album this card belongs to. Empty on rows saved before albums existed.
  @HiveField(3)
  final String? albumId;

  const CollectionEntry({
    required this.id,
    required this.name,
    required this.count,
    this.albumId,
  });

  CollectionEntry copyWith({
    String? id,
    String? name,
    int? count,
    String? albumId,
  }) {
    return CollectionEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      count: count ?? this.count,
      albumId: albumId ?? this.albumId,
    );
  }
}

class CollectionEntryAdapter extends TypeAdapter<CollectionEntry> {
  @override
  final int typeId = 8;

  @override
  CollectionEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    final album = fields[3] as String?;
    return CollectionEntry(
      id: fields[0] as String,
      name: fields[1] as String,
      count: fields[2] as int? ?? 1,
      albumId: album == null || album.isEmpty ? null : album,
    );
  }

  @override
  void write(BinaryWriter writer, CollectionEntry obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.count)
      ..writeByte(3)
      ..write(obj.albumId ?? '');
  }
}
