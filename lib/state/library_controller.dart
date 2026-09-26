import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/storage/preferences_service.dart';
import '../core/utils/logger.dart';
import '../data/models/media_item.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/playlist_repository.dart';

enum LibraryTab { all, favorites, downloads, recent, continueWatching, local, history, platforms }

/// Drives the library screen: tab data, filters, sort, multi-selection and
/// bulk operations.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required LibraryRepository library,
    required HistoryRepository history,
    required PlaylistRepository playlists,
    PreferencesService? prefs,
  })  : _library = library,
        _history = history,
        _playlists = playlists,
        _prefs = prefs {
    _restoreSortPrefs();
  }

  final LibraryRepository _library;
  final HistoryRepository _history;
  final PlaylistRepository _playlists;
  final PreferencesService? _prefs;

  /// Restores the last-used sort key/direction (v1.7.0). Corrupt or
  /// unknown stored names silently fall back to the defaults.
  void _restoreSortPrefs() {
    final p = _prefs;
    if (p == null) return;
    final s = p.raw.getString(PrefKeys.librarySort);
    if (s != null) {
      final restored = SortBy.values.where((v) => v.name == s).firstOrNull;
      if (restored != null) sort = restored;
    }
    final d = p.raw.getString(PrefKeys.librarySortDirection);
    if (d != null) {
      final restoredDir =
          SortDirection.values.where((v) => v.name == d).firstOrNull;
      if (restoredDir != null) direction = restoredDir;
    }
  }

  void _persistSortPrefs() {
    final p = _prefs;
    if (p == null) return;
    p.raw.setString(PrefKeys.librarySort, sort.name);
    p.raw.setString(PrefKeys.librarySortDirection, direction.name);
  }

  LibraryTab tab = LibraryTab.all;
  List<MediaItem> items = [];
  Map<String, WatchProgress> progressById = {};
  bool loading = false;
  Object? error;

  // Filters (shared across tabs)
  String search = '';
  MediaItemType? typeFilter;
  String? sourceFilter;
  DurationFilter durationFilter = DurationFilter.any;
  SortBy sort = SortBy.dateAdded;
  SortDirection direction = SortDirection.descending;

  // Multi-select
  final Set<String> selected = {};
  bool get selecting => selected.isNotEmpty;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      switch (tab) {
        case LibraryTab.all:
          items = await _library.query(_query());
        case LibraryTab.favorites:
          items = await _library.query(_query(favoritesOnly: true));
        case LibraryTab.downloads:
          items = await _library.query(_query(type: MediaItemType.download));
        case LibraryTab.local:
          items = await _library.query(_query(type: MediaItemType.local));
        case LibraryTab.recent:
          items = await _library.query(_query()).then((l) => l.take(100).toList());
        case LibraryTab.continueWatching:
          items = await _history.continueWatching(limit: 200);
        case LibraryTab.history:
          items = await _history.history();
        case LibraryTab.platforms:
          // The platforms tab manages its own data (links/IPTV/NAS) via
          // PlatformsController — nothing to load here.
          items = [];
      }
      progressById = await _history.progressMap();
    } catch (e, s) {
      AppLogger.instance.error('library', 'load failed', e, s);
      error = e;
    } finally {
      loading = false;
      selected.clear();
      notifyListeners();
    }
  }

  LibraryQuery _query({bool favoritesOnly = false, MediaItemType? type}) => LibraryQuery(
        search: search.isEmpty ? null : search,
        type: type ?? typeFilter,
        sourceId: sourceFilter,
        favoritesOnly: favoritesOnly,
        durationFilter: durationFilter,
        sort: tab == LibraryTab.recent ? SortBy.dateAdded : sort,
        direction: direction,
      );

  void setTab(LibraryTab t) {
    tab = t;
    load();
  }

  void setSearch(String q) {
    search = q;
    load();
  }

  void setTypeFilter(MediaItemType? t) {
    typeFilter = t;
    load();
  }

  void setSourceFilter(String? s) {
    sourceFilter = s;
    load();
  }

  void setDurationFilter(DurationFilter d) {
    durationFilter = d;
    load();
  }

  void setSort(SortBy s) {
    sort = s;
    _persistSortPrefs();
    load();
  }

  void setDirection(SortDirection d) {
    if (direction == d) return;
    direction = d;
    _persistSortPrefs();
    load();
  }

  /// Flips the current direction and persists it (used by the toolbar
  /// toggle button on the library screen).
  void toggleDirection() => setDirection(
        direction == SortDirection.ascending
            ? SortDirection.descending
            : SortDirection.ascending,
      );

  void toggleSelect(String id) {
    selected.contains(id) ? selected.remove(id) : selected.add(id);
    notifyListeners();
  }

  void clearSelection() {
    selected.clear();
    notifyListeners();
  }

  void selectAll() {
    selected.addAll(items.map((m) => m.id));
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    final ids = selected.toList();
    await _library.deleteMany(ids);
    await _history.deleteProgressBulk(ids);
    clearSelection();
    await load();
  }

  Future<void> toggleFavoriteSelected() async {
    for (final id in selected) {
      final item = items.firstWhere((m) => m.id == id, orElse: () => throw StateError('missing'));
      await _library.setFavorite(id, !item.isFavorite);
    }
    clearSelection();
    await load();
  }

  Future<void> toggleFavorite(String id) async {
    final item = items.firstWhere((m) => m.id == id);
    await _library.setFavorite(id, !item.isFavorite);
    await load();
  }

  Future<void> rename(String id, String title) async {
    await _library.rename(id, title);
    await load();
  }

  Future<void> addSelectedToPlaylist(String playlistId) async {
    await _playlists.addItems(playlistId, selected.toList());
    clearSelection();
  }

  Future<void> updateThumb(String id, String path) => _library.updateThumb(id, path);
}
