import 'package:flutter/foundation.dart';
import '../core/utils/logger.dart';
import '../data/models/media_item.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repository.dart';

/// Library-wide search with history-backed suggestions and filters.
class LibrarySearchController extends ChangeNotifier {
  LibrarySearchController({
    required LibraryRepository library,
    required HistoryRepository history,
  })  : _library = library,
        _history = history;

  final LibraryRepository _library;
  final HistoryRepository _history;

  String query = '';
  List<MediaItem> results = [];
  List<String> recentSearches = [];
  List<String> suggestions = [];
  bool searching = false;
  bool submitted = false;

  MediaItemType? typeFilter;
  DurationFilter durationFilter = DurationFilter.any;
  SortBy sort = SortBy.dateAdded;

  Future<void> init() async {
    recentSearches = await _history.recentSearches();
    notifyListeners();
  }

  void onQueryChanged(String q) {
    query = q;
    submitted = false;
    _computeSuggestions();
  }

  void _computeSuggestions() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      suggestions = List.of(recentSearches);
      notifyListeners();
      return;
    }
    // Deterministic suggestions: recent queries + live title matches.
    _library
        .query(LibraryQuery(search: q, limit: 5, sort: SortBy.name))
        .then((matches) {
      final set = <String>{...recentSearches.where((s) => s.toLowerCase().contains(q))};
      set.addAll(matches.map((m) => m.title));
      suggestions = set.take(8).toList();
      notifyListeners();
    }).catchError((e) {
      AppLogger.instance.warning('search', 'suggestions failed: $e');
    });
  }

  Future<void> submit([String? forced]) async {
    final q = (forced ?? query).trim();
    if (q.isEmpty) return;
    query = q;
    submitted = true;
    searching = true;
    notifyListeners();
    try {
      await _history.addSearch(q);
      recentSearches = await _history.recentSearches();
      results = await _library.query(LibraryQuery(
        search: q,
        type: typeFilter,
        durationFilter: durationFilter,
        sort: sort,
      ));
    } catch (e, s) {
      AppLogger.instance.error('search', 'submit failed', e, s);
      results = [];
    } finally {
      searching = false;
      notifyListeners();
    }
  }

  void setTypeFilter(MediaItemType? t) {
    typeFilter = t;
    if (submitted) submit();
  }

  void setDurationFilter(DurationFilter d) {
    durationFilter = d;
    if (submitted) submit();
  }

  void setSort(SortBy s) {
    sort = s;
    if (submitted) submit();
  }

  Future<void> removeRecent(String q) async {
    await _history.removeSearch(q);
    recentSearches = await _history.recentSearches();
    notifyListeners();
  }

  Future<void> clearRecent() async {
    await _history.clearSearches();
    recentSearches = [];
    suggestions = [];
    notifyListeners();
  }
}
