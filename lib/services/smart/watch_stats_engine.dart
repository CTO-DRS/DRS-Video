import '../../data/models/media_item.dart';
import 'arabic_text_analyzer.dart';

/// Aggregated, fully local viewing statistics powering the "نشاطي الذكي"
/// (My Smart Activity) screen. Pure computation over already-loaded data —
/// no SQL, no network, no clocks ([DateTime] injectable).
class WatchStats {
  const WatchStats({
    required this.totalWatchMs,
    required this.watchedCount,
    required this.completedCount,
    required this.currentStreakDays,
    required this.bestStreakDays,
    required this.peakHour,
    required this.activityByHour,
    required this.activityByWeekday,
    required this.topInterests,
    required this.dayBuckets,
  });

  /// Sum of watched time: completed items count their full duration,
  /// in-progress items count their last position.
  final int totalWatchMs;

  final int watchedCount;
  final int completedCount;

  /// Consecutive-day watching streak ending today (or yesterday).
  final int currentStreakDays;
  final int bestStreakDays;

  /// Hour of day (0..23) with most play activity, or null with no history.
  final int? peakHour;

  /// Play counts per hour bucket (0..23).
  final List<int> activityByHour;

  /// Play counts per weekday (index 0 = Monday .. 6 = Sunday).
  final List<int> activityByWeekday;

  /// Top interest keywords derived from watched titles, best first.
  final List<String> topInterests;

  /// Watched-time (ms) per day for the last [14] days, oldest first —
  /// index 13 is today. Days with no activity are zero.
  final List<int> dayBuckets;
}

/// Deterministic statistics engine over the media library + watch history.
class WatchStatsEngine {
  WatchStatsEngine({ArabicTextAnalyzer? analyzer})
      : analyzer = analyzer ?? const ArabicTextAnalyzer();

  final ArabicTextAnalyzer analyzer;

  static const int _windowDays = 14;

  WatchStats compute({
    required List<MediaItem> library,
    required Map<String, WatchProgress?> progressByItem,
    DateTime? now,
    int maxInterests = 6,
  }) {
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);

    final hourBuckets = List<int>.filled(24, 0);
    final weekdayBuckets = List<int>.filled(7, 0);
    final dayMs = List<int>.filled(_windowDays, 0);
    final dayKeys = <String, int>{}; // yyyy-mm-dd -> index into dayMs
    for (var i = 0; i < _windowDays; i++) {
      final d = today.subtract(Duration(days: _windowDays - 1 - i));
      dayKeys['${d.year}-${d.month}-${d.day}'] = i;
    }

    final keywordWeight = <String, int>{};
    var totalMs = 0;
    var watched = 0;
    var completed = 0;
    final activeDays = <DateTime>{};

    for (final item in library) {
      final last = item.lastPlayedAt;
      if (last == null) continue;
      watched++;
      activeDays.add(DateTime(last.year, last.month, last.day));

      final progress = progressByItem[item.id];
      final done = progress?.completed ?? false;
      if (done) completed++;

      // --- watched-time estimation --------------------------------------
      var ms = 0;
      if (progress != null) {
        if (progress.completed && (progress.durationMs ?? item.durationMs ?? 0) > 0) {
          ms = progress.durationMs ?? item.durationMs ?? 0;
        } else {
          ms = progress.positionMs;
        }
      } else if ((item.durationMs ?? 0) > 0) {
        ms = item.durationMs!; // no progress row: assume full watch
      }
      totalMs += ms;

      // --- temporal histograms ------------------------------------------
      hourBuckets[last.hour]++;
      weekdayBuckets[(last.weekday - 1) % 7]++; // Mon=1..Sun=7 → 0..6

      final key = '${last.year}-${last.month}-${last.day}';
      final dayIdx = dayKeys[key];
      if (dayIdx != null) dayMs[dayIdx] += ms;

      // --- interests ------------------------------------------------------
      for (final kw in analyzer.tokenize(item.title, dropStopwords: true)) {
        if (kw.length >= 3) keywordWeight.update(kw, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    // --- streaks ----------------------------------------------------------
    var current = 0;
    var cursor = today;
    if (!activeDays.contains(today) && activeDays.contains(today.subtract(const Duration(days: 1)))) {
      cursor = today.subtract(const Duration(days: 1)); // streak alive if watched yesterday
    }
    while (activeDays.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    var best = 0;
    var run = 0;
    DateTime? prev;
    final sortedDays = activeDays.toList()..sort();
    for (final d in sortedDays) {
      run = (prev != null && d.difference(prev).inDays == 1) ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }

    // --- peak hour / top interests ----------------------------------------
    var peakHour = -1;
    var peakVal = 0;
    for (var h = 0; h < 24; h++) {
      if (hourBuckets[h] > peakVal) {
        peakVal = hourBuckets[h];
        peakHour = h;
      }
    }

    final interests = keywordWeight.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return a.key.compareTo(b.key); // stable alphabetical tie-break
      });

    return WatchStats(
      totalWatchMs: totalMs,
      watchedCount: watched,
      completedCount: completed,
      currentStreakDays: current,
      bestStreakDays: best,
      peakHour: peakVal == 0 ? null : peakHour,
      activityByHour: hourBuckets,
      activityByWeekday: weekdayBuckets,
      topInterests: interests.take(maxInterests).map((e) => e.key).toList(),
      dayBuckets: dayMs,
    );
  }
}
