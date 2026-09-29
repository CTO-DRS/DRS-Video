import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/core/storage/database_service.dart';
import 'package:drs_video/core/storage/preferences_service.dart';
import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/data/repositories/history_repository.dart';
import 'package:drs_video/data/repositories/library_repository.dart';
import 'package:drs_video/data/repositories/playlist_repository.dart';
import 'package:drs_video/services/backup/backup_service.dart';
import 'package:drs_video/services/network/stream_detector.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  // =====================================================================
  // StreamDetector (v1.7.0 — HLS/DASH/live classification)
  // =====================================================================
  group('StreamDetector.classifyUrl', () {
    test('HLS manifests by extension', () {
      expect(StreamDetector.classifyUrl('https://cdn.io/live/master.m3u8'),
          StreamKind.hls);
      expect(StreamDetector.classifyUrl('https://a.b/x/y/playlist.M3U8'),
          StreamKind.hls);
      expect(StreamDetector.classifyUrl('https://a.b/stream.m3u?tok=1'),
          StreamKind.hls);
    });

    test('DASH manifests by extension', () {
      expect(StreamDetector.classifyUrl('https://cdn.io/manifest.mpd'),
          StreamKind.dash);
      expect(
          StreamDetector.classifyUrl('https://cdn.io/VIDEO.MPD?drm=widevine'),
          StreamKind.dash);
    });

    test('progressive video files', () {
      expect(StreamDetector.classifyUrl('https://cdn.io/movie.mp4'),
          StreamKind.progressive);
      expect(StreamDetector.classifyUrl('https://cdn.io/clip.WEBM'),
          StreamKind.progressive);
      expect(StreamDetector.classifyUrl('https://cdn.io/a/b/c.ts'),
          StreamKind.progressive);
    });

    test('query strings and fragments are ignored', () {
      expect(
          StreamDetector.classifyUrl(
              'https://cdn.io/live/index.m3u8?token=abc.def&exp=1#seg'),
          StreamKind.hls);
    });

    test('unknown for HTML pages and extension-less URLs', () {
      expect(StreamDetector.classifyUrl('https://example.com/watch/123'),
          StreamKind.unknown);
      expect(StreamDetector.classifyUrl('https://example.com'),
          StreamKind.unknown);
      // .php is an extension but not a media one.
      expect(StreamDetector.classifyUrl('https://example.com/page.php'),
          StreamKind.unknown);
    });

    test('paths without a file extension handled safely', () {
      expect(StreamDetector.extensionForTesting('/a/b/.hidden'), '');
      expect(StreamDetector.extensionForTesting('/a/b/file.'), '');
      expect(StreamDetector.extensionForTesting('/'), '');
    });
  });

  group('StreamDetector.classifyContentType', () {
    test('Apple/Nokia HLS mime types', () {
      expect(StreamDetector.classifyContentType('application/vnd.apple.mpegurl'),
          StreamKind.hls);
      expect(StreamDetector.classifyContentType('application/x-mpegurl'),
          StreamKind.hls);
      expect(
          StreamDetector.classifyContentType(
              'application/vnd.apple.mpegurl; charset=utf-8'),
          StreamKind.hls);
    });

    test('DASH mime type', () {
      expect(StreamDetector.classifyContentType('application/dash+xml'),
          StreamKind.dash);
    });

    test('video/audio fallback and junk', () {
      expect(StreamDetector.classifyContentType('video/mp4'),
          StreamKind.progressive);
      expect(StreamDetector.classifyContentType('audio/mpeg'),
          StreamKind.progressive);
      expect(StreamDetector.classifyContentType('text/html'),
          StreamKind.unknown);
      expect(StreamDetector.classifyContentType(null), StreamKind.unknown);
      expect(StreamDetector.classifyContentType(''), StreamKind.unknown);
    });
  });

  group('StreamDetector.isLiveLike', () {
    test('live keyword wins immediately', () {
      expect(
          StreamDetector.isLiveLike(
              url: 'https://cdn.io/live/master.m3u8', sizeBytes: 12345),
          isTrue);
      expect(
          StreamDetector.isLiveLike(
              url: 'https://tv.io/hls/chunklist_w123.m3u8', sizeBytes: 999),
          isTrue);
    });

    test('HLS/DASH without size or range support treated as live', () {
      expect(
          StreamDetector.isLiveLike(
              url: 'https://cdn.io/event.m3u8', sizeBytes: null),
          isTrue);
      expect(
          StreamDetector.isLiveLike(
              url: 'https://cdn.io/stream.mpd',
              contentType: 'application/dash+xml',
              sizeBytes: null),
          isTrue);
    });

    test('VOD manifests (sized playlist) are NOT live', () {
      expect(
          StreamDetector.isLiveLike(
              url: 'https://cdn.io/vod/movie.m3u8', sizeBytes: 4096),
          isFalse);
      expect(
          StreamDetector.isLiveLike(
              url: 'https://cdn.io/vod/movie.m3u8',
              sizeBytes: null,
              resumable: true),
          isFalse);
    });

    test('progressive files and pages are never live', () {
      expect(
          StreamDetector.isLiveLike(
              url: 'https://cdn.io/movie.mp4', sizeBytes: null),
          isFalse);
      expect(
          StreamDetector.isLiveLike(url: 'https://example.com/watch/1'),
          isFalse);
    });
  });

  group('StreamDetector.badgeFor', () {
    test('returns a kind only for recognizable stream URLs', () {
      expect(StreamDetector.badgeFor('https://a.io/x.m3u8'), StreamKind.hls);
      expect(StreamDetector.badgeFor('https://a.io/x.mp4'),
          StreamKind.progressive);
      expect(StreamDetector.badgeFor('https://a.io/page.html'), isNull);
      expect(StreamDetector.badgeFor(''), isNull);
    });
  });

  // =====================================================================
  // Library sorting v1.7.0 (playCount / resolution / direction)
  // =====================================================================
  group('library sorting v1.7.0', () {
    late DatabaseService db;
    late LibraryRepository library;

    setUp(() async {
      db = DatabaseService.instance;
      await db.database;
      library = LibraryRepository(db);
    });

    tearDown(() async {
      await db.deleteAllData();
    });

    Future<MediaItem> add(
      String id, {
      String title = 't',
      int? durationMs,
      int? size,
      int? width,
      int? height,
    }) async {
      final item = MediaItem(
        id: id,
        title: title,
        uri: 'https://example.com/$id.mp4',
        type: MediaItemType.network,
        durationMs: durationMs,
        sizeBytes: size,
        width: width,
        height: height,
      );
      await library.upsert(item);
      return item;
    }

    test('playCount descending puts most played first', () async {
      final a = await add('a', title: 'A');
      await add('b', title: 'B');
      final c = await add('c', title: 'C');
      for (var i = 0; i < 3; i++) {
        await library.markPlayed(a.id);
      }
      await library.markPlayed(c.id);
      // Re-read from the DB: markPlayed mutates rows, not our objects.
      final counts = {
        for (final m in await library.query(const LibraryQuery()))
          m.id: m.playCount
      };
      expect(counts['a'], 3);
      expect(counts['b'], 0);
      expect(counts['c'], 1);

      final desc = await library.query(const LibraryQuery(
          sort: SortBy.playCount, direction: SortDirection.descending));
      expect(desc.map((m) => m.id).toList(), ['a', 'c', 'b']);

      final asc = await library.query(const LibraryQuery(
          sort: SortBy.playCount, direction: SortDirection.ascending));
      expect(asc.map((m) => m.id).toList(), ['b', 'c', 'a']);
    });

    test('resolution sorts by pixel area, NULLs last in both directions',
        () async {
      await add('sd', title: 'SD', width: 640, height: 480);
      await add('hd', title: 'HD', width: 1920, height: 1080);
      await add('fhd', title: 'FHD', width: 2560, height: 1440);
      await add('unknown', title: 'NoRes');

      final desc = await library.query(const LibraryQuery(
          sort: SortBy.resolution, direction: SortDirection.descending));
      expect(desc.map((m) => m.id).toList(), ['fhd', 'hd', 'sd', 'unknown']);

      final asc = await library.query(const LibraryQuery(
          sort: SortBy.resolution, direction: SortDirection.ascending));
      expect(asc.map((m) => m.id).toList(), ['sd', 'hd', 'fhd', 'unknown']);
    });

    test('direction works for name sort too', () async {
      await add('x2', title: 'banana');
      await add('x1', title: 'Apple');
      await add('x3', title: 'cherry');

      final asc = await library.query(const LibraryQuery(
          sort: SortBy.name, direction: SortDirection.ascending));
      expect(asc.map((m) => m.title).toList(), ['Apple', 'banana', 'cherry']);

      final desc = await library.query(const LibraryQuery(
          sort: SortBy.name, direction: SortDirection.descending));
      expect(desc.map((m) => m.title).toList(), ['cherry', 'banana', 'Apple']);
    });

    test('existing sorts keep nulls-last behaviour when reversed',
        () async {
      await add('short', title: 'short', durationMs: 60);
      await add('long', title: 'long', durationMs: 9000);
      await add('noDur', title: 'noDur');

      final asc = await library.query(const LibraryQuery(
          sort: SortBy.duration, direction: SortDirection.ascending));
      expect(asc.map((m) => m.id).toList(), ['short', 'long', 'noDur']);

      final desc = await library.query(const LibraryQuery(
          sort: SortBy.duration, direction: SortDirection.descending));
      expect(desc.map((m) => m.id).toList(), ['long', 'short', 'noDur']);
    });
  });

  // =====================================================================
  // Backup codec + merge (v1.7.0)
  // =====================================================================
  group('BackupCodec', () {
    BackupPayload samplePayload() => BackupPayload(
          items: [
            (MediaItem(
              id: 'mn_1',
              title: 'Clip One',
              uri: 'https://cdn.io/one.mp4',
              type: MediaItemType.network,
              sourceId: 'direct',
            )
                  ..isFavorite = true
                  ..playCount = 4)
                .toMap(),
          ],
          playlists: [
            {
              'id': 'pl_1',
              'name': 'أغاني',
              'createdAt': 1700000000000,
              'itemIds': ['mn_1']
            },
          ],
          progress: [
            WatchProgress(
              itemId: 'mn_1',
              positionMs: 30000,
              durationMs: 100000,
              completed: false,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000001000),
            ).toMap(),
          ],
          searches: ['فيديو كرتون', 'أخبار'],
          settings: {'default_quality': '1080p', 'enable_pip': false},
        );

    test('round-trip preserves all sections', () {
      final codec = BackupCodec();
      final raw = codec.encode(samplePayload());
      final decoded = codec.decode(raw);
      expect(decoded.appVersion, AppConstants.appVersion);
      expect(decoded.payload.items, hasLength(1));
      expect(decoded.payload.items.first['id'], 'mn_1');
      expect(decoded.payload.playlists.first['name'], 'أغاني');
      expect(decoded.payload.searches, ['فيديو كرتون', 'أخبار']);
      expect(decoded.payload.settings['default_quality'], '1080p');
      expect(decoded.payload.settings['enable_pip'], false);
    });

    test('tampered payload fails checksum validation', () {
      final codec = BackupCodec();
      final raw = codec.encode(samplePayload());
      final map = jsonDecode(raw) as Map<String, Object?>;
      (map['data'] as Map<String, Object?>)['items'] = <Object?>[];
      final tampered = const JsonEncoder.withIndent('  ').convert(map);
      expect(() => codec.decode(tampered),
          throwsA(predicate((e) => e is BackupFormatException && e.reason == 'checksum')));
    });

    test('foreign format / schema / junk rejected with stable reasons', () {
      final codec = BackupCodec();
      expect(() => codec.decode(''), throwsA(predicate((e) => (e as BackupFormatException).reason == 'empty')));
      expect(() => codec.decode('not json {'),
          throwsA(predicate((e) => (e as BackupFormatException).reason == 'json')));
      expect(
          () => codec.decode(jsonEncode({'format': 'other-app', 'data': {}})),
          throwsA(predicate((e) => (e as BackupFormatException).reason == 'format')));
      expect(
          () => codec.decode(jsonEncode({
                'format': BackupCodec.format,
                'schema': 99,
                'data': {}
              })),
          throwsA(predicate((e) => (e as BackupFormatException).reason == 'schema')));
    });

    test('normalize converts JSON bools to DB ints recursively', () {
      final out = BackupCodec.normalize({
        'is_favorite': true,
        'completed': false,
        'nested': {'x': true},
        'keep': 7,
      });
      expect(out['is_favorite'], 1);
      expect(out['completed'], 0);
      expect((out['nested'] as Map)['x'], 1);
      expect(out['keep'], 7);
    });
  });

  group('BackupService.mergeInto', () {
    late DatabaseService db;
    late LibraryRepository library;
    late PlaylistRepository playlists;
    late HistoryRepository history;
    late BackupService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = DatabaseService.instance;
      await db.database;
      library = LibraryRepository(db);
      playlists = PlaylistRepository(db);
      history = HistoryRepository(db);
      service = BackupService(
        library: library,
        playlists: playlists,
        history: history,
        prefs: PreferencesService(await SharedPreferences.getInstance()),
      );
    });

    tearDown(() async {
      await db.deleteAllData();
    });

    test('merges new items, skips duplicates, rebuilds playlists',
        () async {
      // Existing item: same URI as backup item mn_1 → duplicate.
      await library.upsert(MediaItem(
        id: 'local_old',
        title: 'Existing',
        uri: 'https://cdn.io/one.mp4',
        type: MediaItemType.network,
      ));

      final payload = BackupPayload(
        items: [
          MediaItem(
                  id: 'mn_1',
                  title: 'Clip One',
                  uri: 'https://cdn.io/one.mp4',
                  type: MediaItemType.network)
              .toMap(),
          MediaItem(
                  id: 'mn_2',
                  title: 'Clip Two',
                  uri: 'https://cdn.io/two.mp4',
                  type: MediaItemType.network)
              .toMap(),
        ],
        playlists: [
          // mn_1 is known (via local_old? no — knownIds tracks BACKUP ids),
          // so only mn_2 survives the knownIds filter.
          {'id': 'pl_x', 'name': 'Favorites', 'createdAt': 1, 'itemIds': ['mn_2', 'ghost']},
        ],
        progress: [
          WatchProgress(
            itemId: 'mn_2',
            positionMs: 1000,
            durationMs: 10000,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          ).toMap(),
        ],
        searches: ['abc', 'ABC', ' '],
        settings: {'default_quality': '720p'},
      );

      final result = await service.mergeInto(payload);

      expect(result.addedItems, 1); // mn_2 only
      expect(result.skippedItems, 1); // mn_1 duplicate by uri
      expect(result.addedPlaylists, 1);
      expect(result.mergedPlaylists, 0);

      final restored = await library.byId('mn_2');
      expect(restored, isNotNull);
      expect(restored!.title, 'Clip Two');

      final pls = await playlists.list();
      expect(pls, hasLength(1));
      final plItems = await playlists.items(pls.first.id);
      expect(plItems.map((m) => m.id), ['mn_2']); // ghost filtered out

      final prog = await history.progressFor('mn_2');
      expect(prog, isNotNull);
      expect(prog!.positionMs, 1000);

      final searches = await history.recentSearches(limit: 10);
      expect(searches, ['abc']); // dedup case-insensitive, blank dropped
    });

    test('never regresses newer local watch progress', () async {
      await library.upsert(MediaItem(
        id: 'mn_9',
        title: 'Nine',
        uri: 'https://cdn.io/nine.mp4',
        type: MediaItemType.network,
      ));
      await history.upsertProgress(WatchProgress(
        itemId: 'mn_9',
        positionMs: 90000,
        durationMs: 100000,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(9999999999),
      ));

      final result = await service.mergeInto(BackupPayload(
        items: const [],
        playlists: const [],
        progress: [
          WatchProgress(
            itemId: 'mn_9',
            positionMs: 10,
            durationMs: 100000,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
          ).toMap(),
        ],
        searches: const [],
        settings: const {},
      ));

      expect(result.restoredProgress, 0);
      final kept = await history.progressFor('mn_9');
      expect(kept!.positionMs, 90000);
    });

    test('same-name playlists merge instead of duplicating', () async {
      await library.upsert(MediaItem(
        id: 'mn_a',
        title: 'A',
        uri: 'https://cdn.io/a.mp4',
        type: MediaItemType.network,
      ));
      final existing = await playlists.create('Music');
      await playlists.addItem(existing.id, 'mn_a');

      final result = await service.mergeInto(BackupPayload(
        items: const [],
        playlists: [
          {'id': 'pl_old', 'name': 'Music', 'createdAt': 1, 'itemIds': ['mn_a']},
        ],
        progress: const [],
        searches: const [],
        settings: const {},
      ));

      expect(result.mergedPlaylists, 1);
      expect(result.addedPlaylists, 0);
      final pls = await playlists.list();
      expect(pls.where((p) => p.name == 'Music'), hasLength(1));
    });

    test('summarize reports live counts', () async {
      await library.upsert(MediaItem(
        id: 's1',
        title: 'S',
        uri: 'https://cdn.io/s.mp4',
        type: MediaItemType.network,
      ));
      final summary = await service.summarize();
      expect(summary.items, 1);
      expect(summary.playlists, 0);
      expect(summary.progressEntries, 0);
      expect(summary.searches, 0);
    });
  });

  group('PreferencesService snapshot', () {
    test('export → apply round-trip and exclusions', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs =
          PreferencesService(await SharedPreferences.getInstance());
      await prefs.raw.setString(PrefKeys.defaultQuality, '1080p');
      await prefs.raw.setBool(PrefKeys.enablePip, false);
      await prefs.raw.setDouble(PrefKeys.defaultSpeed, 1.5);
      await prefs.raw.setInt(PrefKeys.blockedRequestsCount, 500); // excluded
      await prefs.raw.setBool(PrefKeys.firstRunDone, true); // excluded

      final snapshot = prefs.exportSnapshot();
      expect(snapshot.containsKey(PrefKeys.blockedRequestsCount), isFalse);
      expect(snapshot.containsKey(PrefKeys.firstRunDone), isFalse);
      expect(snapshot[PrefKeys.defaultQuality], '1080p');
      expect(snapshot[PrefKeys.defaultSpeed], 1.5);

      SharedPreferences.setMockInitialValues({});
      final fresh =
          PreferencesService(await SharedPreferences.getInstance());
      final applied = await fresh.applySnapshot(snapshot);
      expect(applied, greaterThanOrEqualTo(3));
      expect(fresh.raw.getString(PrefKeys.defaultQuality), '1080p');
      expect(fresh.raw.getBool(PrefKeys.enablePip), false);
      expect(fresh.raw.getDouble(PrefKeys.defaultSpeed), 1.5);
      expect(fresh.raw.getString(PrefKeys.librarySort), isNull);
    });

    test('settings survive a full backup round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs =
          PreferencesService(await SharedPreferences.getInstance());
      await prefs.raw.setString(PrefKeys.defaultQuality, '720p');

      final payload = BackupPayload(
        items: const [],
        playlists: const [],
        progress: const [],
        searches: const [],
        settings: prefs.exportSnapshot(),
      );
      final codec = BackupCodec();
      final decoded = codec.decode(codec.encode(payload));
      expect(decoded.payload.settings[PrefKeys.defaultQuality], '720p');
    });
  });
}
