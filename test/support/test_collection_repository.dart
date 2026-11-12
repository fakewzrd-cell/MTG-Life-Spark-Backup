import 'package:mgt_life_spark/core/models/collection_entry.dart';
import 'package:mgt_life_spark/core/models/owned_album.dart';
import 'package:mgt_life_spark/core/persistence/collection_repository.dart';

/// In-memory collection repo for widget tests (no Hive).
class TestCollectionRepository extends CollectionRepository {
  TestCollectionRepository({List<OwnedAlbum>? albums, this.counts = const {}})
    : _albums = List<OwnedAlbum>.from(albums ?? const []);

  final List<OwnedAlbum> _albums;
  final Map<String, int> counts;

  @override
  Future<void> init() async {}

  @override
  Future<void> adoptLooseCards(String albumName) async {}

  @override
  List<OwnedAlbum> getAlbums() => List<OwnedAlbum>.from(_albums);

  @override
  OwnedAlbum? getAlbum(String id) {
    for (final album in _albums) {
      if (album.id == id) return album;
    }
    return null;
  }

  @override
  List<CollectionEntry> forAlbum(String albumId) => const [];

  @override
  int cardCount(String albumId) => counts[albumId] ?? 0;

  @override
  Future<void> setAlbumFavorited(String id, bool favorited) async {
    final index = _albums.indexWhere((album) => album.id == id);
    if (index < 0) return;
    _albums[index] = _albums[index].copyWith(favorited: favorited);
  }

  @override
  Future<void> touchAlbumOpened(String id) async {
    final index = _albums.indexWhere((album) => album.id == id);
    if (index < 0) return;
    _albums[index] = _albums[index].copyWith(
      lastOpenedMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> renameAlbum(String id, String name) async {
    final index = _albums.indexWhere((album) => album.id == id);
    if (index < 0) return;
    _albums[index] = _albums[index].copyWith(name: name.trim());
  }

  @override
  Future<void> deleteAlbum(String id) async {
    _albums.removeWhere((album) => album.id == id);
  }
}
