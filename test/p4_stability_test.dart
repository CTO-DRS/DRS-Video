import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:drs_video/core/errors/app_exception.dart';
import 'package:drs_video/core/storage/database_service.dart';
import 'package:drs_video/core/utils/serialized_runner.dart';
import 'package:drs_video/services/player/player_service.dart';

void main() {
  group('P4-M1: SerializedRunner (pump gate primitive)', () {
    test('passes run strictly in submission order, never overlapping',
        () async {
      final runner = SerializedRunner();
      final log = <int>[];
      var inside = false;
      var maxConcurrent = 0;

      Future<void> pass(int i) async {
        expect(inside, isFalse,
            reason: 'two passes must never overlap inside the gate');
        inside = true;
        maxConcurrent++;
        // Yield a few times so a broken gate would interleave passes.
        for (var k = 0; k < 3; k++) {
          await Future<void>.delayed(Duration.zero);
        }
        log.add(i);
        maxConcurrent--;
        inside = false;
      }

      // Submit 12 passes WITHOUT awaiting each — the old race pattern.
      final futures = [
        for (var i = 0; i < 12; i++) runner.run(() => pass(i)),
      ];
      await runner.idle;
      await Future.wait(futures);

      expect(log, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
      expect(maxConcurrent, lessThanOrEqualTo(1));
    });

    test('a later pass waits for a long-running earlier pass', () async {
      final runner = SerializedRunner();
      final aStarted = Completer<void>();
      final aRelease = Completer<void>();
      var bStarted = false;

      final fa = runner.run(() async {
        aStarted.complete();
        await aRelease.future;
      });
      final fb = runner.run(() async {
        bStarted = true;
      });

      await aStarted.future;
      // Give b a real chance to (wrongly) start.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bStarted, isFalse,
          reason: 'pass b must not start while pass a is still running');
      aRelease.complete();
      await Future.wait([fa, fb]);
      expect(bStarted, isTrue);
    });

    test('a failing pass does not break the chain or poison later passes',
        () async {
      final runner = SerializedRunner();
      final log = <String>[];

      final f1 = runner.run(() async {
        log.add('a');
        throw StateError('boom');
      });
      final f2 = runner.run(() async {
        log.add('b');
      });
      final f3 = runner.run(() async {
        log.add('c');
      });

      await expectLater(f1, throwsA(isA<StateError>()));
      await Future.wait([f2, f3]);
      expect(log, ['a', 'b', 'c'], reason: 'b and c must still run, in order');
    });

    test('awaiting a pass still guarantees that pass ran (semantics kept)',
        () async {
      final runner = SerializedRunner();
      var done = false;
      await runner.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        done = true;
      });
      expect(done, isTrue);
    });
  });

  group('P4-M4: database schema convergence', () {
    late Database db;
    late String path;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    /// Builds a pre-GitHub-style database: core tables only, WITHOUT the
    /// v3/v4 tables and WITHOUT the ALTER-added columns. Two shapes are
    /// exercised: with and without search_history/sources (v1 vs v2).
    Future<void> seedLegacyDb({required bool withSearchAndSources}) async {
      path = '${Directory.systemTemp.path}/'
          'p4_legacy_${withSearchAndSources ? 1 : 0}_${DateTime.now().microsecondsSinceEpoch}.db';
      db = await openDatabase(path, version: 1, onCreate: (d, v) async {
        await d.execute('''
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
            headers TEXT
          )''');
        await d.execute('''
          CREATE TABLE watch_progress (
            item_id TEXT PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
            position_ms INTEGER NOT NULL,
            duration_ms INTEGER,
            completed INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
          )''');
        await d.execute('''
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
            created_at INTEGER NOT NULL,
            completed_at INTEGER
          )''');
        await d.execute('''
          CREATE TABLE playlists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await d.execute('''
          CREATE TABLE playlist_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
            item_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
            position INTEGER NOT NULL
          )''');
        if (withSearchAndSources) {
          await d.execute('''
            CREATE TABLE search_history (
              query TEXT PRIMARY KEY,
              updated_at INTEGER NOT NULL
            )''');
          await d.execute('''
            CREATE TABLE sources (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              base_url TEXT NOT NULL,
              header_name TEXT,
              header_value TEXT,
              enabled INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL
            )''');
        }
      });
      // A real user row — the migration must preserve it.
      await db.insert('media_items', {
        'id': 'legacy1',
        'title': 'Legacy Movie',
        'uri': '/sdcard/Legacy Movie.mkv',
        'type': 'local',
        'added_at': 1700000000000,
        'play_count': 3,
      });
      await db.close();
    }

    Future<Set<String>> tables(Database d) async {
      final rows =
          await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      return rows.map((r) => r['name'] as String).toSet();
    }

    Future<Set<String>> columns(Database d, String table) async {
      final rows = await d.rawQuery('PRAGMA table_info($table)');
      return rows.map((r) => r['name'] as String).toSet();
    }

    test('v1-shaped database converges to the full v7 schema, data intact',
        () async {
      await seedLegacyDb(withSearchAndSources: false);
      db = await openDatabase(
        path,
        version: 7,
        onCreate: (d, v) => DatabaseService.createSchema(d),
        onUpgrade: (d, o, n) => DatabaseService.upgradeSchema(d, o, n),
      );

      final t = await tables(db);
      for (final expected in [
        'media_items', 'watch_progress', 'downloads', 'playlists',
        'playlist_items', 'search_history', 'sources',
        'iptv_playlists', 'iptv_channels', 'nas_servers',
        'browser_history', 'browser_bookmarks', 'user_sites',
      ]) {
        expect(t, contains(expected), reason: 'table $expected missing');
      }
      expect(await columns(db, 'media_items'),
          containsAll(['play_uri', 'is_hidden']));
      expect(await columns(db, 'downloads'),
          containsAll(['headers', 'origin_url']));

      // User data survived the migration.
      final rows = await db.query('media_items', where: "id='legacy1'");
      expect(rows, hasLength(1));
      expect(rows.first['title'], 'Legacy Movie');
      expect(rows.first['play_count'], 3);

      // The upgraded DB is usable for real queries (no "no such table").
      final searched =
          await db.query('search_history', limit: 1);
      expect(searched, isEmpty);

      await db.close();
    });

    test('v2-shaped database (with search_history/sources) also converges',
        () async {
      await seedLegacyDb(withSearchAndSources: true);
      db = await openDatabase(
        path,
        version: 7,
        onCreate: (d, v) => DatabaseService.createSchema(d),
        onUpgrade: (d, o, n) => DatabaseService.upgradeSchema(d, o, n),
      );
      final t = await tables(db);
      expect(t, containsAll(['iptv_playlists', 'nas_servers']));
      expect(t, containsAll(['browser_history', 'user_sites']));
      expect(await columns(db, 'media_items'), contains('play_uri'));
      expect(await columns(db, 'downloads'), contains('origin_url'));
      await db.close();
    });

    test('convergence is idempotent (running it twice changes nothing)',
        () async {
      await seedLegacyDb(withSearchAndSources: false);
      db = await openDatabase(
        path,
        version: 7,
        onCreate: (d, v) => DatabaseService.createSchema(d),
        onUpgrade: (d, o, n) => DatabaseService.upgradeSchema(d, o, n),
      );
      final beforeTables = await tables(db);
      final beforeCols = await columns(db, 'media_items');

      // Re-run the convergence pass against an already-current schema.
      await DatabaseService.upgradeSchema(db, 7, 7);

      expect(await tables(db), beforeTables);
      expect(await columns(db, 'media_items'), beforeCols);
      await db.close();
    });

    test('fresh create path still builds the complete schema', () async {
      path = '${Directory.systemTemp.path}/'
          'p4_fresh_${DateTime.now().microsecondsSinceEpoch}.db';
      db = await openDatabase(
        path,
        version: 7,
        onCreate: (d, v) => DatabaseService.createSchema(d),
      );
      final t = await tables(db);
      expect(t, containsAll(['media_items', 'nas_servers', 'user_sites']));
      expect(
        await columns(db, 'media_items'),
        containsAll(['play_uri', 'is_hidden']),
      );
      await db.close();
    });
  });

  group('P4-M2: player auto-recovery decision core', () {
    test('only transport-level failures are recoverable', () {
      expect(
        PlayerService.isRecoverableNetworkError(
            const AppException(AppErrorType.network)),
        isTrue,
      );
      expect(
        PlayerService.isRecoverableNetworkError(
            const AppException(AppErrorType.timeout)),
        isTrue,
      );
      for (final t in [
        AppErrorType.notFound,
        AppErrorType.forbidden,
        AppErrorType.unsupported,
        AppErrorType.corrupted,
        AppErrorType.invalidInput,
        AppErrorType.unknown,
      ]) {
        expect(
          PlayerService.isRecoverableNetworkError(AppException(t)),
          isFalse,
          reason: '${t.name} must never auto-retry',
        );
      }
    });

    test('backoff schedule: 2s → 5s → 10s, capped', () {
      expect(PlayerService.recoveryDelay(0), const Duration(seconds: 2));
      expect(PlayerService.recoveryDelay(-3), const Duration(seconds: 2));
      expect(PlayerService.recoveryDelay(1), const Duration(seconds: 5));
      expect(PlayerService.recoveryDelay(2), const Duration(seconds: 10));
      expect(PlayerService.recoveryDelay(9), const Duration(seconds: 10),
          reason: 'must cap — no unbounded backoff');
    });

    test('attempt budget is bounded', () {
      expect(PlayerService.maxAutoRecoveryAttempts, 3);
      // Worst case wall time: 2s + 5s + 10s.
      var total = Duration.zero;
      for (var i = 0; i < PlayerService.maxAutoRecoveryAttempts; i++) {
        total += PlayerService.recoveryDelay(i);
      }
      expect(total, const Duration(seconds: 17));
    });
  });
}
