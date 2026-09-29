import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/services/downloader/chunked_download_engine.dart';

void main() {
  group('planSegments', () {
    test('tiles [0,total) exactly — no gaps, no overlaps', () {
      for (final total in [1, 2, 3, 5, 1024, 1048577, 10 * 1048576 + 7]) {
        for (final max in [1, 2, 3, 4]) {
          final segs = planSegments(total, max);
          expect(segs, isNotEmpty, reason: 'total=$total max=$max');
          var cursor = 0;
          for (final s in segs) {
            expect(s.start, cursor);
            expect(s.endInclusive, lessThan(total));
            expect(s.length, greaterThan(0));
            cursor = s.endInclusive + 1;
          }
          expect(cursor, total);
          expect(segs.length, lessThanOrEqualTo(max));
        }
      }
    });

    test('uneven totals distribute the remainder across first segments', () {
      final segs = planSegments(10, 4); // 10 = 3+3+2+2
      expect(segs.map((s) => s.length).toList(), [3, 3, 2, 2]);
    });

    test('count clamped to span size (no empty segments)', () {
      final segs = planSegments(2, 4);
      expect(segs.length, 2);
      expect(segs.every((s) => s.length == 1), isTrue);
    });

    test('seedOffset confines segments to [seed, total)', () {
      final segs = planSegments(100, 4, seedOffset: 40);
      expect(segs.first.start, 40);
      var cursor = 40;
      for (final s in segs) {
        expect(s.start, cursor);
        cursor = s.endInclusive + 1;
      }
      expect(cursor, 100);
    });

    test('empty when fully seeded or non-positive total', () {
      expect(planSegments(0, 4), isEmpty);
      expect(planSegments(-5, 4), isEmpty);
      expect(planSegments(100, 4, seedOffset: 100), isEmpty);
      expect(planSegments(100, 4, seedOffset: 150), isEmpty);
    });
  });

  group('segmentCountFor', () {
    test('2 segments below 16 MiB, up to 4 above', () {
      expect(segmentCountFor(5 * 1048576), 2);
      expect(segmentCountFor(15 * 1048576), 2);
      expect(segmentCountFor(64 * 1048576), 4);
    });

    test('tight storage keeps 2 segments (rename needs no extra space)', () {
      expect(segmentCountFor(64 * 1048576, freeBytes: 65 * 1048576), 2);
      expect(
          segmentCountFor(64 * 1048576, freeBytes: 128 * 1048576), 4);
      expect(segmentCountFor(64 * 1048576), 4, reason: 'unknown free = assume ok');
    });
  });

  group('chunkWindowEnd', () {
    test('clamps to segment end', () {
      expect(chunkWindowEnd(0, 999, 1024), 999);
      expect(chunkWindowEnd(0, 2047, 1024), 1023);
      expect(chunkWindowEnd(1024, 2047, 1024), 2047);
    });
  });

  group('engineEligible', () {
    test('only known sizes ≥ 4 MiB', () {
      expect(engineEligible(null), isFalse);
      expect(engineEligible(0), isFalse);
      expect(engineEligible(4 * 1048576 - 1), isFalse);
      expect(engineEligible(4 * 1048576), isTrue);
      expect(engineEligible(50 * 1048576), isTrue);
    });
  });

  group('percentOf', () {
    test('boundaries and rounding', () {
      expect(percentOf(0, 100), 0);
      expect(percentOf(50, 100), 50);
      expect(percentOf(100, 100), 100);
      expect(percentOf(150, 100), 100);
      expect(percentOf(10, 0), 0);
      expect(percentOf(1, 3), closeTo(33.33, 0.01));
    });
  });

  group('SegmentSpec', () {
    test('cursor/remaining/done math', () {
      final s = SegmentSpec(start: 100, endInclusive: 199);
      expect(s.length, 100);
      expect(s.remaining, 100);
      expect(s.done, isFalse);
      expect(s.absoluteCursor, 100);
      s.received = 40;
      expect(s.absoluteCursor, 140);
      expect(s.remaining, 60);
      s.received = 100;
      expect(s.done, isTrue);
      expect(s.remaining, 0);
    });
  });

  group('EngineState sidecar', () {
    test('encode → decode round trip keeps layout and watermarks', () {
      final state = EngineState(
        version: EngineState.kVersion,
        url: 'https://cdn/video.mp4',
        total: 1000,
        segments: [
          SegmentSpec(start: 0, endInclusive: 499, received: 120),
          SegmentSpec(start: 500, endInclusive: 999, received: 0),
        ],
      );
      final restored = EngineState.decode(state.encode(), url: state.url);
      expect(restored, isNotNull);
      expect(restored!.total, 1000);
      expect(restored.url, 'https://cdn/video.mp4');
      expect(restored.segments.length, 2);
      expect(restored.segments[0].received, 120);
      expect(restored.segments[0].endInclusive, 499);
      expect(restored.received, 120);
    });

    test('decode adopts the live url (signed urls refresh)', () {
      final state = EngineState(
        version: EngineState.kVersion,
        url: 'https://old/signed',
        total: 10,
        segments: [SegmentSpec(start: 0, endInclusive: 9)],
      );
      final restored =
          EngineState.decode(state.encode(), url: 'https://new/signed');
      expect(restored!.url, 'https://new/signed');
    });

    test('corrupt json / wrong version / bad layout → null', () {
      expect(EngineState.decode('not json', url: 'u'), isNull);
      expect(EngineState.decode('{"v":2}', url: 'u'), isNull);
      expect(
          EngineState.decode(jsonEncode({
            'v': 1,
            'url': 'u',
            'total': 100,
            'segs': [
              {'s': 0, 'e': 50, 'r': 0},
              {'s': 60, 'e': 99, 'r': 0}, // gap at 51..59
            ],
          }), url: 'u'),
          isNull);
      expect(
          EngineState.decode(jsonEncode({
            'v': 1,
            'url': 'u',
            'total': 100,
            'segs': [
              {'s': 0, 'e': 99, 'r': 200}, // watermark beyond segment
            ],
          }), url: 'u'),
          isNull);
      expect(EngineState.decode('', url: 'u'), isNull);
    });
  });

  group('StallTracker', () {
    test('not stalled before first touch or before the threshold', () {
      final t = StallTracker(stallAfter: const Duration(seconds: 45));
      expect(t.isStalled('a'), isFalse); // never seen
      final t0 = DateTime(2026, 1, 1, 12);
      t.touch('a', now: t0);
      expect(t.isStalled('a', now: t0.add(const Duration(seconds: 44))),
          isFalse);
      expect(t.isStalled('a', now: t0.add(const Duration(seconds: 45))),
          isTrue);
    });

    test('kick escalates after maxKicks and resets the stall clock', () {
      final t = StallTracker(
          stallAfter: const Duration(seconds: 45), maxKicks: 3);
      var now = DateTime(2026, 1, 1, 12);
      t.touch('a', now: now);
      now = now.add(const Duration(seconds: 50));
      expect(t.kick('a', now: now), isFalse); // kick 1
      expect(t.isStalled('a', now: now), isFalse, reason: 'clock reset');
      now = now.add(const Duration(seconds: 50));
      expect(t.kick('a', now: now), isFalse); // kick 2
      now = now.add(const Duration(seconds: 50));
      expect(t.kick('a', now: now), isTrue); // kick 3 → escalate
    });

    test('progress events reset the stall clock', () {
      final t = StallTracker(stallAfter: const Duration(seconds: 45));
      var now = DateTime(2026, 1, 1, 12);
      t.touch('a', now: now);
      now = now.add(const Duration(seconds: 40));
      t.touch('a', now: now); // progress arrived
      now = now.add(const Duration(seconds: 40));
      expect(t.isStalled('a', now: now), isFalse);
      now = now.add(const Duration(seconds: 6));
      expect(t.isStalled('a', now: now), isTrue);
    });

    test('forget clears both clock and kicks', () {
      final t = StallTracker(stallAfter: const Duration(seconds: 45));
      final now = DateTime(2026, 1, 1, 12);
      t.touch('a', now: now);
      t.kick('a', now: now.add(const Duration(seconds: 50)));
      t.forget('a');
      expect(t.isStalled('a'), isFalse);
    });
  });

  group('partFileName', () {
    test('stable .partN suffix', () {
      expect(partFileName('/d/video.mp4', 0), '/d/video.mp4.part0');
      expect(partFileName('/d/video.mp4', 3), '/d/video.mp4.part3');
    });
  });
}
