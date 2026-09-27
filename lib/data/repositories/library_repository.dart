import 'package:sqflite/sqflite.dart';
import '../../core/storage/database_service.dart';
import '../models/media_item.dart';

enum SortBy { name, dateAdded, recentlyPlayed, duration, size, playCount, resolution }

/// Sort direction for the library list (v1.7.0). Every sort key honours it;
/// NULL values always stay last regardless of direction.
enum SortDirection { ascending, descending }

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
    this.direction = SortDirection.descending,
    this.limit,
    this.includeHidden = false,
  });

  final String? search;
  final MediaItemType? type;
  final String? sourceId;
  final bool favoritesOnly;
  final DurationFilter durationFilter;
  final SortBy sort;
  final SortDirection direction;
  final int? limit;

  /// Private vault (v1.10.0): hidden rows are excluded from EVERY library
  /// listing by default — search, home, recommendations, activity, smart
  /// playlists and cleanup all flow through [LibraryRepository.query], so
  /// one filter here covers the whole app. Only the backup collector and
  /// the vault screen opt in with [includeHidden] = true.
  final bool includeHidden;
}

class LibraryRepository {
  LibraryRepository(this._db);

  final DatabaseService _db;

  Future<MediaItem> upsert(MediaItem item) async {
    final database = await _db.database;
    // Private vault: a rescan that re-inserts an already hidden row (same
    // id or same uri) must NOT unhide it — carry the flag over.
    final existing = await database.query('media_items',
        where: 'id = ? OR uri = ?', whereArgs: [item.id, item.uri], limit: 1);
    if (existing.isNotEmpty) {
      item.isHidden =
          ((existing.first['is_hidden'] as int?) ?? 0) == 1 || item.isHidden;
    }
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

    // Vault filter first: hidden rows stay invisible everywhere unless the
    // caller (vault screen / backup) explicitly opts in.
    if (!q.includeHidden) where.add('is_hidden = 0');

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

    // Direction-aware ordering with a stable NULLS-LAST guarantee for every
    // key: the "(expr IS NULL) ASC" guard sorts NULLs to the end no matter
    // which way the main expression runs.
    final dir = q.direction == SortDirection.ascending ? 'ASC' : 'DESC';
    final orderBy = switch (q.sort) {
      SortBy.name => 'title COLLATE NOCASE $dir',
      SortBy.dateAdded => 'added_at $dir',
      SortBy.recentlyPlayed => '(last_played_at IS NULL) ASC, last_played_at $dir',
      SortBy.duration => '(duration_ms IS NULL) ASC, duration_ms $dir',
      SortBy.size => '(size_bytes IS NULL) ASC, size_bytes $dir',
      SortBy.playCount => 'play_count $dir',
      SortBy.resolution =>
        '(CASE WHEN width IS NULL OR height IS NULL THEN NULL ELSE width * height END) IS NULL ASC, '
            '(CASE WHEN width IS NULL OR height IS NULL THEN NULL ELSE width * height END) $dir',
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
        'SELECT COUNT(*) c FROM media_items WHERE type = ? AND is_hidden = 0',
        [type.name]);
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countFavorites() async {
    final database = await _db.database;
    final rows = await database.rawQuery(
        'SELECT COUNT(*) c FROM media_items WHERE is_favorite = 1 AND is_hidden = 0');
    return (rows.first['c'] as int?) ?? 0;
  }

  // ---- private vault (v1.10.0) -------------------------------------------

  /// Moves a media row into (or out of) the private vault. Hidden rows are
  /// excluded from every listing (see [LibraryQuery.includeHidden]).
  Future<void> setHidden(String id, bool hidden) async {
    final database = await _db.database;
    await database.update('media_items', {'is_hidden': hidden ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// All vaulted rows, newest first — the vault screen grid.
  Future<List<MediaItem>> vaultItems() async {
    final database = await _db.database;
    final rows = await database.query('media_items',
        where: 'is_hidden = 1', orderBy: 'added_at DESC');
    return rows.map(MediaItem.fromMap).toList();
  }

  /// Number of rows currently in the vault (settings screen subtitle).
  Future<int> hiddenCount() async {
    final database = await _db.database;
    final rows = await database.rawQuery(
        'SELECT COUNT(*) c FROM media_items WHERE is_hidden = 1');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> _update(String id, Map<String, Object?> values) async {
    final database = await _db.database;
    await database.update('media_items', values, where: 'id = ?', whereArgs: [id]);
  }
}
