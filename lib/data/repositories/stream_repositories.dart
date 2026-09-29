import 'package:sqflite/sqflite.dart';

import '../../core/storage/database_service.dart';
import '../../core/storage/secure_credentials.dart';
import '../models/stream_models.dart';

/// Persistence for IPTV playlists and channels.
class IptvRepository {
  IptvRepository(this._db);

  final DatabaseService _db;

  /// Atomically replaces one playlist and its channels (re-import is
  /// idempotent: same playlist id → clean replace, channel ids stay stable
  /// because they hash the URL).
  Future<void> replacePlaylist({
    required IptvPlaylist playlist,
    required List<IptvChannel> channels,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete('iptv_channels',
          where: 'playlist_id = ?', whereArgs: [playlist.id]);
      batch.insert('iptv_playlists', playlist.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      for (final ch in channels) {
        batch.insert('iptv_channels', ch.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<IptvPlaylist>> playlists() async {
    final db = await _db.database;
    final rows = await db.query('iptv_playlists', orderBy: 'created_at DESC');
    return rows.map(IptvPlaylist.fromMap).toList();
  }

  Future<IptvPlaylist?> playlistById(String id) async {
    final db = await _db.database;
    final rows = await db.query('iptv_playlists',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : IptvPlaylist.fromMap(rows.first);
  }

  /// Channels of a playlist with optional group filter and SQL search.
  Future<List<IptvChannel>> channelsOf(
    String playlistId, {
    String? group,
    String? search,
    int limit = 300,
    int offset = 0,
  }) async {
    final db = await _db.database;
    final where = <String>['playlist_id = ?'];
    final args = <Object?>[playlistId];
    if (group != null && group.isNotEmpty) {
      where.add('group_name = ?');
      args.add(group);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('name LIKE ?');
      args.add('%${search.trim()}%');
    }
    final rows = await db.query(
      'iptv_channels',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
      offset: offset,
    );
    return rows.map(IptvChannel.fromMap).toList();
  }

  /// Distinct group names inside one playlist.
  Future<List<String>> groupsOf(String playlistId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT group_name FROM iptv_channels '
      "WHERE playlist_id = ? AND group_name IS NOT NULL AND group_name != '' "
      'ORDER BY group_name COLLATE NOCASE',
      [playlistId],
    );
    return rows.map((r) => r['group_name'] as String).toList();
  }

  Future<int> channelCount(String playlistId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM iptv_channels WHERE playlist_id = ?',
      [playlistId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> touch(String playlistId) async {
    final db = await _db.database;
    await db.update(
      'iptv_playlists',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> delete(String playlistId) async {
    final db = await _db.database;
    await db.delete('iptv_channels',
        where: 'playlist_id = ?', whereArgs: [playlistId]);
    await db
        .delete('iptv_playlists', where: 'id = ?', whereArgs: [playlistId]);
  }
}

/// Persistence for NAS server connections (credentials stay on-device).
///
/// P2 security fix (C1): the `password` column is NEVER written with
/// plaintext anymore — secrets live in the Keystore-backed
/// [SecureCredentialsStore]; the row keeps connection metadata only.
/// Reads hydrate the password from the vault in-memory, and legacy
/// plaintext rows are migrated lazily on the first [servers] call.
class NasRepository {
  /// [credentials] is optional so plain unit tests can construct the
  /// repository without a vault; production wiring (bootstrap) always
  /// supplies it.
  NasRepository(this._db, {SecureCredentialsStore? credentials})
      : _credentials = credentials;

  final DatabaseService _db;
  final SecureCredentialsStore? _credentials;

  Future<void> save(NasServer server) async {
    final db = await _db.database;
    var row = server;
    final creds = _credentials;
    final pw = server.password;
    if (creds != null && pw != null && pw.isNotEmpty) {
      // Secret goes to the Keystore vault; the DB row gets a blank.
      await creds.setNasPassword(server.id, pw);
      row = _withBlankPassword(server);
    }
    await db.insert('nas_servers', row.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<NasServer>> servers() async {
    final db = await _db.database;
    final creds = _credentials;
    if (creds != null) {
      // Idempotent one-way migration of legacy plaintext rows (v1.14.7).
      await creds.migrateNasPasswords(db);
    }
    final rows = await db.query('nas_servers', orderBy: 'created_at DESC');
    final servers = rows.map(NasServer.fromMap).toList();
    if (creds == null) return servers;
    for (final s in servers) {
      final pw = s.password;
      if (pw != null && pw.isNotEmpty) continue; // not yet migrated
      try {
        s.password = await creds.nasPassword(s.id);
      } catch (_) {
        // Vault unavailable (corrupt Keystore etc.): degrade to an auth
        // failure on the next connection instead of killing the list.
      }
    }
    return servers;
  }

  Future<NasServer?> byId(String id) async {
    final db = await _db.database;
    final rows = await db
        .query('nas_servers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : NasServer.fromMap(rows.first);
  }

  Future<void> touch(String id) async {
    final db = await _db.database;
    await db.update(
      'nas_servers',
      {'last_seen_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('nas_servers', where: 'id = ?', whereArgs: [id]);
    await _credentials?.deleteNasPassword(id);
  }

  /// Returns a copy of [server] with an empty password for DB storage.
  NasServer _withBlankPassword(NasServer server) => NasServer(
        id: server.id,
        name: server.name,
        protocol: server.protocol,
        host: server.host,
        port: server.port,
        username: server.username,
        password: '',
        basePath: server.basePath,
        useTls: server.useTls,
        createdAt: server.createdAt,
        lastSeenAt: server.lastSeenAt,
      );
}
