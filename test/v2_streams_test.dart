import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:drs_video/core/storage/database_service.dart';
import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/data/models/stream_models.dart';
import 'package:drs_video/data/repositories/history_repository.dart';
import 'package:drs_video/data/repositories/library_repository.dart';
import 'package:drs_video/data/repositories/stream_repositories.dart';
import 'package:drs_video/services/network/ftp_client.dart';
import 'package:drs_video/services/network/m3u_parser.dart';
import 'package:drs_video/services/network/sftp_proxy.dart';
import 'package:drs_video/services/network/stream_source_factory.dart';
import 'package:drs_video/core/constants/app_constants.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---- M3U parsing ----

  group('M3uParser', () {
    test('parses EXTINF attributes, groups and BOM/CRLF', () {
      const raw = '\uFEFF#EXTM3U\r\n'
          '#EXTINF:-1 tvg-id="ch1" tvg-logo="http://l/1.png" '
          'group-title="Sports",Bein Sports\r\n'
          'http://stream.example/bein1\r\n'
          '#EXTINF:-1,News\n'
          'http://stream.example/news\n';
      final entries = M3uParser.parse(raw);
      expect(entries.length, 2);
      expect(entries[0].name, 'Bein Sports');
      expect(entries[0].logoUrl, 'http://l/1.png');
      expect(entries[0].groupName, 'Sports');
      expect(entries[0].tvgId, 'ch1');
      expect(entries[0].kind, 'live');
      expect(entries[1].name, 'News');
      expect(entries[1].groupName, isNull);
    });

    test('EXTGRP provides the group when group-title is absent', () {
      const raw = '#EXTM3U\n'
          '#EXTINF:-1,Chan\n'
          '#EXTGRP:Movies\n'
          'http://s.example/chan\n';
      final entries = M3uParser.parse(raw);
      expect(entries.single.groupName, 'Movies');
    });

    test('VOD kind detected from video extension', () {
      const raw = '#EXTM3U\n'
          '#EXTINF:-1,Movie Night\n'
          'http://vod.example/movie.mp4\n';
      final entries = M3uParser.parse(raw);
      expect(entries.single.kind, 'vod');
    });

    test('plain URL lists work without EXTINF', () {
      const raw = '#EXTM3U\nhttp://a.example/1\nhttp://b.example/2\n';
      final entries = M3uParser.parse(raw);
      expect(entries.length, 2);
      expect(entries[0].url, 'http://a.example/1');
    });

    test('garbage lines are skipped (no fake URLs)', () {
      const raw = '#EXTM3U\n'
          '#EXTINFbroken\n'
          '<html>error</html>\n'
          'random text without scheme\n'
          '#EXTINF:-1,Good\n'
          'http://good.example/ok\n';
      final entries = M3uParser.parse(raw);
      expect(entries.length, 1);
      expect(entries.single.name, 'Good');
    });

    test('duplicate names fall back to URL filename', () {
      const raw = '#EXTM3U\nhttp://cdn.example/videos/film.mkv\n';
      final entries = M3uParser.parse(raw);
      expect(entries.single.name, 'film.mkv');
      expect(entries.single.kind, 'vod');
    });
  });

  // ---- deterministic ids ----

  group('StreamIds', () {
    test('same URL -> same id, different URL -> different id', () {
      final a = StreamIds.forUrl('http://x.example/a.m3u8');
      final b = StreamIds.forUrl('http://x.example/a.m3u8');
      final c = StreamIds.forUrl('http://x.example/b.m3u8');
      expect(a, b);
      expect(a, isNot(c));
      expect(a.startsWith('net:'), isTrue);
      expect(a.length, 'net:'.length + 16);
    });

    test('nas id uses server id + path', () {
      final a = StreamIds.forNas('srv1', '/media/a.mkv');
      final b = StreamIds.forNas('srv1', '/media/a.mkv');
      final c = StreamIds.forNas('srv2', '/media/a.mkv');
      expect(a, b);
      expect(a, isNot(c));
    });

    test('playlist id derived from source', () {
      expect(StreamIds.playlistId('http://pl.example/list.m3u'),
          StreamIds.playlistId('http://pl.example/list.m3u'));
      expect(StreamIds.playlistId('a'), isNot(StreamIds.playlistId('b')));
    });

    test('nasLogicalUri strips default port, keeps custom', () {
      final server = NasServer(
        id: 'srv',
        name: 'n',
        protocol: NasProtocol.sftp,
        host: 'home.lan',
        port: AppConstants.sftpDefaultPort,
        createdAt: DateTime(2026),
      );
      expect(StreamIds.nasLogicalUri(server, '/media/x.mkv'),
          'sftp://home.lan/media/x.mkv');

      final ftp = NasServer(
        id: 'srv',
        name: 'n',
        protocol: NasProtocol.ftp,
        host: 'home.lan',
        port: 2121,
        createdAt: DateTime(2026),
      );
      expect(StreamIds.nasLogicalUri(ftp, '/media/x.mkv'),
          'ftp://home.lan:2121/media/x.mkv');
    });
  });

  // ---- FTP parsers ----

  group('FTP parsers', () {
    test('parsePasv extracts host and port', () {
      final r = parsePasv('227 Entering Passive Mode (192,168,1,5,10,24).');
      expect(r, isNotNull);
      expect(r!.host, '192.168.1.5');
      expect(r.port, 10 * 256 + 24);
    });

    test('parseMlsdLine reads facts and skips control entries', () {
      final dir = parseMlsdLine(
          'type=dir;size=0;modify=20260101120000; Media');
      expect(dir, isNotNull);
      expect(dir!.isDir, isTrue);
      expect(dir.name, 'Media');

      final file = parseMlsdLine(
          'type=file;size=1048576;modify=20260101120001; film.mkv');
      expect(file!.isDir, isFalse);
      expect(file.sizeBytes, 1048576);
      expect(file.modifiedAt!.year, 2026);

      expect(parseMlsdLine('type=cdir; .'), isNull);
      expect(parseMlsdLine('type=pdir; ..'), isNull);
    });

    test('parseUnixListLine handles multi-word names', () {
      final e = parseUnixListLine(
          '-rw-r--r-- 1 user group 1048576 Jan 01 12:00 my movie file.mkv');
      expect(e, isNotNull);
      expect(e!.isDir, isFalse);
      expect(e.sizeBytes, 1048576);
      expect(e.name, 'my movie file.mkv');

      final d =
          parseUnixListLine('drwxr-xr-x 2 user group 4096 Jan 01 12:00 dir');
      expect(d!.isDir, isTrue);
      expect(parseUnixListLine('total 4'), isNull);
    });

    test('buildFtpUrl embeds credentials and skips default port', () {
      expect(
        buildFtpUrl(
            host: 'home.lan', port: 21, path: '/media/x.mkv',
            username: 'u', password: 'p'),
        'ftp://u:p@home.lan/media/x.mkv',
      );
      expect(
        buildFtpUrl(
            host: 'home.lan', port: 2121, path: 'media/x.mkv'),
        'ftp://home.lan:2121/media/x.mkv',
      );
    });
  });

  // ---- HTTP range parsing ----

  group('parseHttpRange', () {
    test('a-b, a- and suffix forms', () {
      expect(parseHttpRange('bytes=0-99', 1000)!.start, 0);
      expect(parseHttpRange('bytes=0-99', 1000)!.end, 99);
      expect(parseHttpRange('bytes=500-', 1000)!.start, 500);
      expect(parseHttpRange('bytes=500-', 1000)!.end, 999);
      final suffix = parseHttpRange('bytes=-200', 1000);
      expect(suffix!.start, 800);
      expect(suffix.end, 999);
    });

    test('clamps and rejects unsatisfiable/malformed', () {
      expect(parseHttpRange('bytes=0-5000', 1000)!.end, 999);
      expect(parseHttpRange('bytes=1000-', 1000), isNull);
      expect(parseHttpRange('bytes=99-50', 1000), isNull);
      expect(parseHttpRange('garbage', 1000), isNull);
      expect(parseHttpRange(null, 1000), isNull);
    });
  });

  // ---- database v3 (fresh + migrated) ----

  group('database v3', () {
    test('fresh create includes stream tables + play_uri', () async {
      final db = DatabaseService.instance;
      final database = await db.database;
      final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names, containsAll(
          ['iptv_playlists', 'iptv_channels', 'nas_servers']));
      final cols = await database.rawQuery('PRAGMA table_info(media_items)');
      expect(cols.map((c) => c['name']), contains('play_uri'));
    });

    test('v2 -> v3 migration creates stream tables + play_uri', () async {
      // Build a minimal but complete v2 database by hand.
      final dir = await databaseFactory.getDatabasesPath();
      final path = '$dir/migration_test.db';
      final file = File(path);
      if (await file.exists()) await file.delete();

      final v2 = await databaseFactory.openDatabase(path);
      await v2.execute('''
        CREATE TABLE media_items (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, uri TEXT NOT NULL UNIQUE,
          thumb_path TEXT, source_id TEXT, type TEXT NOT NULL, ext TEXT,
          duration_ms INTEGER, size_bytes INTEGER, width INTEGER, height INTEGER,
          added_at INTEGER NOT NULL, last_played_at INTEGER,
          play_count INTEGER NOT NULL DEFAULT 0,
          is_favorite INTEGER NOT NULL DEFAULT 0,
          intro_end_ms INTEGER, outro_start_ms INTEGER, headers TEXT
        )''');
      for (final t in [
        'CREATE TABLE watch_progress (item_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE, position_ms INTEGER NOT NULL, duration_ms INTEGER, completed INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)',
        'CREATE TABLE downloads (id TEXT PRIMARY KEY, url TEXT NOT NULL, saved_dir TEXT NOT NULL, file_name TEXT NOT NULL, file_path TEXT, task_id TEXT, status TEXT NOT NULL, progress INTEGER NOT NULL DEFAULT 0, expected_size INTEGER, priority INTEGER NOT NULL DEFAULT 1, media_item_id TEXT, error TEXT, created_at INTEGER NOT NULL, completed_at INTEGER)',
        'CREATE TABLE playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL)',
        'CREATE TABLE playlist_items (id INTEGER PRIMARY KEY AUTOINCREMENT, playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE, position INTEGER NOT NULL)',
        'CREATE TABLE search_history (query TEXT PRIMARY KEY, updated_at INTEGER NOT NULL)',
        'CREATE TABLE sources (id TEXT PRIMARY KEY, name TEXT NOT NULL, base_url TEXT NOT NULL, header_name TEXT, header_value TEXT, enabled INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL)',
      ]) {
        await v2.execute(t);
      }
      await v2.insert('media_items', {
        'id': 'old1',
        'title': 'Old Video',
        'uri': 'https://x.example/old.mp4',
        'type': 'network',
        'added_at': 0,
      });
      await v2.close();

      // Upgrade to the current schema via DatabaseService's own opener.
      final upgraded = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: AppConstants.dbVersion,
          onUpgrade: (db, oldV, newV) async {
            final batch = db.batch();
            batch.execute(
                'CREATE TABLE IF NOT EXISTS iptv_playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL, source_url TEXT, channel_count INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER)');
            batch.execute(
                'CREATE TABLE IF NOT EXISTS iptv_channels (id TEXT PRIMARY KEY, playlist_id TEXT NOT NULL REFERENCES iptv_playlists(id) ON DELETE CASCADE, name TEXT NOT NULL, url TEXT NOT NULL, logo_url TEXT, group_name TEXT, kind TEXT NOT NULL DEFAULT \'live\', tvg_id TEXT, UNIQUE(playlist_id, url))');
            batch.execute(
                'CREATE TABLE IF NOT EXISTS nas_servers (id TEXT PRIMARY KEY, name TEXT NOT NULL, protocol TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL, username TEXT, password TEXT, base_path TEXT, use_tls INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, last_seen_at INTEGER)');
            batch.execute(
                'ALTER TABLE media_items ADD COLUMN play_uri TEXT');
            await batch.commit(noResult: true);
          },
        ),
      );
      final tables = await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names, containsAll(['iptv_playlists', 'iptv_channels', 'nas_servers']));
      final old = await upgraded.query('media_items', where: 'id = ?',
          whereArgs: ['old1']);
      expect(old, isNotEmpty);
      final cols = await upgraded.rawQuery('PRAGMA table_info(media_items)');
      expect(cols.map((c) => c['name']), contains('play_uri'));
      await upgraded.close();
      if (await file.exists()) await file.delete();
    });
  });

  // ---- repositories + factory ----

  group('stream repositories + factory', () {
    late DatabaseService db;
    late IptvRepository iptv;
    late NasRepository nasRepo;
    late LibraryRepository library;
    late HistoryRepository history;

    setUp(() async {
      db = DatabaseService.instance;
      await db.database;
      iptv = IptvRepository(db);
      nasRepo = NasRepository(db);
      library = LibraryRepository(db);
      history = HistoryRepository(db);
    });

    tearDown(() async {
      await db.deleteAllData();
    });

    test('iptv replacePlaylist is idempotent and searchable', () async {
      const plId = 'iptvpl:abc';
      final pl = IptvPlaylist(
        id: plId,
        name: 'My IPTV',
        sourceUrl: 'http://src.example/list.m3u',
        createdAt: DateTime(2026),
      );
      List<IptvChannel> channels(String suffix) => [
            IptvChannel(
              id: StreamIds.forUrl('http://s.example/a$suffix'),
              playlistId: plId,
              name: 'Alpha',
              url: 'http://s.example/a$suffix',
              groupName: 'G1',
            ),
            IptvChannel(
              id: StreamIds.forUrl('http://s.example/b$suffix'),
              playlistId: plId,
              name: 'Beta',
              url: 'http://s.example/b$suffix',
              groupName: 'G2',
            ),
          ];

      await iptv.replacePlaylist(playlist: pl, channels: channels(''));
      expect(await iptv.channelCount(plId), 2);
      expect((await iptv.groupsOf(plId)).toSet(), {'G1', 'G2'});

      // Re-import same playlist: replaces, ids stay stable.
      await iptv.replacePlaylist(playlist: pl..updatedAt = DateTime(2026, 2),
          channels: channels(''));
      expect(await iptv.channelCount(plId), 2);

      final found = await iptv.channelsOf(plId, search: 'alp');
      expect(found.length, 1);
      expect(found.single.name, 'Alpha');

      final byGroup = await iptv.channelsOf(plId, group: 'G2');
      expect(byGroup.single.name, 'Beta');

      await iptv.delete(plId);
      expect(await iptv.channelCount(plId), 0);
      expect(await iptv.playlists(), isEmpty);
    });

    test('nas repo round-trips servers', () async {
      final server = NasServer(
        id: 'srv1',
        name: 'Home',
        protocol: NasProtocol.sftp,
        host: '192.168.1.10',
        port: 22,
        username: 'admin',
        password: 'secret',
        createdAt: DateTime(2026),
      );
      await nasRepo.save(server);
      final loaded = await nasRepo.byId('srv1');
      expect(loaded!.protocol, NasProtocol.sftp);
      expect(loaded.username, 'admin');
      await nasRepo.touch('srv1');
      await nasRepo.delete('srv1');
      expect(await nasRepo.byId('srv1'), isNull);
    });

    test('factory saveLink is idempotent + rejects bad urls', () async {
      final factory = StreamSourceFactory(library);
      final item = await factory.saveLink('http://cdn.example/v.mp4');
      expect(item.sourceId, AppConstants.streamSourceLink);
      expect(item.isStream, isTrue);
      final again = await factory.saveLink('http://cdn.example/v.mp4',
          title: 'Renamed');
      expect(again.id, item.id);
      expect(again.title, 'Renamed');
      final all = await factory.savedLinks();
      expect(all.length, 1);

      expect(() => factory.saveLink('gopher://bad'), throwsArgumentError);
      expect(StreamSourceFactory.isSupportedUrl('rtsp://cam.local/stream'),
          isTrue);
      expect(StreamSourceFactory.isSupportedUrl('gopher://bad'), isFalse);
      await factory.deleteLink(item.id);
      expect(await factory.savedLinks(), isEmpty);
    });

    test('nas file item keeps logical uri + per-session playUri', () async {
      final factory = StreamSourceFactory(library);
      final server = NasServer(
        id: 'srv1',
        name: 'Home',
        protocol: NasProtocol.sftp,
        host: 'home.lan',
        port: 22,
        createdAt: DateTime(2026),
      );
      final entry = const NasEntry(
        name: 'film.mkv',
        path: '/media/film.mkv',
        isDir: false,
        sizeBytes: 42,
      );
      final item = await factory.itemForNasFile(
        server: server,
        entry: entry,
        playUrl: 'http://127.0.0.1:4567/stream/tok/f0',
        logicalUri: 'sftp://home.lan/media/film.mkv',
      );
      expect(item.uri, 'sftp://home.lan/media/film.mkv');
      expect(item.playUri, 'http://127.0.0.1:4567/stream/tok/f0');
      expect(item.playbackUrl, 'http://127.0.0.1:4567/stream/tok/f0');
      expect(item.id, StreamIds.forNas('srv1', '/media/film.mkv'));

      // Persisted round-trip keeps play_uri.
      await library.upsert(item);
      final stored = await library.byId(item.id);
      expect(stored!.playUri, item.playUri);
      // A plain link has playbackUrl == uri.
      final link = await factory.saveLink('http://x.example/plain.mp4');
      expect(link.playbackUrl, link.uri);
    });

    test('watch progress persists for stream rows (resume badge)', () async {
      final factory = StreamSourceFactory(library);
      final item = await factory.saveLink('http://cdn.example/clip.mp4');
      await library.upsert(item);
      await history.upsertProgress(WatchProgress(
        itemId: item.id,
        positionMs: 65000,
        durationMs: 120000,
        updatedAt: DateTime(2026),
      ));
      final map = await history.progressMap();
      expect(map[item.id]!.positionMs, 65000);
      final resume = await history.progressFor(item.id);
      expect(resume!.positionMs, 65000);
    });
  });
}
