import 'dart:math' as math;

import '../../data/models/media_item.dart';
import '../smart/arabic_text_analyzer.dart';
import 'recommendation_engine.dart';

/// Extended explainable reasons produced by [SmartRecommendationEngine].
/// The legacy [ReasonKind] values are reused so old UI keeps working.
enum SmartReason {
  favorite, // existing behavior (map of ReasonKind.favorite)
  unfinished, // in progress
  source, // source affinity
  recent, // played recently
  timeOfDay, // you often watch this around this hour
  becauseYouWatched, // shares keywords with titles you watched
  freshDiscovery, // new item nudging exploration
}

/// Recommendation engine v2 — deterministic, explainable, fully local.
///
/// Signals added on top of the v1 weighted model:
/// 1. **Time-of-day affinity** — learns the user's watching-hour histogram
///    from history and boosts items whose past plays cluster in the current
///    hour bucket (morning / afternoon / evening / night).
/// 2. **Keyword affinity** — extracts Arabic-normalized keywords from
///    watched titles; candidates sharing keywords get "because you watched".
/// 3. **Source diversity** — greedy re-ranking so no source monopolizes the
///    top of the list (max 2 consecutive items from the same source).
///
/// No network, no randomness; [DateTime] injectable for tests.
class SmartRecommendationEngine {
  SmartRecommendationEngine({ArabicTextAnalyzer? analyzer})
      : analyzer = analyzer ?? const ArabicTextAnalyzer();

  final ArabicTextAnalyzer analyzer;

  static const int _maxResults = 12;
  static const int _maxConsecutiveSameSource = 2;

