import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/services/smart/intel_v2.dart';
import 'package:drs_video/services/update/update_service.dart';

/// v1.12.0 — the "everything" release: in-app self-update (GitHub),
/// auto-subtitles pipeline, sibling subtitle matching, bookmarks, frame
/// capture, adaptive seek, intro-skip memory, battery/data savers and
/// the filename metadata parser. Every pure algorithm is covered here.
void main() {
  group('v1.12.0 VersionCompare (self-update)', () {
    test('strictly-newer semantics', () {
      expect(VersionCompare.isNewer('1.14.0', '1.12.0'), isTrue);
      expect(VersionCompare.isNewer('1.12.1', '1.12.0'), isTrue);
      expect(VersionCompare.isNewer('2.0.0', '1.99.99'), isTrue);
      expect(VersionCompare.isNewer('1.12.0', '1.12.0'), isFalse);
      expect(VersionCompare.isNewer('1.11.9', '1.12.0'), isFalse);
      // Tags / build suffixes tolerated.
      expect(VersionCompare.isNewer('v1.14.0', '1.12.0'), isTrue);
      expect(VersionCompare.isNewer('1.14.0+21', '1.12.0+20'), isTrue);
      expect(VersionCompare.isNewer('1.12.0-beta', '1.12.0'), isFalse);
      // Two-part versions normalize.
      expect(VersionCompare.isNewer('1.13', '1.12.0'), isTrue);
      expect(VersionCompare.isNewer('', '1.12.0'), isFalse);
    });
  });

  group('v1.12.0 md5Hex (update integrity)', () {
    test('matches published RFC-1321 vectors', () {
      expect(md5Hex(utf8.encode('')), 'd41d8cd98f00b204e9800998ecf8427e');
      expect(md5Hex(utf8.encode('a')), '0cc175b9c0f1b6a831c399e269772661');
      expect(md5Hex(utf8.encode('abc')), '900150983cd24fb0d6963f7d28e17f72');
      expect(
        md5Hex(utf8.encode('The quick brown fox jumps over the lazy dog')),
        '9e107d9d372bb6826bd81d3542a419d6',
      );
      // Binary-ish payload longer than one block (multi-chunk path).
      final big = List<int>.generate(5000, (i) => i % 251);
      // Golden value captured with Python hashlib for the same bytes.
      expect(md5Hex(big), _goldenBigMd5);
    });

    test('md5 asset line parsing works via regex contract', () {
      final line = 'ede89e2322b3a98b93710e26ae80116d  DRS-Video-v1.11.0.apk';
      expect(
        RegExp(r'([a-fA-F0-9]{32})').firstMatch(line)?.group(1),
        'ede89e2322b3a98b93710e26ae80116d',
      );
    });
  });

  group('v1.12.0 FilenameMeta', () {
    test('parses release-style names', () {
      final a = FilenameMeta.parse('The.Matrix.1999.1080p.BluRay.x264-GROUP');
      expect(a.title, 'The Matrix');
      expect(a.year, 1999);
      expect(a.quality, '1080p');
      expect(a.source?.toLowerCase(), 'bluray');
      expect(a.codec?.toLowerCase(), 'x264');

      final b = FilenameMeta.parse('Breaking.Bad.S01E02.720p.WEB-DL');
      expect(b.title, 'Breaking Bad');
      expect(b.season, 1);
      expect(b.episode, 2);
      expect(b.quality, '720p');
      expect(b.tagLine, 'S01E02 · 720p');

      final c = FilenameMeta.parse('Nature.Doc.2x05.2160p.HEVC');
      expect(c.season, 2);
      expect(c.episode, 5);
      expect(c.quality, '2160p');
    });

    test('keeps Arabic titles intact and strips junk tokens', () {
      final a = FilenameMeta.parse('قصة الحضارة 2018 1080p WEB x265-GROUP');
      expect(a.title, contains('قصة الحضارة'));
      expect(a.year, 2018);
      expect(a.quality, '1080p');

      final b = FilenameMeta.parse('My.Home.Video');
      expect(b.title, 'My Home Video');
      // Plain name stays usable.
      expect(FilenameMeta.displayTitle('/sdcard/Movies/Inception.2010.mkv'),
          'Inception');
    });
  });

  group('v1.12.0 SiblingSubtitles', () {
    test('prefers exact stem, then language-tagged variants', () {
      const video = '/movies/Breaking.Bad.S01E01.mkv';
      expect(
        SiblingSubtitles.find(video, [
          '/movies/other.srt',
          '/movies/Breaking.Bad.S01E01.ara.srt',
          '/movies/Breaking.Bad.S01E01.srt',
        ]),
        '/movies/Breaking.Bad.S01E01.srt',
      );
      // Arabic-tagged sibling wins over English.
      expect(
        SiblingSubtitles.find(video, [
          '/movies/Breaking.Bad.S01E01.en.srt',
          '/movies/Breaking.Bad.S01E01.ar.srt',
        ]),
        '/movies/Breaking.Bad.S01E01.ar.srt',
      );
      // Same folder different video: token overlap still finds it.
      expect(
        SiblingSubtitles.find('/movies/Inception 2010.mkv',
            ['/movies/Inception.2010.srt']),
        '/movies/Inception.2010.srt',
      );
    });

    test('returns null when nothing plausible exists', () {
      const video = '/movies/Inception.mkv';
      expect(SiblingSubtitles.find(video, []), isNull);
      expect(SiblingSubtitles.find(video, ['/movies/cover.jpg']), isNull);
      expect(
        SiblingSubtitles.find(video, ['/movies/Totally.Different.Show.srt']),
        isNull,
      );
      // Non-subtitle extensions are never picked.
      expect(
        SiblingSubtitles.find(video, ['/movies/Inception.nfo']),
        isNull,
      );
    });
  });

  group('v1.12.0 AdaptiveSeek', () {
    test('longer videos get larger steps within sane bounds', () {
      expect(AdaptiveSeek.stepMs(0), 10000);
      expect(AdaptiveSeek.stepMs(5 * 60000), 10000); // <15 min
      expect(AdaptiveSeek.stepMs(40 * 60000), 15000); // <1 h
      expect(AdaptiveSeek.stepMs(90 * 60000), 20000); // <2 h
      expect(AdaptiveSeek.stepMs(3 * 3600000), 30000); // 3 h
      // Bounds hold for extremes.
      expect(AdaptiveSeek.stepMs(10 * 3600000), lessThanOrEqualTo(60000));
      expect(AdaptiveSeek.stepMs(1000), greaterThanOrEqualTo(5000));
    });
  });

  group('v1.12.0 BatterySaver + DataSaver', () {
    test('audio-only only when low, unplugged and enabled', () {
      expect(
        BatterySaver.shouldAutoAudioOnly(
            enabled: true, levelPercent: 15, plugged: false),
        isTrue,
      );
      expect(
        BatterySaver.shouldAutoAudioOnly(
            enabled: true, levelPercent: 15, plugged: true),
        isFalse,
      );
      expect(
        BatterySaver.shouldAutoAudioOnly(
            enabled: true, levelPercent: 80, plugged: false),
        isFalse,
      );
      expect(
        BatterySaver.shouldAutoAudioOnly(
            enabled: false, levelPercent: 5, plugged: false),
        isFalse,
      );
      // Garbage level never triggers.
      expect(
        BatterySaver.shouldAutoAudioOnly(
            enabled: true, levelPercent: -1, plugged: false),
        isFalse,
      );
    });

    test('data saver lowers but never raises a user cap', () {
      expect(DataSaver.effectiveHlsCap(null, saverOn: false), isNull);
      expect(DataSaver.effectiveHlsCap(null, saverOn: true),
          DataSaver.defaultCapKbps);
      expect(DataSaver.effectiveHlsCap(800, saverOn: true), 800);
      expect(DataSaver.effectiveHlsCap(12000, saverOn: true),
          DataSaver.defaultCapKbps);
      expect(DataSaver.effectiveHlsCap(12000, saverOn: false), 12000);
    });
  });

  group('v1.12.0 IntroSkip', () {
    test('folder key is stable per directory / URL directory', () {
      expect(
        IntroSkip.folderKeyOf('/series/Lost/S01/ep1.mkv'),
        IntroSkip.folderKeyOf('/series/Lost/S01/ep2.mkv'),
      );
      expect(
        IntroSkip.folderKeyOf('/series/Lost/S01/ep1.mkv'),
        isNot(IntroSkip.folderKeyOf('/series/Lost/S02/ep1.mkv')),
      );
      final k1 = IntroSkip.folderKeyOf(
          'https://example.com/playlist/abc/ep1.m3u8');
      final k2 = IntroSkip.folderKeyOf(
          'https://example.com/playlist/abc/ep2.m3u8');
      expect(k1, k2);
    });

    test('skip decision respects user progress', () {
      // Fresh open: jump past the intro.
      expect(
        IntroSkip.startMs(introEndMs: 45000, resumePositionMs: null),
        45000,
      );
      // Resume before the intro end: still skip past it.
      expect(
        IntroSkip.startMs(introEndMs: 45000, resumePositionMs: 12000),
        45000,
      );
      // Resume beyond the intro: user progress wins.
      expect(
        IntroSkip.startMs(introEndMs: 45000, resumePositionMs: 120000),
        isNull,
      );
      // No marker → never skip.
      expect(
        IntroSkip.startMs(introEndMs: null, resumePositionMs: null),
        isNull,
      );
      expect(IntroSkip.startMs(introEndMs: 0, resumePositionMs: null), isNull);
    });
  });

  group('v1.12.0 BookmarkCodec', () {
    test('round-trips sorted and drops garbage', () {
      final list = [
        const VideoBookmark(positionMs: 30000, label: 'goal'),
        const VideoBookmark(positionMs: 5000),
      ];
      final encoded = BookmarkCodec.encode(list);
      final decoded = BookmarkCodec.decode(encoded);
      expect(decoded.length, 2);
      expect(decoded.first.positionMs, 5000);
      expect(decoded.last.label, 'goal');

      expect(BookmarkCodec.decode(''), isEmpty);
      expect(BookmarkCodec.decode('not json'), isEmpty);
      expect(BookmarkCodec.decode('{"a":1}'), isEmpty);
      // Negative positions are dropped.
      final bad = jsonEncode([
        {'ms': -5},
        {'ms': 100, 'label': 'ok'},
      ]);
      final decodedBad = BookmarkCodec.decode(bad);
      expect(decodedBad.length, 1);
      expect(decodedBad.first.positionMs, 100);
      // Idempotent ordering.
      expect(BookmarkCodec.encode(decoded), encoded);
    });
  });

  group('v1.12.0 SrtBuilder (auto-subtitles)', () {
    test('builds deterministic, clamp-safe SRT', () {
      final srt = SrtBuilder.build(const [
        CaptionCue(startMs: 1000, durationMs: 2000, text: 'مرحبا'),
        CaptionCue(startMs: 2500, durationMs: 1500, text: 'بالعالم'), // overlap
        CaptionCue(startMs: 9000, durationMs: 500, text: '  '), // blank
      ]);
      final lines = srt.split('\n');
      expect(lines[0], '1');
      expect(lines[1], '00:00:01,000 --> 00:00:02,500'); // clamped to next start
      expect(lines[2], 'مرحبا');
      // Second cue follows; blank cue dropped so numbering compacts.
      expect(srt, contains('2\n00:00:02,500 --> '));
      expect(srt, isNot(contains('00:00:09')));
    });

    test('handles empty and unordered input', () {
      expect(SrtBuilder.build(const []), '');
      final srt = SrtBuilder.build(const [
        CaptionCue(startMs: 5000, durationMs: 1000, text: 'b'),
        CaptionCue(startMs: 1000, durationMs: 1000, text: 'a'),
      ]);
      expect(srt.indexOf('a'), lessThan(srt.indexOf('b')));
      // Negative start clamps to zero.
      final clamped = SrtBuilder.build(const [
        CaptionCue(startMs: -200, durationMs: 600, text: 'x'),
      ]);
      expect(clamped, contains('00:00:00,000 -->'));
    });
  });

  group('v1.12.0 version bump', () {
    test('app version is 1.12.0', () {
      // Pattern-only here: exact equality with pubspec is guarded centrally
      // by test/v20_version_guard_test.dart (endless-update-prompt fix).
      expect(AppConstants.appVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(AppConstants.githubRepo, 'CTO-DRS/DRS-Video');
    });
  });
}

/// Golden md5 for bytes 0..4999 (i % 251), captured with Python hashlib
/// at development time — pins the multi-block (>64 byte) code path.
const String _goldenBigMd5 = '046b3239eaade30920069f171518d956';
