import 'package:flutter/foundation.dart';
import '../core/utils/logger.dart';
import '../data/models/media_item.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repository.dart';
import '../services/smart/arabic_text_analyzer.dart';
import '../services/smart/smart_search_engine.dart';

/// Library-wide search with history-backed suggestions and filters.
///
/// v1.5.0: results are ranked by [SmartSearchEngine] — Arabic-normalized,
/// typo-tolerant, multi-signal scoring — over the in-memory library pool.
/// The SQL LIKE path remains as an automatic fallback if the smart pass
/// throws (never leave the user without results when avoidable).
class LibrarySearchController extends ChangeNotifier {
  LibrarySearchController({
    required LibraryRepository library,
    required HistoryRepository history,
    SmartSearchEngine? smartEngine,
  })  : _library = library,
        _history = history,
        smart = smartEngine ?? SmartSearchEngine();

  final LibraryRepository _library;
  final HistoryRepository _history;

  /// Exposed so screens can reuse normalization (e.g. highlight rendering).
  final SmartSearchEngine smart;
  ArabicTextAnalyzer get analyzer => smart.analyzer;

  String query = '';
  List<MediaItem> results = [];
  List<String> recentSearches = [];
  List<String> suggestions = [];
  bool searching = false;
  bool submitted = false;

  /// Non-null when the last query produced nothing but a close title
  /// exists — the UI shows a "هل تقصد؟" chip.
  String? didYouMean;

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
    didYouMean = null;
    notifyListeners();
    try {
      await _history.addSearch(q);
      recentSearches = await _history.recentSearches();

      // Smart path: score the whole pool in memory (cheap for a few
      // thousand rows), then apply the active filters in Dart.
      final pool = await _library.query(const LibraryQuery(limit: 5000));
      final hits = smart.search(query: q, candidates: pool);
      var items = hits.map((h) => h.item).toList();

      if (typeFilter != null) {
        items = items.where((m) => m.type == typeFilter).toList();
      }
      if (durationFilter != DurationFilter.any) {
        items = items.where((m) {
          final d = m.durationMs;
          if (d == null) return false;
          return switch (durationFilter) {
            DurationFilter.short => d < 300000,
            DurationFilter.medium => d >= 300000 && d <= 1200000,
            DurationFilter.long => d > 1200000 && d <= 3600000,
            DurationFilter.veryLong => d > 3600000,
            DurationFilter.any => true,
          };
        }).toList();
      }
      results = items;

      // Nothing found → try the tolerant SQL fallback once, then propose
      // the closest title ("did you mean").
      if (results.isEmpty) {
        final fallback = await _library.query(LibraryQuery(search: q));
        if (fallback.isNotEmpty) {
          results = fallback;
        } else {
          didYouMean = smart.didYouMean(q, pool);
        }
      }
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