  List<ScoredItem> recommend({
    required List<MediaItem> candidates,
    required Map<String, WatchProgress?> progressByItem,
    required List<MediaItem> history,
    DateTime? now,
    int limit = _maxResults,
  }) {
    final at = now ?? DateTime.now();
    final hour = at.hour;

    // ---- global statistics from history -------------------------------
    final hourBuckets = List<int>.filled(24, 0);
    final keywordWeight = <String, int>{};
    final sourcePlays = <String, int>{};
    var watchedTitles = 0;

    for (final h in history) {
      final last = h.lastPlayedAt;
      if (last != null) {
        hourBuckets[last.hour]++;
        watchedTitles++;
        final src = h.sourceId;
        if (src != null) sourcePlays.update(src, (v) => v + 1, ifAbsent: () => 1);
        for (final kw in analyzer.tokenize(h.title, dropStopwords: true)) {
          if (kw.length >= 3) keywordWeight.update(kw, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }

    // Normalized affinity of the *current* hour bucket (0..1).
    final currentBucketWeight = watchedTitles == 0
        ? 0.0
        : hourBuckets[hour] / watchedTitles;
    final maxKeyword =
        keywordWeight.values.fold<int>(1, math.max);

    // Candidate source counts (for v1 source-affinity parity).
    final candSourceAffinity = <String, double>{};
    for (final item in candidates) {
      final src = item.sourceId ?? 'none';
      candSourceAffinity.update(src, (v) => v + 1, ifAbsent: () => 1);
    }
    final maxCandPlays =
        candSourceAffinity.values.fold<double>(1, math.max);

    final scored = <ScoredItem>[];
    final scoredReasons = <ScoredItem, List<SmartReason>>{};

    for (final item in candidates) {
      final progress = progressByItem[item.id];
      final ratio = progress?.ratio() ?? 0;
      var score = 0.0;
      final reasons = <SmartReason>[];

      if (item.isFavorite) {
        score += 40;
        reasons.add(SmartReason.favorite);
      }
      if (progress != null && !progress.completed && ratio > 0.05 && ratio < 0.9) {
        score += 55 * (1 - ratio * 0.5);
        reasons.add(SmartReason.unfinished);
      }

      final affinity = (candSourceAffinity[item.sourceId ?? 'none'] ?? 0) / maxCandPlays;
      if (item.sourceId != null && affinity > 0) {
        score += 20 * affinity;
        if (affinity > 0.5) reasons.add(SmartReason.source);
      }

      final last = item.lastPlayedAt;
      if (last != null) {
        final days = at.difference(last).inDays.clamp(0, 60);
        final decay = math.exp(-days / 7.0);
        score += 35 * decay;
        if (days <= 3) reasons.add(SmartReason.recent);

        // --- time-of-day affinity -------------------------------------
        if (hourBuckets[last.hour] > 0 &&
            last.hour == hour &&
            currentBucketWeight >= 0.15) {
          score += 15 + 10 * currentBucketWeight;
          reasons.add(SmartReason.timeOfDay);
        }
      } else {
        score += 12; // exploration nudge
        reasons.add(SmartReason.freshDiscovery);
      }

      // --- keyword affinity ("because you watched") -------------------
      var shared = 0;
      for (final h in history) {
        if (h.id == item.id) continue;
        for (final kw in analyzer.sharedKeywords(h.title, item.title)) {
          shared += keywordWeight[kw] ?? 1;
        }
      }
      if (shared > 0) {
        final kwBoost = 12 * math.min(1.0, shared / (3.0 * maxKeyword));
        score += kwBoost;
        if (kwBoost >= 6) reasons.add(SmartReason.becauseYouWatched);
      }

      if (progress?.completed ?? false) score -= 45;
      if (last != null && at.difference(last).inDays > 30) score -= 20;

      final si = ScoredItem(item: item, score: score, reasons: const []);
      scored.add(si);
      scoredReasons[si] = reasons;
    }

    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.item.id.compareTo(b.item.id);
    });

    final diversified = diversify(scored, maxConsecutive: _maxConsecutiveSameSource);
    final limited = diversified.take(limit).toList();

    // Map back to the legacy ReasonKind list for the existing UI chips,
    // preserving the first (strongest) smart reason.
    return [
      for (final si in limited)
        ScoredItem(
          item: si.item,
          score: si.score,
          reasons: _toLegacyKinds(scoredReasons[si] ?? const []),
        ),
    ];
  }

  /// Greedy pass that pulls an item from a different source when
  /// [maxConsecutive] same-source items would sit together. Items that
  /// cannot be re-placed keep their original relative order — the
  /// transformation is stable and deterministic.
  List<ScoredItem> diversify(List<ScoredItem> input, {int maxConsecutive = 2}) {
    if (input.length < maxConsecutive + 1) return List.of(input);

    final remaining = List.of(input);
    final result = <ScoredItem>[];
    var runSource = <String?>{};
    var runLen = 0;

    while (remaining.isNotEmpty) {
      var picked = -1;
      for (var i = 0; i < remaining.length; i++) {
        final src = remaining[i].item.sourceId;
        if (runLen >= maxConsecutive && runSource.contains(src)) continue;
        picked = i;
        break;
      }
      if (picked == -1) picked = 0; // everyone conflicts; keep best as-is

      final chosen = remaining.removeAt(picked);
      final src = chosen.item.sourceId;
      if (runLen > 0 && runSource.contains(src)) {
        runLen++;
      } else {
        runLen = 1;
        runSource = {src};
      }
      result.add(chosen);
    }
    return result;
  }

  List<ReasonKind> _toLegacyKinds(List<SmartReason> smart) {
    final out = <ReasonKind>[];
    for (final r in smart) {
      switch (r) {
        case SmartReason.favorite:
          out.add(ReasonKind.favorite);
        case SmartReason.unfinished:
          out.add(ReasonKind.unfinished);
        case SmartReason.source:
          out.add(ReasonKind.source);
        case SmartReason.recent:
        case SmartReason.timeOfDay:
        case SmartReason.becauseYouWatched:
          out.add(ReasonKind.recent);
        case SmartReason.freshDiscovery:
          break;
      }
    }
    if (out.isEmpty) out.add(ReasonKind.recent);
    return out;
  }
}
