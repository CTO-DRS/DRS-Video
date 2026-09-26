import '../../core/storage/database_service.dart';
import '../models/media_item.dart';
import '../models/playlist.dart';

class PlaylistRepository {
  PlaylistRepository(this._db);

  final DatabaseService _db;

  Future<Playlist> create(String name) async {
    final pl = Playlist(id: _newId(), name: name);
    final database = await _db.database;
    await database.insert('playlists', pl.toMap());
    return pl;
  }

  Future<void> rename(String id, String name) async {
    final database = await _db.database;
    await database.update('playlists', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final database = await _db.database;
    await database.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Playlist>> list() async {
    final database = await _db.database;
    final rows = await database.query('playlists', orderBy: 'created_at DESC');
    return rows.map(Playlist.fromMap).toList();
  }

  Future<List<PlaylistWithItems>> listWithCounts() async {
    final pls = await list();
    final result = <PlaylistWithItems>[];
    for (final pl in pls) {
      result.add(PlaylistWithItems(playlist: pl, items: await items(pl.id)));
    }
    return result;
  }

  Future<List<MediaItem>> items(String playlistId) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT m.* FROM playlist_items p
      JOIN media_items m ON m.id = p.item_id
      WHERE p.playlist_id = ?
      ORDER BY p.position ASC
    ''', [playlistId]);
    return rows.map(MediaItem.fromMap).toList();
  }

  Future<void> addItem(String playlistId, String itemId) async {
    final database = await _db.database;
    final existing = await database.query('playlist_items',
        where: 'playlist_id = ? AND item_id = ?', whereArgs: [playlistId, itemId], limit: 1);
    if (existing.isNotEmpty) return; // no duplicates
    final rows = await database.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM playlist_items WHERE playlist_id = ?',
        [playlistId]);
    final position = (rows.first['next'] as int?) ?? 0;
    await database.insert('playlist_items',
        {'playlist_id': playlistId, 'item_id': itemId, 'position': position});
  }

  Future<void> addItems(String playlistId, List<String> itemIds) async {
    for (final id in itemIds) {
      await addItem(playlistId, id);
    }
  }

  Future<void> removeItem(String playlistId, String itemId) async {
    final database = await _db.database;
    await database.delete('playlist_items',
        where: 'playlist_id = ? AND item_id = ?', whereArgs: [playlistId, itemId]);
    await _repack(playlistId);
  }

  /// Persists a new order of item ids for the playlist.
  Future<void> reorder(String playlistId, List<String> orderedItemIds) async {
    final database = await _db.database;
    final batch = database.batch();
    for (var i = 0; i < orderedItemIds.length; i++) {
      batch.update(
        'playlist_items',
        {'position': i},
        where: 'playlist_id = ? AND item_id = ?',
        whereArgs: [playlistId, orderedItemIds[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _repack(String playlistId) async {
    final database = await _db.database;
    final rows = await database.query('playlist_items',
        where: 'playlist_id = ?', whereArgs: [playlistId], orderBy: 'position ASC');
    final batch = database.batch();
    for (var i = 0; i < rows.length; i++) {
      batch.update('playlist_items', {'position': i},
          where: 'id = ?', whereArgs: [rows[i]['id']]);
    }
    await batch.commit(noResult: true);
  }

  String _newId() =>
      'pl_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
