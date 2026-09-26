import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:drs_video/core/storage/database_service.dart';
import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/data/models/playlist.dart';
import 'package:drs_video/data/repositories/bookmark_repository.dart';
import 'package:drs_video/data/repositories/history_repository.dart';
import 'package:drs_video/data/repositories/library_repository.dart';
import 'package:drs_video/data/repositories/playlist_repository.dart';
import 'package:drs_video/services/backup/backup_service.dart';
import 'package:drs_video/services/player/ab_loop.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AbLoop state machine', () {
    test('cycles off -> aMarked -> active -> off', () {
      final loop = AbLoop();
      expect(loop.state, AbLoopState.off);

      loop.mark(const Duration(seconds: 10));
      expect(loop.state, AbLoopState.aMarked);
      expect(loop.a, const Duration(seconds: 10));

      loop.mark(const Duration(seconds: 30));
      expect(loop.state, AbLoopState.active);
      expect(loop.b, const Duration(seconds: 30));

      loop.mark(const Duration(seconds: 5)); // tap again clears
      expect(loop.state, AbLoopState.off);
    });

    test('swaps marks when B lands before A', () {
      final loop = AbLoop();
      loop.mark(const Duration(seconds: 30));
      loop.mark(const Duration(seconds: 5));
      expect(loop.state, AbLoopState.active);
      expect(loop.a, const Duration(seconds: 5));
      expect(loop.b, const Duration(seconds: 30));
    });

    test('jumpFrom rewinds past B to A, and only then', () {
      final loop = AbLoop();
      loop.mark(const Duration(seconds: 10));
      loop.mark(const Duration(seconds: 30));
      expect(loop.jumpFrom(const Duration(seconds: 29)), isNull);
      expect(loop.jumpFrom(const Duration(seconds: 30)),
          const Duration(seconds: 10));
      expect(loop.jumpFrom(const Duration(seconds: 45)),
          const Duration(seconds: 10));
      expect(loop.contains(const Duration(seconds: 20)), isTrue);
      expect(loop.contains(const Duration(seconds: 40)), isFalse);
    });
  });

  group('ViewGestureTracker', () {
    test('zoom out-in maps to mpv logarithmic zoom', () {
      final t = ViewGestureTracker(initialZoom: 0, initialPan: Offset.zero)
        ..begin(distance: 100, midpoint: Offset.zero);
      final r = t.update(
        distance: 200, // 2x pinch out
        midpoint: Offset.zero,
        viewportShortSide: 400,
        maxZoom: 2.5,
        maxPan: 1.0,
      );
      expect(r.zoom, closeTo(1.0, 0.01)); // 2x == zoom value 1.0
      final r2 = t.update(
        distance: 50, // pinch in to half
        midpoint: Offset.zero,
        viewportShortSide: 400,
        maxZoom: 2.5,
        maxPan: 1.0,
      );
      // mpv zoom clamps at 0 (never zooms out below fit).
      expect(r2.zoom, 0.0);
    });

    test('pan follows midpoint drag and clamps', () {
      final t = ViewGestureTracker(initialZoom: 1, initialPan: Offset.zero)
        ..begin(distance: 100, midpoint: const Offset(200, 200));
      final r = t.update(
        distance: 100,
        midpoint: const Offset(400, 260),
        viewportShortSide: 400,
        maxZoom: 2.5,
        maxPan: 1.0,
      );
      expect(r.pan.dx, 0.5);
      expect(r.pan.dy, closeTo(0.15, 0.001));
    });
  });

  group('BackupCodec', () {
    test('encode/decode round-trips every section', () {
      final item = MediaItem(
        id: 'v1',
        title: 'فيديو تجريبي',
        uri: '/tmp/v1.mp4',
        type: MediaItemType.local,
      )..playCount = 3;
      final map = BackupCodec.encode(
        itemMaps: [item.toMap()],
        progressMaps: [
          WatchProgress(
            itemId: 'v1',
            positionMs: 5000,
            durationMs: 60000,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          ).toMap()
        ],
        playlistMaps: [Playlist(id: 'p1', name: 'قائمتي').toMap()],
        membershipMaps: [
          {'playlist_id': 'p1', 'item_id': 'v1', 'position': 0}
        ],
        bookmarkMaps: [
          VideoBookmark(itemId: 'v1', positionMs: 12000).toMap()
        ],
        watchDailyMaps: [
          {'day': '2026-09-26', 'watched_ms': 60000, 'sessions': 2}
        ],
        prefs: {'default_speed': 1.5, 'theme_mode': 'dark'},
      );
      final json = jsonEncode(map);
      final decoded = BackupCodec.decode(json);
      expect(decoded, isNotNull);
      expect(decoded!.items.length, 1);
      expect(decoded.items.first.title, 'فيديو تجريبي');
      expect(decoded.items.first.playCount, 3);
      expect(decoded.progress.first['position_ms'], 5000);
      expect(decoded.playlists.first['name'], 'قائمتي');
      expect(decoded.bookmarks.first['position_ms'], 12000);
      expect(decoded.watchDaily.first['watched_ms'], 60000);
      expect(decoded.prefs['default_speed'], 1.5);
    });

    test('rejects foreign or corrupt payloads', () {
      expect(BackupCodec.decode('not json at all'), isNull);
      expect(BackupCodec.decode('{"app":"Other App","schema":1}'), isNull);
      expect(
        BackupCodec.decode(
            '{"app":"DRS Video Backup","schema":"bad"}'),
        isNull,
      );
      // Future schema must be rejected (downgrade safety).
      expect(
        BackupCodec.decode(
            '{"app":"DRS Video Backup","schema":99,"mediaItems":[]}'),
        isNull,
      );
    });
  });

  group('v1.1.0 persistence', () {
    late DatabaseService db;
    late BookmarkRepository bookmarks;
    late HistoryRepository history;
    late LibraryRepository library;
    late PlaylistRepository playlists;

    setUp(() async {
      db = DatabaseService.instance;
      await db.database;
      bookmarks = BookmarkRepository(db);
      history = HistoryRepository(db);
      library = LibraryRepository(db);
      playlists = PlaylistRepository(db);
    });

    tearDown(() async {
      await db.deleteAllData();
    });

    test('bookmarks CRUD round-trip', () async {
      final id1 = await bookmarks
          .add(VideoBookmark(itemId: 'v1', positionMs: 1000));
      await bookmarks.add(VideoBookmark(
        itemId: 'v1',
        positionMs: 5000,
        label: 'الفصل الأول',
      ));
      final forItem = await bookmarks.forItem('v1');
      expect(forItem.length, 2);
      expect(forItem.first.positionMs, 1000); // ordered by position
      expect(forItem[1].label, 'الفصل الأول');

      await bookmarks.delete(id1);
      expect((await bookmarks.forItem('v1')).length, 1);

      // Bulk restore path.
      await bookmarks.upsertAll([
        VideoBookmark(itemId: 'v2', positionMs: 42),
        VideoBookmark(itemId: 'v3', positionMs: 77),
      ]);
      expect((await bookmarks.all()).length, 3);
    });

    test('watch stats accumulate per day and merge on restore', () async {
      await history.recordWatchedMs(30000);
      await history.recordWatchedMs(45000);
      await history.recordSession();
      expect(await history.totalWatchedMs(), 75000);

      final today = await history.watchDaily();
      expect(today, isNotEmpty);
      expect(today.last.sessions, 1);

      // Restore merge never lowers newer local values.
      await history.mergeWatchDay(
        day: today.last.day,
        watchedMs: 1000,
        sessions: 9,
      );
      final merged = await history.watchDaily();
      expect(merged.last.watchedMs, 75000); // max(local, backup)
      expect(merged.last.sessions, 9); // max(local, backup)

      // Streak counts today's activity.
      expect(await history.currentStreakDays(), greaterThanOrEqualTo(1));

      await history.clearWatchStats();
      expect(await history.totalWatchedMs(), 0);
    });

    test('topPlayed ranks by play_count', () async {
      final a = MediaItem(id: 'a', title: 'A', uri: '/a', type: MediaItemType.local);
      final b = MediaItem(id: 'b', title: 'B', uri: '/b', type: MediaItemType.local);
      await library.upsert(a);
      await library.upsert(b);
      await library.markPlayed('a');
      await library.markPlayed('a');
      await library.markPlayed('a');
      await library.markPlayed('b');
      final top = await library.topPlayed();
      expect(top.first.id, 'a');
      expect(top.first.playCount, 3);
    });

    test('playlist memberships export/import keep order', () async {
      final a = MediaItem(id: 'a', title: 'A', uri: '/a', type: MediaItemType.local);
      await library.upsert(a);
      final pl = await playlists.create('قائمة');
      await playlists.addItem(pl.id, 'a');
      final exported = await playlists.exportMemberships();
      expect(exported, isNotEmpty);

      await db.deleteAllData();
      // Restore order mirrors BackupService: media items first, then
      // playlists + memberships (playlist_items has an FK on media).
      await library.upsert(a);
      await playlists.upsertAll([Playlist.fromMap(pl.toMap())]);
      await playlists.importMemberships(exported);
      final items = await playlists.items(pl.id);
      expect(items.first.id, 'a');
    });
  });
}
