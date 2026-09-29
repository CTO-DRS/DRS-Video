import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/services/recommendations/recommendation_engine.dart';
import 'package:drs_video/services/recommendations/smart_recommendation_engine.dart';
import 'package:drs_video/services/smart/duplicate_detector.dart';

MediaItem _item(String id, String title, {String? source, DateTime? lastPlayed, int plays = 0}) {
  final m = MediaItem(
    id: id,
    title: title,
    uri: 'https://x/$id',
    type: MediaItemType.network,
    sourceId: source,
    lastPlayedAt: lastPlayed,
  );
  m.playCount = plays;
  return m;
}

void main() {
  group('SmartRecommendationEngine', () {
    test('time-of-day affinity boosts items watched in the current hour', () {
      final now = DateTime(2026, 9, 27, 21); // 21:00
      final a = _item('a', 'فيلم الليل', source: 's1',
          lastPlayed: DateTime(2026, 9, 20, 21)); // played at 21 before
      final b = _item('b', 'فيلم الصباح', source: 's1',
          lastPlayed: DateTime(2026, 9, 20, 8)); // played at 08 before
      // history shows the same items; engine learns hour pattern
      final history = [a, b];

      final engine = SmartRecommendationEngine();
      final scored = engine.recommend(
        candidates: [a, b],
        progressByItem: {a.id: null, b.id: null},
        history: history,
        now: now,
      );

      double scoreOf(String id) => scored.firstWhere((s) => s.item.id == id).score;
      expect(scoreOf('a'), greaterThan(scoreOf('b')));
    });

    test('keyword affinity: "because you watched" for shared keywords', () {
      final now = DateTime(2026, 9, 27, 12);
      final watched1 = _item('w1', 'فيلم المغامرة الكبير',
          lastPlayed: DateTime(2026, 9, 25, 12));
      final watched2 = _item('w2', 'رحلة المغامرة في الصحراء',
          lastPlayed: DateTime(2026, 9, 24, 12));
      final candidateA = _item('a', 'مغامرة جديدة في الصحراء'); // shares مغامره + صحراء
      final candidateB = _item('b', 'طبخ الأكلات الشعبية'); // unrelated

      final engine = SmartRecommendationEngine();
      final scored = engine.recommend(
        candidates: [candidateA, candidateB],
        progressByItem: {},
        history: [watched1, watched2],
        now: now,
      );

      double scoreOf(String id) => scored.firstWhere((s) => s.item.id == id).score;
      expect(scoreOf('a'), greaterThan(scoreOf('b')));
    });

    test('diversify caps consecutive same-source items at 2', () {
      final engine = SmartRecommendationEngine();
      final input = [
        ScoredItem(item: _item('x1', 't1', source: 'x'), score: 100, reasons: const []),
        ScoredItem(item: _item('x2', 't2', source: 'x'), score: 99, reasons: const []),
        ScoredItem(item: _item('x3', 't3', source: 'x'), score: 98, reasons: const []),
        ScoredItem(item: _item('y1', 't4', source: 'y'), score: 97, reasons: const []),
      ];
      final out = engine.diversify(input);
      expect(out.length, input.length);
      // The third 'x' is pushed after 'y' — no window of 3 same-source.
      for (var i = 0; i + 3 <= out.length; i++) {
        final window = out.sublist(i, i + 3);
        expect(window.every((s) => s.item.sourceId == 'x'), isFalse,
            reason: 'window at $i has 3 same-source items');
      }
    });

    test('diversify cannot split a single-source list (kept as-is)', () {
      final engine = SmartRecommendationEngine();
      final input = [
        for (var i = 0; i < 4; i++)
          ScoredItem(item: _item('s$i', 't$i', source: 'same'), score: 100 - i.toDouble(), reasons: const []),
      ];
      final out = engine.diversify(input);
      // No alternative source exists — order must be preserved, never broken.
      expect(out.map((s) => s.item.id).toList(), ['s0', 's1', 's2', 's3']);
    });

    test('diversify keeps relative order of distinct sources', () {
      final engine = SmartRecommendationEngine();
      final input = [
        ScoredItem(item: _item('a', 'a', source: 'x'), score: 30, reasons: const []),
        ScoredItem(item: _item('b', 'b', source: 'y'), score: 20, reasons: const []),
        ScoredItem(item: _item('c', 'c', source: 'z'), score: 10, reasons: const []),
      ];
      final out = engine.diversify(input);
      expect(out.map((s) => s.item.id).toList(), ['a', 'b', 'c']);
    });

    test('legacy reason kinds still populated for UI chips', () {
      final now = DateTime(2026, 9, 27, 12);
      final fav = _item('f', 'المفضل عندي', lastPlayed: DateTime(2026, 9, 26, 12));
      fav.isFavorite = true;

      final engine = SmartRecommendationEngine();
      final scored = engine.recommend(
        candidates: [fav],
        progressByItem: {},
        history: [fav],
        now: now,
      );
      expect(scored.first.reasons, contains(ReasonKind.favorite));
    });
  });

  group('DuplicateDetector', () {
    test('clusters diacritics/hamza variants of the same title', () {
      final detector = DuplicateDetector();
      final items = [
        _item('1', 'فيلم المُغامِرة', )..durationMs = 1000000,
        _item('2', 'فيلم المغامرة')..durationMs = 1000000,
        _item('3', 'وثائقي مختلف تماماً')..durationMs = 500000,
      ];
      final clusters = detector.detect(items);
      expect(clusters.length, 1);
      expect(clusters.first.items.length, 2);
      expect(clusters.first.duplicates.first.id, isNot('1'));
    });

    test('same title but different duration (5%+) is NOT duplicate', () {
      final detector = DuplicateDetector();
      final items = [
        _item('1', 'نفس العنوان')..durationMs = 1000000,
        _item('2', 'نفس العنوان')..durationMs = 1200000,
      ];
      expect(detector.detect(items), isEmpty);
    });

    test('same title + duration, big size gap is NOT duplicate', () {
      final detector = DuplicateDetector();
      final a = _item('1', 'مقطع مكرر محتمل')..durationMs = 1000000;
      a.sizeBytes = 100 * 1024 * 1024;
      final b = _item('2', 'مقطع مكرر محتمل')..durationMs = 1000000;
      b.sizeBytes = 300 * 1024 * 1024;
      expect(detector.detect([a, b]), isEmpty);
    });

    test('transitive merging: A≈B, B≈C gives one cluster of three', () {
      final detector = DuplicateDetector();
      final a = _item('a', 'درس البرمجة الأولى')..durationMs = 600000;
      final b = _item('b', 'درس البرمجة اولى')..durationMs = 602000; // ~same
      final c = _item('c', 'درس البرمجة الأولى!')..durationMs = 604000;
      final clusters = detector.detect([a, b, c]);
      expect(clusters.length, 1);
      expect(clusters.first.items.length, 3);
    });

    test('keep suggestion prefers favorites and higher quality', () {
      final detector = DuplicateDetector();
      final small = _item('lo', 'نسخة قديمة')..durationMs = 600000;
      small.sizeBytes = 50 * 1024 * 1024;
      final fav = _item('hi', 'نسخة قديمة')..durationMs = 600000;
      fav.sizeBytes = 52 * 1024 * 1024;
      fav.isFavorite = true;
      fav.playCount = 3;

      final clusters = detector.detect([small, fav]);
      expect(clusters.length, 1);
      expect(clusters.first.keepId, 'hi');
    });

    test('empty and singleton inputs produce nothing', () {
      final detector = DuplicateDetector();
      expect(detector.detect(const []), isEmpty);
      expect(detector.detect([_item('x', 'واحد')]), isEmpty);
    });
  });
}
