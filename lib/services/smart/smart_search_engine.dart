import 'dart:math' as math;

import '../../data/models/media_item.dart';
import 'arabic_text_analyzer.dart';

/// Why a candidate matched — drives the (future) match badge and ranking
/// explanation. Values are ordered by descending strength.
enum MatchKind { exact, prefix, substring, tokenAll, fuzzy }

class SmartSearchHit {
  const SmartSearchHit({
    required this.item,
    required this.score,
    required this.kind,
    this.matchedVia,
  });

  final MediaItem item;

  /// Combined multi-signal score (higher is better).
  final double score;

  /// Strongest match signal found.
  final MatchKind kind;

  /// Free-form hint, e.g. the keyword that produced a fuzzy match.
  final String? matchedVia;
}

/// Deterministic, typo-tolerant library search over an in-memory candidate
/// list. Complements the SQL LIKE path in [LibraryRepository]:
///
/// - Arabic-aware normalization (diacritics, hamza forms, ة/ى, tatweel)
/// - tiered signals: exact > prefix > substring > all-tokens > fuzzy
/// - popularity & recency boosts re-rank equally-strong matches
/// - `didYouMean` proposes the closest title when a query yields nothing
///
/// Pure functions: no IO, no clock access — [DateTime] is injectable.
class SmartSearchEngine {
  SmartSearchEngine({ArabicTextAnalyzer? analyzer})
      : analyzer = analyzer ?? const ArabicTextAnalyzer();

  final ArabicTextAnalyzer analyzer;

  static const double _fuzzyThreshold = 0.55;

  /// Search [candidates]. Cheap enough for a few thousand items (<10ms);
  /// the controller passes the already-loaded library pool.
  List<SmartSearchHit> search({
    required String query,
    required List<MediaItem> candidates,
    DateTime? now,
    int limit = 30,
  }) {
    final q = analyzer.normalize(query);
    if (q.isEmpty) return const [];
    final at = now ?? DateTime.now();
    final qTokens = q.split(' ').toSet();

    final hits = <SmartSearchHit>[];
    for (final item in candidates) {
      final title = analyzer.normalize(item.title);
      if (title.isEmpty) continue;

      var score = 0.0;
      var kind = MatchKind.fuzzy;
      String? via;

      if (title == q) {
        score += 100;
        kind = MatchKind.exact;
      } else if (title.startsWith(q)) {
        score += 80;
        kind = MatchKind.prefix;
      } else if (title.contains(q)) {
        score += 60;
        kind = MatchKind.substring;
      }

      // Token coverage: every query token appears in the title.
      final tTokens = title.split('').isEmpty
          ? <String>{}
          : title.split(' ').toSet();
      if (qTokens.length > 1 && qTokens.every(tTokens.contains)) {
        if (score < 55) {
          score += 55;
          kind = kind == MatchKind.fuzzy ? MatchKind.tokenAll : kind;
        } else {
          score += 10; // strong + tokenized, small extra
        }
      }

      // Fuzzy path: full-title similarity, then best token similarity.
      if (score == 0) {
        final full = analyzer.similarity(item.title, query);
        var bestSim = full;
        var bestVia = item.title;
        if (full < _fuzzyThreshold) {
          for (final t in tTokens) {
            if (t.length < 4) continue;
            final s = analyzer.similarity(t, q);
            if (s > bestSim) {
              bestSim = s;
              bestVia = t;
            }
          }
        }
        if (bestSim >= _fuzzyThreshold) {
          score += 45 * bestSim;
          kind = MatchKind.fuzzy;
          via = bestVia;
        } else {
          continue; // no signal at all — not a hit
        }
      }

      // Popularity: log2 scaling keeps 1 play > 0 and 256 plays ≈ +16.
      if (item.playCount > 0) {
        score += 2 * (math.log(item.playCount) / math.ln2);
      }
      if (item.isFavorite) score += 8;

      // Recency: last week gets a gentle bump (decay 7 days).
      final last = item.lastPlayedAt;
      if (last != null) {
        final days = at.difference(last).inDays.clamp(0, 30);
        score += 6 * math.exp(-days / 7.0);
      }

      hits.add(SmartSearchHit(item: item, score: score, kind: kind, matchedVia: via));
    }

    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.item.id.compareTo(b.item.id); // stable tie-break
    });
    return hits.take(limit).toList();
  }

  /// "Did you mean …" — the closest title above the threshold, or null.
  /// Only meaningful when the plain query produced zero results.
  String? didYouMean(String query, List<MediaItem> candidates) {
    final q = analyzer.normalize(query);
    if (q.length < 3 || candidates.isEmpty) return null;

    String? best;
    var bestScore = 0.0;
    for (final item in candidates) {
      final title = analyzer.normalize(item.title);
      if (title.isEmpty || title == q) continue;
      final sim = analyzer.similarity(item.title, query);
      if (sim > bestScore) {
        bestScore = sim;
        best = item.title;
      }
    }
    return bestScore >= _fuzzyThreshold ? best : null;
  }
}
