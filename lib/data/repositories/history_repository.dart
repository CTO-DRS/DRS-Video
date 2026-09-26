import 'package:sqflite/sqflite.dart';
import '../../core/constants/app_constants.dart';
import '../../core/storage/database_service.dart';
import '../models/media_item.dart';

/// Watch progress + search history persistence.
class HistoryRepository {
  HistoryRepository(this._db);

  final DatabaseService _db;

  Future<void> upsertProgress(WatchProgress p) async {
    final database = await _db.database;
    await database.insert('watch_progress', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<WatchProgress?> progressFor(String itemId) async {
    final database = await _db.database;
    final rows = await database
        .query('watch_progress', where: 'item_id = ?', whereArgs: [itemId], limit: 1);
    return rows.isEmpty ? null : WatchProgress.fromMap(rows.first);
  }

  /// Items in progress (started, not completed), most recent first.
  Future<List<MediaItem>> continueWatching({int limit = 20}) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT m.*, w.position_ms AS pos
      FROM media_items m
      JOIN watch_progress w ON w.item_id = m.id
      WHERE w.completed = 0 AND w.position_ms >= ?
      ORDER BY w.updated_at DESC
      LIMIT ?
    ''', [AppConstants.minResumablePositionMs, limit]);
    return rows.map(MediaItem.fromMap).toList();
  }

  /// All items with stored progress (history tab).
  Future<List<MediaItem>> history({int limit = 500}) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT m.*
      FROM media_items m
      JOIN watch_progress w ON w.item_id = m.id
      ORDER BY w.updated_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(MediaItem.fromMap).toList();
  }

  /// Progress snapshot for every tracked item (used for progress bars).
  Future<Map<String, WatchProgress>> progressMap() async {
    final database = await _db.database;
    final rows = await database.query('watch_progress');
    return {
      for (final r in rows)
        (r['item_id'] as String): WatchProgress.fromMap(r),
    };
  }

  Future<void> clearHistory() async {
    final database = await _db.database;
    await database.delete('watch_progress');
  }

  Future<void> deleteProgress(String itemId) async {
    final database = await _db.database;
    await database.delete('watch_progress', where: 'item_id = ?', whereArgs: [itemId]);
  }

  Future<void> deleteProgressBulk(List<String> itemIds) async {
    if (itemIds.isEmpty) return;
    final database = await _db.database;
    await database.delete('watch_progress',
        where: 'item_id IN (${List.filled(itemIds.length, '?').join(',')})',
        whereArgs: itemIds);
  }

  // ---- search history ----

  Future<void> addSearch(String query) async {
    if (query.trim().isEmpty) return;
    final database = await _db.database;
    await database.insert(
      'search_history',
      {
        'query': query.trim(),
        'updated_at': DateTime.now().microsecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> recentSearches({int limit = 10}) async {
    final database = await _db.database;
    final rows = await database.query('search_history',
        orderBy: 'updated_at DESC', limit: limit);
    return rows.map((r) => r['query'] as String).toList();
  }

  Future<void> removeSearch(String query) async {
    final database = await _db.database;
    await database.delete('search_history', where: 'query = ?', whereArgs: [query]);
  }

  Future<void> clearSearches() async {
    final database = await _db.database;
    await database.delete('search_history');
  }
}
