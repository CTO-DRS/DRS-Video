import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import 'package:sqflite/sqflite.dart';

/// Row of the built-in browser history.
class BrowserHistoryEntry {
  BrowserHistoryEntry({
    required this.id,
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  final int id;
  final String url;
  final String title;
  final int visitedAt;
}

/// A saved bookmark of the built-in browser.
class BrowserBookmark {
  BrowserBookmark({
    required this.id,
    required this.url,
    required this.title,
    required this.createdAt,
  });

  final int id;
  final String url;
  final String title;
  final int createdAt;
}

/// A user-added platform site (extends the bundled catalog).
class UserSite {
  UserSite({
    required this.id,
    required this.name,
    required this.url,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String url;
  final int createdAt;
}

/// SQLite storage for the built-in platform browser (v1.4.0):
/// visit history (capped), bookmarks and user-added sites.
/// All methods are failure-tolerant: a browser storage problem must
/// never crash the app (the in-memory session keeps working).
class BrowserRepository {
  BrowserRepository(this._db);

  final Database _db;

  // ---- history ----

  Future<void> addHistory(String url, String title) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Collapse consecutive duplicates of the same URL.
      await _db.delete('browser_history',
          where: 'url = ?', whereArgs: [url]);
      await _db.insert('browser_history', {
        'url': url,
        'title': title.isEmpty ? url : title,
        'visited_at': now,
      });
      // Enforce the cap (delete oldest overflow rows).
      await _db.execute(
        "DELETE FROM browser_history WHERE id NOT IN "
        "(SELECT id FROM browser_history ORDER BY visited_at DESC LIMIT ?)",
        [AppConstants.browserHistoryCap],
      );
    } catch (e, s) {
      AppLogger.instance.error('browser-repo', 'addHistory failed', e, s);
    }
  }

  Future<List<BrowserHistoryEntry>> history({int limit = 100}) async {
    try {
      final rows = await _db.query('browser_history',
          orderBy: 'visited_at DESC', limit: limit);
      return rows
          .map((r) => BrowserHistoryEntry(
                id: r['id'] as int,
                url: r['url'] as String,
                title: (r['title'] as String?) ?? '',
                visitedAt: r['visited_at'] as int,
              ))
          .toList();
    } catch (e, s) {
      AppLogger.instance.error('browser-repo', 'history failed', e, s);
      return const [];
    }
  }

  /// Deletes all history rows whose URL contains [query]
  /// (used by the protection screen "clear" action).
  Future<int> clearHistory() async {
    try {
      return await _db.delete('browser_history');
    } catch (e, s) {
      AppLogger.instance.error('browser-repo', 'clearHistory failed', e, s);
      return 0;
    }
  }

  // ---- bookmarks ----

  Future<void> addBookmark(String url, String title) async {
    try {
      await _db.insert(
        'browser_bookmarks',
        {
          'url': url,
          'title': title.isEmpty ? url : title,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, s) {
      AppLogger.instance.error('browser-repo', 'addBookmark failed', e, s);
    }
  }

  Future<void> removeBookmark(String url) async {
    try {
      await _db.delete('browser_bookmarks', where: 'url = ?', whereArgs: [url]);
    } catch (e, s) {
      AppLogger.instance.error('browser-repo', 'removeBookmark failed', e, s);
    }
  }

  Future<bool> isBookmarked(String url) async {
    try {
      final rows = await _db.query('browser_bookmarks',
          where: 'url = ?', whereArgs: [url], limit: 1);
      return rows.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<List<BrowserBookmark>> bookmarks() async {
    try {
      final rows = await _db
          .query('browser_bookmarks', orderBy: 'created_at DESC');
      return rows
          .map((r) => BrowserBookmark(
                id: r['id'] as int,
                url: r['url'] as String,
                title: (r['title'] as String?) ?? '',
                createdAt: r['created_at'] as int,
              ))
          .toList();
    } catch (e, s) {
      AppLogger.instance.error('browser-repo', 'bookmarks failed', e, s);
      return const [];
    }
  }

  // ---- user sites ----

  Future<UserSite?> addUserSite(String name, String url) async {
    try {
      final id = await _db.insert('user_sites', {
        'name': name,
        'url': url,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      return UserSite(
        id: id,
        name: name,
        url: url,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e, s) {
      AppLogger.instance.error('browser-repo', 'addUserSite failed', e, s);
      return null;
    }
  }

  Future<void> removeUserSite(int id) async {
    try {
      await _db.delete('user_sites', where: 'id = ?', whereArgs: [id]);
    } catch (e, s) {
      AppLogger.instance.error('browser-repo', 'removeUserSite failed', e, s);
    }
  }

  Future<List<UserSite>> userSites() async {
    try {
      final rows = await _db.query('user_sites', orderBy: 'created_at DESC');
      return rows
          .map((r) => UserSite(
                id: r['id'] as int,
                name: (r['name'] as String?) ?? '',
                url: (r['url'] as String?) ?? '',
                createdAt: r['created_at'] as int,
              ))
          .toList();
    } catch (e, s) {
      AppLogger.instance.error('browser-repo', 'userSites failed', e, s);
      return const [];
    }
  }
}
