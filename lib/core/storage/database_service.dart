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
      onCreate: (db, version) => createSchema(db),
      onUpgrade: (db, o, n) => upgradeSchema(db, o, n),
    );
  }

  // ---------------------------------------------------------------------
  // Schema definition — one entry per table, in FK-dependency order.
  // Kept as data (not imperative batch code) so [_ensureSchema] can create
  // any MISSING table individually during an upgrade (P4-M4 safety net)
  // without duplicating SQL. [_create] consumes the same map, so a fresh
  // install and the safety net can never drift apart.
  // ---------------------------------------------------------------------
  static const List<(String, List<String>)> _tableSql = [
    ('media_items', [
      '''
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
      )''',
      'CREATE INDEX idx_media_type ON media_items(type)',
      'CREATE INDEX idx_media_last_played ON media_items(last_played_at)',
    ]),
    ('watch_progress', [
      '''
      CREATE TABLE watch_progress (
        item_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER,
        completed INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )''',
    ]),
    ('downloads', [
      '''
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
        origin_url TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER
      )''',
    ]),
    ('playlists', [
      '''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''',
    ]),
    ('playlist_items', [
      '''
      CREATE TABLE playlist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
        position INTEGER NOT NULL
      )''',
    ]),
    ('search_history', [
      '''
      CREATE TABLE search_history (
        query TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL
      )''',
    ]),
    ('sources', [
      '''
      CREATE TABLE sources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        header_name TEXT,
        header_value TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )''',
    ]),
    // Streaming platforms (v3): IPTV playlists/channels + NAS servers.
    ('iptv_playlists', [
      '''
      CREATE TABLE iptv_playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        source_url TEXT,
        channel_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER
      )''',
    ]),
    ('iptv_channels', [
      '''
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
      )''',
      'CREATE INDEX idx_iptv_channels_pl ON iptv_channels(playlist_id)',
      'CREATE INDEX idx_iptv_channels_group ON iptv_channels(playlist_id, group_name)',
    ]),
    ('nas_servers', [
      '''
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
      )''',
    ]),
    // Built-in browser (v4): history, bookmarks, user-added sites.
    ('browser_history', [
      '''
      CREATE TABLE browser_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL,
        title TEXT,
        visited_at INTEGER NOT NULL
      )''',
      'CREATE INDEX idx_browser_history_time ON browser_history(visited_at DESC)',
    ]),
    ('browser_bookmarks', [
      '''
      CREATE TABLE browser_bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''',
    ]),
    ('user_sites', [
      '''
      CREATE TABLE user_sites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      )''',
    ]),
  ];

  /// Columns added by ALTER TABLE migrations — a v1/v2 database that
  /// skipped those branches must still converge to the same shape.
  /// table -> (column -> full ADD COLUMN clause).
  static const Map<String, Map<String, String>> _migrationColumns = {
    'media_items': {
      'play_uri': 'ALTER TABLE media_items ADD COLUMN play_uri TEXT',
      'is_hidden':
          'ALTER TABLE media_items ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0',
    },
    'downloads': {
      'headers': 'ALTER TABLE downloads ADD COLUMN headers TEXT',
      'origin_url': 'ALTER TABLE downloads ADD COLUMN origin_url TEXT',
    },
  };

  /// Creates the full schema on a brand-new database.
  static Future<void> createSchema(Database db) async {
    final batch = db.batch();
    for (final (_, statements) in _tableSql) {
      for (final sql in statements) {
        batch.execute(sql);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Version upgrade path.
  ///
  /// P4-M4: sqflite runs this callback inside an exclusive transaction
  /// (any throw rolls the whole upgrade back), so the work below is atomic.
  /// The real gap was HISTORY: this repository's git history starts at DB
  /// v3, so the v1→v2 delta of pre-GitHub builds is unknowable — a database
  /// at v1/v2 could never receive those changes (e.g. missing
  /// search_history/sources → "no such table" crashes at first query).
  ///
  /// Instead of replaying history we cannot reconstruct, the upgrade
  /// CONVERGES the schema: [_ensureSchema] verifies every expected table
  /// (with its indexes) and every migration-added column, and creates or
  /// alters whatever is missing. For ANY starting version the end state is
  /// exactly the current full schema — identical to what the old
  /// oldVersion<3/<4/<5/<6/<7 branches produced, with their work fully
  /// subsumed (those branches only created tables and added columns).
  /// Nothing is ever dropped or overwritten, so user data survives.
  ///
  /// A FUTURE migration that must transform DATA (not just shape) cannot
  /// be expressed here — add an explicit oldVersion<N branch for it above
  /// the convergence call, conditional on actual state (never blind
  /// ALTER/CREATE, the safety net may already have applied the shape).
  static Future<void> upgradeSchema(
      Database db, int oldVersion, int newVersion) async {
    AppLogger.instance
        .info('db', 'upgrade $oldVersion → $newVersion (converge)');
    await _ensureSchema(db);
  }

  static Future<void> _ensureSchema(Database db) async {
    final rows = await db
        .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final existing = rows.map((r) => r['name'] as String).toSet();

    final batch = db.batch();
    var dirty = false;
    for (final (table, statements) in _tableSql) {
      if (!existing.contains(table)) {
        for (final sql in statements) {
          batch.execute(sql);
        }
        dirty = true;
      }
    }
    if (dirty) await batch.commit(noResult: true);

    for (final entry in _migrationColumns.entries) {
      final table = entry.key;
      if (!existing.contains(table) && !_tableSql.any((t) => t.$1 == table)) {
        continue; // table unknown to this schema — nothing to fix here
      }
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      final present = cols.map((r) => r['name'] as String).toSet();
      for (final col in entry.value.entries) {
        if (!present.contains(col.key)) {
          await db.execute(col.value);
        }
      }
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
