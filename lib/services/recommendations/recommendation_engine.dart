import 'dart:math' as math;
import '../../data/models/media_item.dart';

/// Deterministic, explainable recommendation engine (no AI, no network).
///
/// Score model (all local data):
///   + favorites boost            +40
///   + unfinished (watch ratio 5%..90%)   +55 * ratio weight
///   + source affinity (log of plays)     +30 * affinity
///   + recency of last play               +35 * decay(7 days)
///   - already completed                  -45
///   - stale (not played in 30 days)      -20
class RecommendationEngine {
  const RecommendationEngine();

  static const int _maxResults = 12;

  List<ScoredItem> recommend({
    required List<MediaItem> candidates,
    required Map<String, WatchProgress?> progressByItem,
    required List<WatchProgress> recentHistory,
    int limit = _maxResults,
  }) {
    final sourceAffinity = <String, double>{};
    for (final item in candidates) {
      final src = item.sourceId ?? 'none';
      sourceAffinity.update(src, (v) => v + 1, ifAbsent: () => 1);
    }
    final maxSourcePlays =
        sourceAffinity.values.fold<double>(1, math.max);

    final now = DateTime.now();
    final scored = <ScoredItem>[];

    for (final item in candidates) {
      final progress = progressByItem[item.id];
      final ratio = progress?.ratio() ?? 0;
      var score = 0.0;
      final reasons = <ReasonKind>[];

      if (item.isFavorite) {
        score += 40;
        reasons.add(ReasonKind.favorite);
      }
      if (progress != null &&
          !progress.completed &&
          ratio > 0.05 &&
          ratio < 0.9) {
        score += 55 * (1 - ratio * 0.5);
        reasons.add(ReasonKind.unfinished);
      }
      final affinity = (sourceAffinity[item.sourceId ?? 'none'] ?? 0) / maxSourcePlays;
      if (item.sourceId != null && affinity > 0) {
        score += 30 * affinity;
        if (affinity > 0.5) reasons.add(ReasonKind.source);
      }
      final last = item.lastPlayedAt;
      if (last != null) {
        final days = now.difference(last).inDays.clamp(0, 60);
        final decay = math.exp(-days / 7.0);
        score += 35 * decay;
        if (days <= 3) reasons.add(ReasonKind.recent);
      } else {
        score += 12; // nudge to try new items
      }
      if (progress?.completed ?? false) score -= 45;
      if (last != null && now.difference(last).inDays > 30) score -= 20;

      scored.add(ScoredItem(item: item, score: score, reasons: reasons));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }
}

enum ReasonKind { favorite, unfinished, source, recent }

class ScoredItem {
  const ScoredItem({
    required this.item,
    required this.score,
    required this.reasons,
  });

  final MediaItem item;
  final double score;
  final List<ReasonKind> reasons;

  ReasonKind get primaryReason =>
      reasons.isEmpty ? ReasonKind.recent : reasons.first;
}
