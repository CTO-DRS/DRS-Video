import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import '../utils/logger.dart';

/// SQLite access layer. Schema is created/updated here; repositories own SQL.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, AppConstants.dbName);
    AppLogger.instance.info('db', 'open $path');
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
      onUpgrade: _upgrade,
    );
  }

  Future<void> _create(Database db, int version) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE media_items (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        uri TEXT NOT NULL UNIQUE,
        thumb_path TEXT,
        source_id TEXT,
        type TEXT NOT NULL,
        ext TEXT,
        duration_ms INTEGER,
        size_bytes INTEGER,
        width INTEGER,
        height INTEGER,
        added_at INTEGER NOT NULL,
        last_played_at INTEGER,
        play_count INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        intro_end_ms INTEGER,
        outro_start_ms INTEGER,
        headers TEXT,
        play_uri TEXT,
        is_hidden INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('CREATE INDEX idx_media_type ON media_items(type)');
    batch.execute('CREATE INDEX idx_media_last_played ON media_items(last_played_at)');
    batch.execute('''
      CREATE TABLE watch_progress (
        item_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER,
        completed INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE downloads (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        saved_dir TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT,
        task_id TEXT,
        status TEXT NOT NULL,
        progress INTEGER NOT NULL DEFAULT 0,
        expected_size INTEGER,
        priority INTEGER NOT NULL DEFAULT 1,
        media_item_id TEXT,
        error TEXT,
        headers TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      )''');
    batch.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE playlist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
        position INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE search_history (
        query TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE sources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        header_name TEXT,
        header_value TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )''');
    _createStreamTables(batch);
    _createBrowserTables(batch);
    await batch.commit(noResult: true);
  }

  /// Built-in browser tables (v4): history, bookmarks, user-added sites.
  void _createBrowserTables(Batch batch) {
    batch.execute('''
      CREATE TABLE browser_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL,
        title TEXT,
        visited_at INTEGER NOT NULL
      )''');
    batch.execute(
        'CREATE INDEX idx_browser_history_time ON browser_history(visited_at DESC)');
    batch.execute('''
      CREATE TABLE browser_bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE user_sites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      )''');
  }

  /// Streaming-platform tables (v3): IPTV playlists/channels + NAS servers.
  void _createStreamTables(Batch batch) {
    batch.execute('''
      CREATE TABLE iptv_playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        source_url TEXT,
        channel_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER
      )''');
    batch.execute('''
      CREATE TABLE iptv_channels (
        id TEXT PRIMARY KEY,
        playlist_id TEXT NOT NULL REFERENCES iptv_playlists(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        logo_url TEXT,
        group_name TEXT,
        kind TEXT NOT NULL DEFAULT 'live',
        tvg_id TEXT,
        UNIQUE(playlist_id, url)
      )''');
    batch.execute(
        'CREATE INDEX idx_iptv_channels_pl ON iptv_channels(playlist_id)');
    batch.execute(
        'CREATE INDEX idx_iptv_channels_group ON iptv_channels(playlist_id, group_name)');
    batch.execute('''
      CREATE TABLE nas_servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        protocol TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT,
        password TEXT,
        base_path TEXT,
        use_tls INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_seen_at INTEGER
      )''');
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    // v3: streaming platforms (IPTV + NAS) + per-session play_uri column.
    if (oldVersion < 3) {
      final batch = db.batch();
      _createStreamTables(batch);
      batch.execute('ALTER TABLE media_items ADD COLUMN play_uri TEXT');
      await batch.commit(noResult: true);
    }
    // v4: built-in browser (history / bookmarks / user sites).
    if (oldVersion < 4) {
      final batch = db.batch();
      _createBrowserTables(batch);
      await batch.commit(noResult: true);
    }
    // v5: private vault (v1.10.0) — hidden flag on media rows.
    if (oldVersion < 5) {
      await db.execute(
          'ALTER TABLE media_items ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0');
    }
    // v6 (v1.14.1): CDN headers persisted per download task so retry /
    // resume re-enqueue web-scrape addresses with their required headers.
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE downloads ADD COLUMN headers TEXT');
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> deleteAllData() async {
    final db = await database;
    final batch = db.batch();
    for (final table in [
      'watch_progress', 'playlist_items', 'playlists',
      'downloads', 'search_history', 'media_items', 'sources',
      'iptv_channels', 'iptv_playlists', 'nas_servers',
      'browser_history', 'browser_bookmarks', 'user_sites',
    ]) {
      batch.delete(table);
    }
    await batch.commit(noResult: true);
  }
}
