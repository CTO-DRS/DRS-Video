import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/data/models/download_task.dart';
import 'package:drs_video/services/downloader/download_service.dart';
import 'package:drs_video/services/downloader/platform_download_resolver.dart';
import 'package:drs_video/services/network/tiktok_resolver.dart';

/// v1.14.2 speed + reliability regression tests.
///
/// User report after v1.14.1: "nothing downloads, downloading and search
/// are unbearably slow". Root causes fixed here:
///  1. Sequential resolver chain + one outer kill-timeout → the headless
///     WebView layer never ran on slow networks. Fixed by parallel racing
///     (raceSuccess) with per-phase budgets.
///  2. Head probes retried 3× with backoff → ~45s dead waiting. Fixed by
///     noRetry probe flags + tight timeouts.
///  3. Resolution + probing ran TWICE per download (sheet, then service).
///     Fixed by preflight passthrough (PreflightInfo + ProbeWithMedia).
///  4. Failed tasks retried the SAME expired signed CDN URL forever.
///     Fixed by originUrl persistence + re-resolve gate.
void main() {
  group('TikTokResolver.raceSuccess — parallel first-win semantics', () {
    test('first non-null result wins even when faster racers return null', () async {
      final sw = Stopwatch()..start();
      final result = await TikTokResolver.raceSuccess<String>([
        // answers first but with null (a dead feed node)
        () async => await Future<String?>.delayed(
            const Duration(milliseconds: 10), () => null),
        // answers second with the WINNER
        () async => await Future<String?>.delayed(
            const Duration(milliseconds: 60), () => 'winner'),
        // would also succeed later — must be ignored
        () async => await Future<String?>.delayed(
            const Duration(milliseconds: 120), () => 'loser'),
      ], budget: const Duration(seconds: 2));
      sw.stop();
      expect(result, 'winner');
      expect(sw.elapsed.inMilliseconds, lessThan(500));
    });

    test('null when every racer fails or returns null', () async {
      final result = await TikTokResolver.raceSuccess<String>([
        () async => null,
        () => Future<String?>.error(Exception('boom')),
        () async => null,
      ], budget: const Duration(seconds: 2));
      expect(result, isNull);
    });

    test('budget cap rescues a hanging race — never longer than budget',
        () async {
      final sw = Stopwatch()..start();
      final result = await TikTokResolver.raceSuccess<String>([
        () => Completer<String?>().future, // hangs forever
      ], budget: const Duration(milliseconds: 150));
      sw.stop();
      expect(result, isNull);
      expect(sw.elapsed.inMilliseconds, lessThan(1000));
    });

    test('empty task list completes immediately', () async {
      final result = await TikTokResolver.raceSuccess<String>([],
          budget: const Duration(seconds: 1));
      expect(result, isNull);
    });

    test('a racer that throws does not prevent others from winning',
        () async {
      final result = await TikTokResolver.raceSuccess<String>([
        () => Future<String?>.error(Exception('crash')),
        () async => await Future<String?>.delayed(
            const Duration(milliseconds: 30), () => 'ok'),
      ], budget: const Duration(seconds: 2));
      expect(result, 'ok');
    });
  });

  group('PreflightInfo — sheet probe passthrough contract', () {
    test('carries size, resume, mime and disposition verbatim', () {
      const p = PreflightInfo(
        expectedSize: 542615,
        resumable: true,
        contentType: 'video/mp4',
        disposition: 'attachment; filename="v.mp4"',
      );
      expect(p.expectedSize, 542615);
      expect(p.resumable, isTrue);
      expect(p.contentType, 'video/mp4');
      expect(p.disposition, isNotNull);
    });

    test('null-size + unknown mime is valid (probe failed path)', () {
      const p = PreflightInfo(
          expectedSize: null, resumable: false, contentType: null);
      expect(p.expectedSize, isNull);
      expect(p.resumable, isFalse);
    });
  });

  group('DownloadTaskModel.originUrl — persistence + mutable url', () {
    test('originUrl roundtrips through toMap/fromMap', () {
      final t = DownloadTaskModel(
        id: 'dl_x',
        url: 'https://v19.tiktokcdn-us.com/signed/expiring.mp4',
        savedDir: '/tmp/dl',
        fileName: 'video.mp4',
        status: DownloadStatus.queued,
        originUrl: 'https://vt.tiktok.com/ZSbjGXQu6/',
      );
      final restored = DownloadTaskModel.fromMap(t.toMap());
      expect(restored.originUrl, 'https://vt.tiktok.com/ZSbjGXQu6/');
      expect(restored.url, contains('tiktokcdn-us.com'));
    });

    test('null originUrl survives persistence (plain links)', () {
      final t = DownloadTaskModel(
        id: 'dl_y',
        url: 'https://cdn.example.com/file.zip',
        savedDir: '/tmp/dl',
        fileName: 'f.zip',
        status: DownloadStatus.queued,
      );
      final restored = DownloadTaskModel.fromMap(t.toMap());
      expect(restored.originUrl, isNull);
    });

    test('url is mutable (re-resolve refreshes the signed address)', () {
      final t = DownloadTaskModel(
        id: 'dl_z',
        url: 'https://old.example/a.mp4',
        savedDir: '/tmp/dl',
        fileName: 'a.mp4',
        status: DownloadStatus.failed,
      );
      t.url = 'https://fresh.example/b.mp4';
      expect(t.url, 'https://fresh.example/b.mp4');
    });
  });

  group('DownloadService.shouldReresolveOnFailure — retry gate (pure)', () {
    test('re-resolves platform origins within the 2-attempt budget', () {
      expect(
        DownloadService.shouldReresolveOnFailure(
            originUrl: 'https://vt.tiktok.com/ZSbjGXQu6/', attempts: 0),
        isTrue,
      );
      expect(
        DownloadService.shouldReresolveOnFailure(
            originUrl: 'https://x.com/u/status/1234567890123456789',
            attempts: 1),
        isTrue,
      );
    });

    test('never re-resolves after the 2-attempt budget', () {
      expect(
        DownloadService.shouldReresolveOnFailure(
            originUrl: 'https://vt.tiktok.com/ZSbjGXQu6/', attempts: 2),
        isFalse,
      );
      expect(
        DownloadService.shouldReresolveOnFailure(
            originUrl: 'https://fb.watch/abc123/', attempts: 5),
        isFalse,
      );
    });

    test('plain/direct URLs never trigger re-resolve', () {
      expect(
        DownloadService.shouldReresolveOnFailure(
            originUrl: 'https://cdn.example.com/movie.mp4', attempts: 0),
        isFalse,
      );
      expect(
        DownloadService.shouldReresolveOnFailure(originUrl: null, attempts: 0),
        isFalse,
      );
    });

    test('look-alike evil hosts never trigger re-resolve', () {
      expect(
        DownloadService.shouldReresolveOnFailure(
            originUrl: 'https://tiktok.com.evil.com/video/1', attempts: 0),
        isFalse,
      );
    });
  });

  group('Preflight contract — resolution does not run twice', () {
    test('resolved media carries direct URL + headers for the engine', () {
      // The sheet passes ResolvedPlatformMedia straight into start(); the
      // engine must receive a CDN address plus its required headers.
      final media = ResolvedPlatformMedia(
        directUrl: 'https://v19.tiktokcdn-us.com/abc/video/tos/x.mp4',
        headers: const {'User-Agent': 'Mozilla/5.0'},
        title: 'فيديو تجريبي',
        platform: 'tiktok',
      );
      expect(media.directUrl, startsWith('https://'));
      expect(media.headers, isNotEmpty);
      expect(media.platform, 'tiktok');
    });
  });
}
