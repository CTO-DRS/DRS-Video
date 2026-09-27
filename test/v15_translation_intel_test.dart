import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/core/utils/md5.dart';
import 'package:drs_video/services/smart/intel_v3.dart';
import 'package:drs_video/services/subtitles/subtitle_translator.dart';

void main() {
  // ------------------------------------------------------------------
  // TranslationBatcher
  // ------------------------------------------------------------------
  group('v1.14.0 TranslationBatcher', () {
    test('splits by char budget and preserves cue order', () {
      final texts = List.generate(40, (i) => 'cue number ${i * 17}');
      final batches = TranslationBatcher.batch(texts, charBudget: 200);
      expect(batches.isNotEmpty, isTrue);
      // All cues covered exactly once, in order.
      var cue = 0;
      for (final b in batches) {
        expect(b.startCue, cue);
        cue += b.lines.length;
        expect(b.payload.length, lessThanOrEqualTo(260));
      }
      expect(cue, texts.length);
    });

    test('a single line longer than the budget still becomes a batch', () {
      final long = 'x' * 5000;
      final batches = TranslationBatcher.batch([long, 'short']);
      expect(batches.length, 2);
      expect(batches[0].lines.first, long);
      expect(batches[1].lines, ['short']);
    });

    test('internal newlines are flattened so \n stays a cue separator', () {
      final out = TranslationBatcher.flattenLine('hello\r\nworld\nagain');
      expect(out, 'hello world again');
      final batches = TranslationBatcher.batch(['a\nb', 'c']);
      expect(batches.single.payload, 'a b\nc');
    });
  });

  // ------------------------------------------------------------------
  // GtxResponse parsing
  // ------------------------------------------------------------------
  group('v1.14.0 GtxResponse', () {
    test('parses the real gtx shape and joins chunks', () {
      const body =
          '[[["مرحبا","hello",null,null,10],["بالعالم","world",null,null,1]],null,"en",'
          '[["مرحبا"],["بالعالم"]],"en"]';
      final r = GtxResponse.parse(body);
      expect(r.text, 'مرحبابالعالم');
      expect(r.detectedSource, 'en');
    });

    test('throws FormatException on wrong structures', () {
      expect(() => GtxResponse.parse('"just a string"'),
          throwsFormatException);
      expect(() => GtxResponse.parse('[]'), throwsFormatException);
      expect(() => GtxResponse.parse('[null,null,"en"]'),
          throwsFormatException);
    });

    test('mapLines requires exact line count', () {
      expect(GtxResponse.mapLines('سطر أول\nسطر ثانٍ', 2),
          ['سطر أول', 'سطر ثانٍ']);
      expect(GtxResponse.mapLines('مدمج في سطر واحد', 2), isNull);
    });
  });

  // ------------------------------------------------------------------
  // SrtTextOps + cache keys
  // ------------------------------------------------------------------
  group('v1.14.0 SrtTextOps', () {
    const srt = '1\n00:00:01,000 --> 00:00:02,000\nhello world\n\n'
        '2\n00:00:03,000 --> 00:00:04,500\nsecond line one\nsecond line two\n\n'
        '3\n00:00:05,000 --> 00:00:06,000\nbye\n';

    test('extracts only text lines, one flattened entry per block', () {
      final texts = SrtTextOps.textsForTranslation(srt);
      expect(texts, [
        'hello world',
        'second line one second line two',
        'bye',
      ]);
    });

    test('rebuild keeps numbering and timings byte-identical', () {
      final out = SrtTextOps.rebuild(srt, ['مرحبا بالعالم', 'السطر الثاني', 'وداعا']);
      expect(out.contains('00:00:01,000 --> 00:00:02,000'), isTrue);
      expect(out.contains('00:00:03,000 --> 00:00:04,500'), isTrue);
      expect(out.contains('00:00:05,000 --> 00:00:06,000'), isTrue);
      expect(out.contains('مرحبا بالعالم'), isTrue);
      expect(out.contains('1\n'), isTrue);
      expect(out.contains('hello world'), isFalse);
      expect(out.contains('second line one'), isFalse);
    });

    test('cache keys are deterministic and language-scoped', () {
      final k1 = TranslationCacheKeys.fileKey('abc', 'ar');
      final k2 = TranslationCacheKeys.fileKey('abc', 'ar');
      final k3 = TranslationCacheKeys.fileKey('abc', 'en');
      expect(k1, k2);
      expect(k1, isNot(k3));
      expect(k1.startsWith('tr_') && k1.endsWith('.srt'), isTrue);
      // Underlying md5 sanity.
      expect(md5Hex(utf8.encode('abc')), '900150983cd24fb0d6963f7d28e17f72');
    });
  });

  // ------------------------------------------------------------------
  // Zoom / rotation / boost / bookmark nav / video eq
  // ------------------------------------------------------------------
  group('v1.14.0 gesture + picture algorithms', () {
    test('ZoomPanMath clamps zoom and pan to the zoom surplus', () {
      final fit = ZoomPanMath.clampAll(zoom: 0, panX: 0.5, panY: -0.5);
      expect(fit.zoom, 0);
      expect(fit.panX, 0); // nothing to pan at fit size
      final z = ZoomPanMath.clampAll(zoom: 1.0, panX: 99, panY: -99);
      expect(z.zoom, 1.0);
      final bound = ZoomPanMath.panBoundExact(1.0);
      expect(z.panX, bound);
      expect(z.panY, -bound);
      expect(ZoomPanMath.panBoundExact(0), 0);
      // Monotonic + sane.
      expect(ZoomPanMath.panBoundExact(2.0),
          greaterThan(ZoomPanMath.panBoundExact(1.0)));
      expect(ZoomPanMath.panBoundExact(2.0), 1.5);
    });

    test('RotationCycle cycles and clamps', () {
      expect(RotationCycle.next(0), 90);
      expect(RotationCycle.next(90), 180);
      expect(RotationCycle.next(180), 270);
      expect(RotationCycle.next(270), 0);
      expect(RotationCycle.next(77), 90); // unknown → treated as first
      expect(RotationCycle.clamp(95), 90);
    });

    test('LongPressBoost engages only after the delay, once per hold', () {
      final b = LongPressBoost(engageDelayMs: 400);
      b.start(1000);
      expect(b.tick(1200), isFalse); // too early
      expect(b.tick(1399), isFalse);
      expect(b.tick(1400), isTrue); // engages exactly once
      expect(b.tick(1600), isFalse);
      expect(b.end(), isTrue); // restore needed
      expect(b.end(), isFalse); // second end is a no-op
    });

    test('LongPressBoost short hold never engages', () {
      final b = LongPressBoost(engageDelayMs: 400);
      b.start(1000);
      expect(b.tick(1100), isFalse);
      expect(b.end(), isFalse);
    });

    test('BookmarkNav finds nearest with tolerance', () {
      const marks = [10000, 20000, 30000];
      expect(BookmarkNav.next(marks, 5000), 10000);
      expect(BookmarkNav.next(marks, 10000), 20000); // tolerance bounce
      expect(BookmarkNav.next(marks, 29500), 30000);
      expect(BookmarkNav.next(marks, 30000), isNull);
      expect(BookmarkNav.previous(marks, 35000), 30000);
      expect(BookmarkNav.previous(marks, 10000), isNull);
      expect(BookmarkNav.previous(marks, 10001 - 400 - 1), isNull);
      expect(BookmarkNav.previous(marks.reversed.toList(), 25000), 20000);
    });

    test('VideoEq clamps, channels round-trip through JSON', () {
      final eq = const VideoEq()
          .withChannel('brightness', 150)
          .withChannel('contrast', -150)
          .withChannel('hue', 30);
      expect(eq.brightness, 100);
      expect(eq.contrast, -100);
      expect(eq.hue, 30);
      expect(eq.isNeutral, isFalse);
      final restored = VideoEq.decode(eq.encode());
      expect(restored.brightness, 100);
      expect(restored.contrast, -100);
      expect(restored.hue, 30);
      expect(VideoEq.decode('garbage{').isNeutral, isTrue);
      // mpv property names match channel keys (typo guard).
      for (final k in VideoEq.mpvProperty.keys) {
        expect(VideoEq.mpvProperty[k], k);
      }
    });
  });

  // ------------------------------------------------------------------
  // SubtitleTranslator (mock fetcher — no network)
  // ------------------------------------------------------------------
  group('v1.14.0 SubtitleTranslator', () {
    const inputSrt = '1\n00:00:01,000 --> 00:00:02,000\nhello world\n\n'
        '2\n00:00:03,000 --> 00:00:04,000\nsecond cue\n';

    String gtxBody(String translated, String source) {
      final chunk = jsonEncode([translated, '', null, null, 1]);
      return '[[$chunk],null,"$source"]';
    }

    test('translates batched cues in order', () async {
      final t = SubtitleTranslator(fetcherOverride: (uri) async {
        final q = uri.queryParameters['q'] ?? '';
        if (q.contains('\n')) {
          return gtxBody('مرحبا بالعالم\nالمقطع الثاني', 'en');
        }
        return gtxBody('سطر', 'en');
      });
      final res = await t.translateSrt(inputSrt, targetLang: 'ar');
      expect(res.isEmpty, isFalse);
      expect(res.partial, isFalse);
      expect(res.detectedSource, 'en');
      expect(res.translatedCues, 2);
      expect(res.srt.contains('مرحبا بالعالم'), isTrue);
      expect(res.srt.contains('المقطع الثاني'), isTrue);
      expect(res.srt.contains('hello world'), isFalse);
      // Timings survive.
      expect(res.srt.contains('00:00:03,000 --> 00:00:04,000'), isTrue);
    });

    test('falls back to per-line requests when the server merges lines',
        () async {
      var requests = 0;
      final t = SubtitleTranslator(fetcherOverride: (uri) async {
        requests++;
        final q = uri.queryParameters['q'] ?? '';
        if (q.contains('\n')) {
          // Simulate the server merging both lines into one — the caller
          // must detect the mismatch and retry line by line.
          return gtxBody('مدمج في سطر واحد', 'en');
        }
        return gtxBody(q == 'hello world' ? 'مرحبا' : 'ثانياً', 'en');
      });
      final res = await t.translateSrt(inputSrt, targetLang: 'ar');
      expect(res.partial, isFalse);
      expect(res.srt.contains('مرحبا'), isTrue);
      expect(res.srt.contains('ثانياً'), isTrue);
      expect(requests, greaterThanOrEqualTo(3));
    });

    test('skips translation entirely when already in the target language',
        () async {
      final t = SubtitleTranslator(fetcherOverride: (uri) async {
        final q = uri.queryParameters['q'] ?? '';
        return gtxBody(q, 'ar'); // detected == target
      });
      final res = await t.translateSrt(inputSrt, targetLang: 'ar');
      expect(res.alreadyTarget, isTrue);
      expect(res.isEmpty, isTrue);
    });

    test('keeps original text for permanently failing batches (partial)',
        () async {
      final t = SubtitleTranslator(fetcherOverride: (uri) async {
        throw const FormatException('network down');
      });
      final res = await t.translateSrt(inputSrt, targetLang: 'ar');
      expect(res.partial, isTrue);
      expect(res.translatedCues, 0);
      // Original text preserved.
      expect(res.srt.contains('hello world'), isTrue);
    });

    test('translateFile writes the cache file and reports the path',
        () async {
      final dir =
          Directory.systemTemp.createTempSync('drs_tr_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final input = File('${dir.path}/in.srt');
      await input.writeAsString(inputSrt);
      final t = SubtitleTranslator(
        fetcherOverride: (uri) async {
          final q = uri.queryParameters['q'] ?? '';
          return gtxBody('ترجمة: $q', 'en');
        },
        baseDirOverride: () async => '${dir.path}/cache',
      );
      final out = await t.translateFile(input.path, targetLang: 'ar');
      expect(out, isNotNull);
      expect(out!.alreadyTarget, isFalse);
      expect(File(out.srtPath!).existsSync(), isTrue);
      final cached =
          await t.cachedTranslation(input.readAsStringSync(), 'ar');
      expect(cached, out.srtPath);
      // Second call with the same input hits the cache (no fetch needed —
      // override that would fail the test if called).
      final t2 = SubtitleTranslator(
        fetcherOverride: (uri) async => fail('cache miss'),
        baseDirOverride: () async => '${dir.path}/cache',
      );
      final out2 = await t2.translateFile(input.path, targetLang: 'ar');
      expect(out2!.srtPath, out.srtPath);
    });

    test('refuses garbage input before spending network', () async {
      final t = SubtitleTranslator(
          fetcherOverride: (uri) async => fail('must not be called'));
      expect(
        () => t.translateSrt('this is not a subtitle', targetLang: 'ar'),
        throwsFormatException,
      );
    });
  });

  // ------------------------------------------------------------------
  // Version
  // ------------------------------------------------------------------
  test('v1.14.0 version + self-update constants intact', () {
    expect(AppConstants.appVersion, '1.14.2');
    expect(AppConstants.githubRepo, contains('/'));
  });
}
