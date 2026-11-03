import 'package:hive/hive.dart';

/// A named group of cards the player owns.
@HiveType(typeId: 9)
class OwnedAlbum {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final int createdAtMillis;

  const OwnedAlbum({
    required this.id,
    required this.name,
    required this.createdAtMillis,
  });

  OwnedAlbum copyWith({String? id, String? name, int? createdAtMillis}) {
    return OwnedAlbum(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
    );
  }
}

class OwnedAlbumAdapter extends TypeAdapter<OwnedAlbum> {
  @override
  final int typeId = 9;

  @override
  OwnedAlbum read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OwnedAlbum(
      id: fields[0] as String,
      name: fields[1] as String? ?? '',
      createdAtMillis: fields[2] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, OwnedAlbum obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.createdAtMillis);
  }
}
