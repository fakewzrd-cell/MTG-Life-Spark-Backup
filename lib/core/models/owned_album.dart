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

  @HiveField(3)
  final bool favorited;

  @HiveField(4)
  final int lastOpenedMillis;

  static const Duration recentWindow = Duration(days: 30);

  const OwnedAlbum({
    required this.id,
    required this.name,
    required this.createdAtMillis,
    this.favorited = false,
    this.lastOpenedMillis = 0,
  });

  int get recencyMillis =>
      lastOpenedMillis > 0 ? lastOpenedMillis : createdAtMillis;

  bool isRecentAt(DateTime now) {
    final stamp = recencyMillis;
    if (stamp <= 0) return false;
    return now.millisecondsSinceEpoch - stamp <= recentWindow.inMilliseconds;
  }

  bool get isRecent => isRecentAt(DateTime.now());

  OwnedAlbum copyWith({
    String? id,
    String? name,
    int? createdAtMillis,
    bool? favorited,
    int? lastOpenedMillis,
  }) {
    return OwnedAlbum(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      favorited: favorited ?? this.favorited,
      lastOpenedMillis: lastOpenedMillis ?? this.lastOpenedMillis,
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
      favorited: fields[3] as bool? ?? false,
      lastOpenedMillis: fields[4] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, OwnedAlbum obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.createdAtMillis)
      ..writeByte(3)
      ..write(obj.favorited)
      ..writeByte(4)
      ..write(obj.lastOpenedMillis);
  }
}
