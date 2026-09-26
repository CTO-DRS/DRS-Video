import 'package:flutter/foundation.dart';
import '../core/utils/logger.dart';
import '../data/models/media_item.dart';
import '../data/models/playlist.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/playlist_repository.dart';

/// Playlist management: CRUD, membership, reorder, import/export.
class PlaylistsController extends ChangeNotifier {
  PlaylistsController({
    required PlaylistRepository playlists,
    required LibraryRepository library,
  })  : _playlists = playlists,
        _library = library;

  final PlaylistRepository _playlists;
  final LibraryRepository _library;

  /// Exposed for controllers that need library lookups alongside playlists.
  LibraryRepository get library => _library;

  List<PlaylistWithItems> playlists = [];
  bool loading = false;
  Object? error;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      playlists = await _playlists.listWithCounts();
    } catch (e, s) {
      AppLogger.instance.error('playlists', 'load failed', e, s);
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Playlist> create(String name) async {
    final pl = await _playlists.create(name.trim());
    await load();
    return pl;
  }

  Future<void> rename(String id, String name) async {
    await _playlists.rename(id, name.trim());
    await load();
  }

  Future<void> delete(String id) async {
    await _playlists.delete(id);
    await load();
  }

  Future<void> addVideos(String playlistId, List<String> itemIds) async {
    await _playlists.addItems(playlistId, itemIds);
    await load();
  }

  Future<void> removeVideo(String playlistId, String itemId) async {
    await _playlists.removeItem(playlistId, itemId);
    await load();
  }

  Future<void> reorder(String playlistId, List<MediaItem> ordered) async {
    await _playlists.reorder(playlistId, ordered.map((m) => m.id).toList());
    await load();
  }

  /// Resolves playable items for URIs that may reference imported
  /// (not yet registered) media.
  Future<List<MediaItem>> playableItems(PlaylistWithItems pl) async {
    return pl.items;
  }

  Future<PlaylistWithItems?> byId(String id) async {
    final items = await _playlists.items(id);
    final all = await _playlists.list();
    for (final pl in all) {
      if (pl.id == id) {
        return PlaylistWithItems(playlist: pl, items: items);
      }
    }
    return null;
  }
}
