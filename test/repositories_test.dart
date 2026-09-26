import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:drs_video/core/storage/database_service.dart';
import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/data/repositories/history_repository.dart';
import 'package:drs_video/data/repositories/library_repository.dart';
import 'package:drs_video/data/repositories/playlist_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;
  late LibraryRepository library;
  late HistoryRepository history;
  late PlaylistRepository playlists;

  setUp(() async {
    db = DatabaseService.instance;
    await db.database;
    library = LibraryRepository(db);
    history = HistoryRepository(db);
    playlists = PlaylistRepository(db);
  });

  tearDown(() async {
    await db.deleteAllData();
  });

  MediaItem media(String id, {String title = 't', MediaItemType type = MediaItemType.network}) =>
      MediaItem(
        id: id,
        title: title,
        uri: 'https://example.com/$id.mp4',
        type: type,
      );

  test('library upsert + query with search', () async {
    await library.upsert(media('1', title: 'Big Buck Bunny'));
    await library.upsert(media('2', title: 'Sintel Trailer'));

    final all = await library.query(const LibraryQuery());
    expect(all.length, 2);

    final found = await library.query(const LibraryQuery(search: 'bunny'));
    expect(found.length, 1);
    expect(found.first.title, 'Big Buck Bunny');
  });

  test('favorites toggle reflected in filtered query', () async {
    await library.upsert(media('a'));
    await library.setFavorite('a', true);
    final favs = await library.query(const LibraryQuery(favoritesOnly: true));
    expect(favs.length, 1);
    expect(library.countFavorites(), completion(1));
  });

  test('watch progress upsert and continue watching', () async {
    await library.upsert(media('p'));
    await library.markPlayed('p');
    await history.upsertProgress(WatchProgress(
      itemId: 'p',
      positionMs: 60000,
      durationMs: 600000,
      updatedAt: DateTime.now(),
    ));

    final progress = await history.progressFor('p');
    expect(progress, isNotNull);
    expect(progress!.positionMs, 60000);
    expect(progress.ratio(), closeTo(0.1, 0.001));

    final cw = await history.continueWatching();
    expect(cw.length, 1);
  });

  test('progress map bulk load', () async {
    await library.upsert(media('x'));
    await history.upsertProgress(WatchProgress(
      itemId: 'x',
      positionMs: 1000,
      updatedAt: DateTime.now(),
    ));
    final map = await history.progressMap();
    expect(map.containsKey('x'), isTrue);
  });

  test('search history add/dedupe/clear', () async {
    await history.addSearch('action');
    await history.addSearch('action movies');
    await history.addSearch('action');
    final recent = await history.recentSearches();
    expect(recent.length, 2);
    expect(recent.first, 'action');
    await history.clearSearches();
    expect(await history.recentSearches(), isEmpty);
  });

  test('playlist CRUD, membership and reorder', () async {
    await library.upsert(media('m1'));
    await library.upsert(media('m2'));
    await library.upsert(media('m3'));

    final pl = await playlists.create('My List');
    await playlists.addItems(pl.id, ['m1', 'm2', 'm3']);

    var items = await playlists.items(pl.id);
    expect(items.map((m) => m.id).toList(), ['m1', 'm2', 'm3']);

    // No duplicates on re-add.
    await playlists.addItem(pl.id, 'm1');
    items = await playlists.items(pl.id);
    expect(items.length, 3);

    // Reorder: move m3 to front.
    await playlists.reorder(pl.id, ['m3', 'm1', 'm2']);
    items = await playlists.items(pl.id);
    expect(items.map((m) => m.id).toList(), ['m3', 'm1', 'm2']);

    // Remove item.
    await playlists.removeItem(pl.id, 'm1');
    items = await playlists.items(pl.id);
    expect(items.map((m) => m.id).toList(), ['m3', 'm2']);

    // Rename + delete.
    await playlists.rename(pl.id, 'Renamed');
    final listed = await playlists.list();
    expect(listed.first.name, 'Renamed');
    await playlists.delete(pl.id);
    expect(await playlists.list(), isEmpty);
  });

  test('deleteMany removes items and cascades progress', () async {
    await library.upsert(media('d1'));
    await history.upsertProgress(WatchProgress(
      itemId: 'd1',
      positionMs: 1000,
      updatedAt: DateTime.now(),
    ));
    await library.deleteMany(['d1']);
    expect(await history.progressFor('d1'), isNull);
  });

  test('MediaItem map round-trip preserves headers and metadata', () async {
    final item = MediaItem(
      id: 'hdr',
      title: 'Headers',
      uri: 'https://cdn.example.com/h.mp4',
      type: MediaItemType.network,
      durationMs: 90000,
      sizeBytes: 12345,
      headers: {'Authorization': 'Bearer token123'},
    );
    await library.upsert(item);
    final restored = await library.byId('hdr');
    expect(restored, isNotNull);
    expect(restored!.headers, {'Authorization': 'Bearer token123'});
    expect(restored.durationMs, 90000);
  });
}
