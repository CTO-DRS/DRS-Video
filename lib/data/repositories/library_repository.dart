import 'package:sqflite/sqflite.dart';
import '../../core/storage/database_service.dart';
import '../models/media_item.dart';

enum SortBy { name, dateAdded, recentlyPlayed, duration, size }

enum DurationFilter { any, short, medium, long, veryLong }

/// Query object for the library screen (all filters are AND-combined).
class LibraryQuery {
  const LibraryQuery({
    this.search,
    this.type,
    this.sourceId,
    this.favoritesOnly = false,
    this.durationFilter = DurationFilter.any,
    this.sort = SortBy.dateAdded,
    this.limit,
  });

  final String? search;
  final MediaItemType? type;
  final String? sourceId;
  final bool favoritesOnly;
  final DurationFilter durationFilter;
  final SortBy sort;
  final int? limit;
}

class LibraryRepository {
  LibraryRepository(this._db);

  final DatabaseService _db;

  Future<MediaItem> upsert(MediaItem item) async {
    final database = await _db.database;
    await database.insert('media_items', item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return item;
  }

  Future<MediaItem?> byId(String id) async {
    final database = await _db.database;
    final rows = await database.query('media_items', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : MediaItem.fromMap(rows.first);
  }

  Future<MediaItem?> byUri(String uri) async {
    final database = await _db.database;
    final rows = await database.query('media_items', where: 'uri = ?', whereArgs: [uri], limit: 1);
    return rows.isEmpty ? null : MediaItem.fromMap(rows.first);
  }

  Future<List<MediaItem>> query(LibraryQuery q) async {
    final database = await _db.database;
    final where = <String>[];
    final args = <Object?>[];

    if (q.search != null && q.search!.trim().isNotEmpty) {
      where.add('title LIKE ?');
      args.add('%${q.search!.trim()}%');
    }
    if (q.type != null) {
      where.add('type = ?');
      args.add(q.type!.name);
    }
    if (q.sourceId != null) {
      where.add('source_id = ?');
      args.add(q.sourceId);
    }
    if (q.favoritesOnly) where.add('is_favorite = 1');
    switch (q.durationFilter) {
      case DurationFilter.short:
        where.add('duration_ms IS NOT NULL AND duration_ms < 300000');
      case DurationFilter.medium:
        where.add('duration_ms BETWEEN 300000 AND 1200000');
      case DurationFilter.long:
        where.add('duration_ms BETWEEN 1200000 AND 3600000');
      case DurationFilter.veryLong:
        where.add('duration_ms > 3600000');
      case DurationFilter.any:
    }

    final orderBy = switch (q.sort) {
      SortBy.name => 'title COLLATE NOCASE ASC',
      SortBy.dateAdded => 'added_at DESC',
      SortBy.recentlyPlayed => 'last_played_at IS NULL, last_played_at DESC',
      SortBy.duration => 'duration_ms IS NULL, duration_ms DESC',
      SortBy.size => 'size_bytes IS NULL, size_bytes DESC',
    };

    final rows = await database.query(
      'media_items',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: orderBy,
      limit: q.limit,
    );
    return rows.map(MediaItem.fromMap).toList();
  }

  Future<List<String>> allSourceIds() async {
    final database = await _db.database;
    final rows = await database.rawQuery(
        'SELECT DISTINCT source_id FROM media_items WHERE source_id IS NOT NULL');
    return rows.map((r) => r['source_id'] as String).toList();
  }

  Future<void> setFavorite(String id, bool fav) => _update(id, {'is_favorite': fav ? 1 : 0});

  Future<void> rename(String id, String title) => _update(id, {'title': title});

  Future<void> updateThumb(String id, String thumbPath) =>
      _update(id, {'thumb_path': thumbPath});

  Future<void> updateMeta(String id, {int? durationMs, int? sizeBytes, int? width, int? height}) {
    final map = <String, Object?>{
      if (durationMs != null) 'duration_ms': durationMs,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    };
    return map.isEmpty ? Future.value() : _update(id, map);
  }

  Future<void> markPlayed(String id) async {
    final database = await _db.database;
    await database.rawUpdate('''
      UPDATE media_items
      SET play_count = play_count + 1,
          last_played_at = ?
      WHERE id = ?
    ''', [DateTime.now().millisecondsSinceEpoch, id]);
  }

  Future<void> delete(String id) => deleteMany([id]);

  Future<void> deleteMany(List<String> ids) async {
    if (ids.isEmpty) return;
    final database = await _db.database;
    await database.delete('media_items',
        where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  Future<int> countByType(MediaItemType type) async {
    final database = await _db.database;
    final rows = await database.rawQuery(
        'SELECT COUNT(*) c FROM media_items WHERE type = ?', [type.name]);
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countFavorites() async {
    final database = await _db.database;
    final rows = await database.rawQuery('SELECT COUNT(*) c FROM media_items WHERE is_favorite = 1');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Every known media item (backup/restore).
  Future<List<MediaItem>> listAll() async {
    final database = await _db.database;
    final rows = await database.query('media_items');
    return rows.map(MediaItem.fromMap).toList();
  }

  /// Bulk upsert (restore).
  Future<void> upsertAll(List<MediaItem> items) async {
    if (items.isEmpty) return;
    final database = await _db.database;
    final batch = database.batch();
    for (final item in items) {
      batch.insert('media_items', item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Most replayed items (watch statistics).
  Future<List<MediaItem>> topPlayed({int limit = 5}) async {
    final database = await _db.database;
    final rows = await database.query('media_items',
        where: 'play_count > 0',
        orderBy: 'play_count DESC, last_played_at DESC',
        limit: limit);
    return rows.map(MediaItem.fromMap).toList();
  }

  Future<void> _update(String id, Map<String, Object?> values) async {
    final database = await _db.database;
    await database.update('media_items', values, where: 'id = ?', whereArgs: [id]);
  }
}
