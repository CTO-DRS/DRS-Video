import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/services/smart/arabic_text_analyzer.dart';
import 'package:drs_video/services/smart/smart_search_engine.dart';
import 'package:drs_video/services/smart/watch_stats_engine.dart';

void main() {
  group('ArabicTextAnalyzer', () {
    const a = ArabicTextAnalyzer();

    test('normalizes diacritics, hamza forms, taa marbuta and alif maqsura', () {
      expect(a.normalize('مُحَمَّد'), 'محمد');
      expect(a.normalize('أحْمَد'), 'احمد');
      expect(a.normalize('إبراهيم'), 'ابراهيم');
      expect(a.normalize('مدرسة'), 'مدرسه');
      expect(a.normalize('مستشفى'), 'مستشفي');
      expect(a.normalize('سُئِل'), 'سيل'); // ئ → ي
      expect(a.normalize('بَرُوقَة'), 'بروقه');
      expect(a.normalize('ـكِتابـ'), 'كتاب'); // tatweel stripped
    });

    test('normalizes latin case and strips punctuation', () {
      expect(a.normalize('Hello, World!'), 'hello world');
      expect(a.normalize('  multiple   spaces '), 'multiple spaces');
    });

    test('normalize is idempotent', () {
      const src = 'مُدَرِّسَةٌ';
      expect(a.normalize(a.normalize(src)), a.normalize(src));
    });

    test('similarity: identical after normalization = 1, unrelated low', () {
      expect(a.similarity('مُحَمَّد', 'محمد'), 1.0);
      expect(a.similarity('The Matrix', 'the  matrix'), greaterThan(0.95));
      expect(a.similarity('كتاب', 'سيارة'), lessThan(0.3));
    });

    test('similarity: small typo stays high, opposite text low', () {
      // one-letter typo in a 5-letter word
      expect(a.similarity('inception', 'inceptian'), greaterThan(0.75));
      expect(a.similarity('الاسد الملك', 'الاسد المنك'), greaterThan(0.7));
    });

    test('tokenize drops stopwords, single letters and the article', () {
      final t = a.tokenize('فيلم المغامرة في الغابة', dropStopwords: true);
      expect(t, containsAll(['فيلم', 'مغامره', 'غابه']));
      expect(t, isNot(contains('في')));
      final single = a.tokenize('ا ب ج');
      expect(single, isEmpty);
    });

    test('sharedKeywords finds intersection after normalization', () {
      final shared = a.sharedKeywords('فيلم المُغامرة الكبير', 'مغامرة في الغابة');
      expect(shared, contains('مغامره'));
      expect(shared, isNot(contains('في')));
    });

    test('trigrams produce padded set', () {
      final g = a.trigrams('ab');
      expect(g, isNotEmpty); // padding ensures short inputs still gram
      expect(a.trigrams(''), isEmpty);
    });
  });

  group('SmartSearchEngine', () {
    late List<MediaItem> pool;
    final now = DateTime(2026, 9, 27, 12);

    MediaItem item(String id, String title,
        {int plays = 0, bool fav = false, String? source}) {
      final m = MediaItem(id: id, title: title, uri: 'https://x/$id', type: MediaItemType.network)
        ..playCount = plays
        ..isFavorite = fav;
      m.sourceId = source;
      return m;
    }

    setUp(() {
      pool = [
        item('1', 'فيلم الأسد الملك'),
        item('2', 'مغامرات في الغابة'),
        item('3', 'The Matrix'),
        item('4', 'وثائقية عن الفضاء'),
        item('5', 'الاسد الذهبي', plays: 5),
      ];
    });

    test('exact + prefix rank above substring', () {
      final engine = SmartSearchEngine();
      final exact = engine.search(query: 'فيلم الأسد الملك', candidates: pool, now: now);
      expect(exact.first.kind, MatchKind.exact);
      final prefix = engine.search(query: 'فيلم', candidates: pool, now: now);
      expect(prefix.first.kind, MatchKind.prefix);
      expect(prefix.first.item.id, '1');
    });

    test('diacritics/hamza-insensitive matching', () {
      final engine = SmartSearchEngine();
      final hits = engine.search(query: 'الأسد', candidates: pool, now: now);
      expect(hits.map((h) => h.item.id), containsAll(['1', '5']));
    });

    test('typo tolerance via fuzzy path (Arabic typo)', () {
      final engine = SmartSearchEngine();
      final hits = engine.search(query: 'الاسد الملوك', candidates: pool, now: now);
      // 'الملوك' vs 'الملك' — one-letter typo still matches
      expect(hits.map((h) => h.item.id), contains('1'));
    });

    test('popularity boost reorders otherwise-similar matches', () {
      final engine = SmartSearchEngine();
      final hits = engine.search(query: 'الاسد', candidates: pool, now: now);
      // item 5 has playCount 5 → should outrank item 1 (both prefix-ish)
      expect(hits.first.item.id, '5');
    });

    test('multi-token query requires all tokens (tokenAll)', () {
      final engine = SmartSearchEngine();
      final hits = engine.search(query: 'مغامرات الغابة', candidates: pool, now: now);
      expect(hits.first.item.id, '2');
    });

    test('no match returns empty and didYouMean proposes closest', () {
      final engine = SmartSearchEngine();
      final none = engine.search(query: 'zzzzzz', candidates: pool, now: now);
      expect(none, isEmpty);
      expect(engine.didYouMean('الاسدالملوك', pool), isNotNull);
      expect(engine.didYouMean('zzzzzz', pool), isNull);
      expect(engine.didYouMean('ab', pool), isNull); // too short
    });

    test('empty query returns empty, limit respected', () {
      final engine = SmartSearchEngine();
      expect(engine.search(query: '  ', candidates: pool, now: now), isEmpty);
      final hits = engine.search(query: 'ا', candidates: pool, now: now, limit: 2);
      expect(hits.length, lessThanOrEqualTo(2));
    });

    test('recency boost decides between equal-strength matches', () {
      final a = item('r1', 'رحلة العمر');
      final b = item('r2', 'رحلة العمر');
      b.lastPlayedAt = DateTime(2026, 9, 26);
      final engine = SmartSearchEngine();
      final hits = engine.search(query: 'رحلة العمر', candidates: [a, b], now: now);
      // identical titles (both exact) — yesterday's play ranks first
      expect(hits.first.item.id, 'r2');
    });
  });

  group('WatchStatsEngine', () {
    test('computes totals, streaks, peak hour, weekday buckets and interests', () {
      final now = DateTime(2026, 9, 27, 15); // Sunday
      MediaItem watched(String id, String title, DateTime at, {bool completed = false, int posMs = 0}) {
        final m = MediaItem(
          id: id,
          title: title,
          uri: 'https://x/$id',
          type: MediaItemType.local,
          durationMs: 600000,
          lastPlayedAt: at,
        );
        return m;
      }

      final lib = [
        watched('a', 'فيلم كرة القدم', DateTime(2026, 9, 26, 21)), // yesterday
        watched('b', 'مباراة كرة القدم', DateTime(2026, 9, 26, 21)),
        watched('c', 'وثائقي الفضاء', DateTime(2026, 9, 27, 10), completed: true),
        watched('d', 'أفضل مهارات كرة', DateTime(2026, 9, 25, 20)),
      ];
      final progress = {
        'a': WatchProgress(
            itemId: 'a', positionMs: 300000, durationMs: 600000, updatedAt: now),
        'b': WatchProgress(
            itemId: 'b', positionMs: 120000, durationMs: 600000, updatedAt: now),
        'c': WatchProgress(
            itemId: 'c',
            positionMs: 600000,
            durationMs: 600000,
            completed: true,
            updatedAt: now),
      };

      final stats = WatchStatsEngine().compute(
        library: lib,
        progressByItem: progress,
        now: now,
      );

      expect(stats.watchedCount, 4);
      expect(stats.completedCount, 1);
      // a: 300s + b: 120s + c full: 600s + d full (no progress) 600s
      expect(stats.totalWatchMs, 1620000);
      expect(stats.currentStreakDays, 3); // 25 + 26 + 27 (today)
      expect(stats.bestStreakDays, 3);
      expect(stats.peakHour, 21); // two plays at 21:00 vs one at 10:00
      expect(stats.activityByWeekday.length, 7);
      expect(stats.topInterests.first, 'كره'); // appears twice
      expect(stats.dayBuckets.length, 14);
      expect(stats.dayBuckets.last, greaterThan(0)); // today has activity
    });

    test('empty library yields zeroed stats with null peak', () {
      final stats = WatchStatsEngine().compute(
        library: const [],
        progressByItem: const {},
        now: DateTime(2026, 9, 27),
      );
      expect(stats.watchedCount, 0);
      expect(stats.totalWatchMs, 0);
      expect(stats.peakHour, isNull);
      expect(stats.currentStreakDays, 0);
    });
  });
}
