import 'package:flutter/foundation.dart';
import '../core/utils/logger.dart';
import '../data/models/download_task.dart';
import '../data/models/media_item.dart';
import '../data/models/playlist.dart';
import '../data/repositories/download_repository.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/playlist_repository.dart';
import '../data/repositories/source_repository.dart';
import '../services/recommendations/recommendation_engine.dart';

class HomeSectionState {
  HomeSectionState({this.items = const [], this.loading = false, this.error});

  final List<MediaItem> items;
  final bool loading;
  final Object? error;
}

/// Aggregates all home dashboard sections.
class HomeController extends ChangeNotifier {
  HomeController({
    required LibraryRepository library,
    required HistoryRepository history,
    required PlaylistRepository playlists,
    required DownloadRepository downloads,
    required SourceRepository sources,
    required RecommendationEngine engine,
  })  : _library = library,
        _history = history,
        _playlists = playlists,
        _downloads = downloads,
        _sources = sources,
        _engine = engine;

  final LibraryRepository _library;
  final HistoryRepository _history;
  final PlaylistRepository _playlists;
  final DownloadRepository _downloads;
  final SourceRepository _sources;
  final RecommendationEngine _engine;

  HomeSectionState continueWatching = HomeSectionState();
  HomeSectionState recent = HomeSectionState();
  HomeSectionState favorites = HomeSectionState();
  HomeSectionState recommended = HomeSectionState();

  int playlistCount = 0;
  int activeDownloads = 0;
  int localVideos = 0;
  int sourceCount = 0;
  bool loading = false;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _history.continueWatching(limit: 12),
        _library.query(const LibraryQuery(sort: SortBy.dateAdded, limit: 12)),
        _library.query(const LibraryQuery(favoritesOnly: true, limit: 12)),
        _library.query(const LibraryQuery(limit: 60)),
        _playlists.listWithCounts(),
        _downloads.all(),
        _library.countByType(MediaItemType.local),
        _sources.list(),
      ]);

      final cw = results[0] as List<MediaItem>;
      final recentItems = results[1] as List<MediaItem>;
      final favs = results[2] as List<MediaItem>;
      final pool = results[3] as List<MediaItem>;
      final pls = results[4] as List<PlaylistWithItems>;
      final dls = results[5] as List<DownloadTaskModel>;
      localVideos = results[6] as int;
      sourceCount = (results[7] as List).length;

      // Deterministic recommendations from local data only (no AI).
      // A second pass enriches with real stored progress where available.
      final progressMap = <String, WatchProgress?>{};
      for (final item in pool) {
        progressMap[item.id] = null;
      }
      final historyRows = await _history.history(limit: 60);
      final historyItemIds = historyRows.map((m) => m.id).toSet();
      final scored = _engine.recommend(
        candidates: pool,
        progressByItem: progressMap,
        recentHistory: [
          for (final row in historyRows)
            WatchProgress(
              itemId: row.id,
              positionMs: 1,
              updatedAt: row.lastPlayedAt ?? row.addedAt,
            ),
        ],
      );

      continueWatching = HomeSectionState(items: cw);
      recent = HomeSectionState(
          items:
              recentItems.where((m) => !cw.any((c) => c.id == m.id)).toList());
      favorites = HomeSectionState(items: favs);
      recommended = HomeSectionState(
          items: scored
              .where((sc) =>
                  historyItemIds.contains(sc.item.id) ||
                  sc.item.isFavorite ||
                  sc.score > 10)
              .map((sc) => sc.item)
              .toList());
      playlistCount = pls.length;
      activeDownloads = dls.where((d) => d.status.isActive).length;
    } catch (e, s) {
      AppLogger.instance.error('home', 'load failed', e, s);
      continueWatching = HomeSectionState(error: e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
