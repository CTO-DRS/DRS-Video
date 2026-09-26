import 'package:sqflite/sqflite.dart';
import '../../core/constants/app_constants.dart';
import '../../core/storage/database_service.dart';
import '../models/media_item.dart';

/// One day of aggregated watch activity (v1.1.0 statistics).
class WatchDayStat {
  const WatchDayStat({
    required this.day,
    required this.watchedMs,
    required this.sessions,
  });

  final String day; // yyyy-MM-dd (local)
  final int watchedMs;
  final int sessions;

  Map<String, Object?> toMap() =>
      {'day': day, 'watched_ms': watchedMs, 'sessions': sessions};

  static WatchDayStat fromMap(Map<String, Object?> m) => WatchDayStat(
        day: m['day'] as String,
        watchedMs: (m['watched_ms'] as int?) ?? 0,
        sessions: (m['sessions'] as int?) ?? 0,
      );
}

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

  // ---- watch statistics (v1.1.0) ----

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Accumulates [ms] of watched time onto today's bucket. No-op when
  /// [ms] <= 0.
  Future<void> recordWatchedMs(int ms) async {
    if (ms <= 0) return;
    final database = await _db.database;
    await database.execute('''
      INSERT INTO watch_daily (day, watched_ms, sessions)
      VALUES (?, ?, 0)
      ON CONFLICT(day) DO UPDATE SET watched_ms = watched_ms + excluded.watched_ms
    ''', [_todayKey(), ms]);
  }

  /// Counts one playback session for today.
  Future<void> recordSession() async {
    final database = await _db.database;
    await database.execute('''
      INSERT INTO watch_daily (day, watched_ms, sessions)
      VALUES (?, 0, 0)
      ON CONFLICT(day) DO UPDATE SET sessions = sessions + 1
    ''', [_todayKey()]);
  }

  /// Merge used by backup restore: takes the LARGER value per field so a
  /// restore never loses newer local statistics.
  Future<void> mergeWatchDay({
    required String day,
    required int watchedMs,
    required int sessions,
  }) async {
    final database = await _db.database;
    await database.execute('''
      INSERT INTO watch_daily (day, watched_ms, sessions)
      VALUES (?, ?, ?)
      ON CONFLICT(day) DO UPDATE SET
        watched_ms = MAX(watch_daily.watched_ms, excluded.watched_ms),
        sessions = MAX(watch_daily.sessions, excluded.sessions)
    ''', [day, watchedMs, sessions]);
  }

  /// Daily buckets ordered oldest -> newest, optionally limited to the
  /// last [days] days.
  Future<List<WatchDayStat>> watchDaily({int? days}) async {
    final database = await _db.database;
    final rows = await database.query('watch_daily', orderBy: 'day ASC');
    final stats = rows.map(WatchDayStat.fromMap).toList();
    if (days == null || stats.length <= days) return stats;
    return stats.sublist(stats.length - days);
  }

  Future<int> totalWatchedMs() async {
    final database = await _db.database;
    final rows = await database
        .rawQuery('SELECT COALESCE(SUM(watched_ms), 0) AS t FROM watch_daily');
    return (rows.first['t'] as int?) ?? 0;
  }

  /// Longest run of consecutive days (with any activity) ending today or
  /// yesterday.
  Future<int> currentStreakDays() async {
    final all = await watchDaily();
    final active = all.where((d) => d.watchedMs > 0 || d.sessions > 0)
        .map((d) => d.day)
        .toSet();
    if (active.isEmpty) return 0;
    var streak = 0;
    var cursor = DateTime.now();
    // Allow the streak to start today or yesterday.
    if (!active.contains(_keyOf(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (active.contains(_keyOf(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static String _keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> clearWatchStats() async {
    final database = await _db.database;
    await database.delete('watch_daily');
  }

  Future<List<WatchProgress>> allProgress() async {
    final database = await _db.database;
    final rows = await database.query('watch_progress');
    return rows.map(WatchProgress.fromMap).toList();
  }

  Future<void> upsertProgressAll(List<WatchProgress> list) async {
    if (list.isEmpty) return;
    final database = await _db.database;
    final batch = database.batch();
    for (final p in list) {
      batch.insert('watch_progress', p.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<WatchDayStat>> allWatchDaily() => watchDaily();


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
