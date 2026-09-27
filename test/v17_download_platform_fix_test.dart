import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/data/models/download_task.dart';
import 'package:drs_video/services/downloader/platform_download_resolver.dart';
import 'package:drs_video/services/network/social_resolver.dart';
import 'package:drs_video/services/network/tiktok_resolver.dart';
import 'package:drs_video/services/downloader/url_probe_service.dart';
import 'package:drs_video/services/smart/intel_v4.dart';
import 'package:drs_video/core/errors/app_exception.dart';

/// v1.14.1 regression tests — "TikTok download saves a .txt document".
///
/// The fix: platform share links are resolved into direct media BEFORE the
/// download engine probes/enqueues them, page-like responses are never
/// saved, and CDN headers travel with the task.
void main() {
  group('PlatformDownloadResolver — needsResolution (pure)', () {
    test('accepts every TikTok share-link form', () {
      expect(PlatformDownloadResolver.needsResolution(
          'https://vt.tiktok.com/ZSbjGXQu6/'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://vm.tiktok.com/ZMhQxKpLE/'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://www.tiktok.com/@user/video/7680238319296335111'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://m.tiktok.com/v/7318517321748022790.html'), isTrue);
    });

    test('accepts X/Twitter and Facebook share links', () {
      expect(PlatformDownloadResolver.needsResolution(
          'https://x.com/user/status/1234567890123456789'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://twitter.com/user/status/1234567890123456789'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://fb.watch/abCdEf123/'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://www.facebook.com/watch/?v=123456789'), isTrue);
    });

    test('rejects direct media and other platforms', () {
      expect(PlatformDownloadResolver.needsResolution(
          'https://cdn.example.com/movie.mp4'), isFalse);
      expect(PlatformDownloadResolver.needsResolution(
          'https://youtube.com/watch?v=abc'), isFalse);
      expect(PlatformDownloadResolver.needsResolution(
          'https://instagram.com/p/abc/'), isFalse);
      expect(PlatformDownloadResolver.needsResolution(''), isFalse);
    });

    test('rejects look-alike hosts (evil-domain guard)', () {
      expect(TikTokResolver.isTikTokUrl('https://tiktok.com.evil.com/video/123'),
          isFalse);
      expect(PlatformDownloadResolver.needsResolution(
          'https://tiktok.com.evil.com/video/123'), isFalse);
      expect(SocialResolver.isTwitterUrl('https://x.com.evil.com/status/1'),
          isFalse);
      expect(SocialResolver.isFacebookUrl('https://facebook.com.evil.com/v/1'),
          isFalse);
    });
  });

  group('PlatformDownloadResolver — page-like MIME rule (pure)', () {
    test('HTML/JSON content types are page-like', () {
      expect(PlatformDownloadResolver.isPageLikeMime('text/html'), isTrue);
      expect(PlatformDownloadResolver.isPageLikeMime('text/html; charset=utf-8'),
          isTrue);
      expect(PlatformDownloadResolver.isPageLikeMime('application/xhtml+xml'),
          isTrue);
      expect(PlatformDownloadResolver.isPageLikeMime('application/json'), isTrue);
      expect(PlatformDownloadResolver.isPageLikeMime('TEXT/HTML'), isTrue);
    });

    test('media and unknown content types are not page-like', () {
      expect(PlatformDownloadResolver.isPageLikeMime('video/mp4'), isFalse);
      expect(PlatformDownloadResolver.isPageLikeMime('audio/mpeg'), isFalse);
      expect(PlatformDownloadResolver.isPageLikeMime('image/jpeg'), isFalse);
      expect(PlatformDownloadResolver.isPageLikeMime('application/octet-stream'),
          isFalse);
      expect(PlatformDownloadResolver.isPageLikeMime(null), isFalse);
      expect(PlatformDownloadResolver.isPageLikeMime(''), isFalse);
    });

    test('explicit .html URL extension means the user wants the page', () {
      expect(PlatformDownloadResolver.hasPageExtension(
          'https://example.com/page.html'), isTrue);
      expect(PlatformDownloadResolver.hasPageExtension(
          'https://example.com/page.htm'), isTrue);
      expect(PlatformDownloadResolver.hasPageExtension(
          'https://vt.tiktok.com/ZSbjGXQu6/'), isFalse);
      expect(PlatformDownloadResolver.hasPageExtension(
          'https://example.com/movie.mp4'), isFalse);
    });

    test('shouldAbortAsPageSave — the .txt bug regression gate', () {
      // The exact user bug: TikTok page probed as text/html must abort.
      expect(PlatformDownloadResolver.shouldAbortAsPageSave(
          contentType: 'text/html; charset=utf-8',
          url: 'https://www.tiktok.com/@user/video/7680238319296335111'),
          isTrue);
      // A real media probe must never abort.
      expect(PlatformDownloadResolver.shouldAbortAsPageSave(
          contentType: 'video/mp4',
          url: 'https://v19.tiktokcdn-us.com/video/tos/alisg/x.mp4'),
          isFalse);
      // Explicit page save stays allowed.
      expect(PlatformDownloadResolver.shouldAbortAsPageSave(
          contentType: 'text/html', url: 'https://example.com/doc.html'),
          isFalse);
      // Probe failure (null mime) keeps legacy behavior.
      expect(PlatformDownloadResolver.shouldAbortAsPageSave(
          contentType: null, url: 'https://example.com/file'),
          isFalse);
    });

    test('extensionFor: video mime on extension-less URL → mp4', () {
      expect(
          DownloadClassifier.extensionFor(
              url: 'https://v19.tiktokcdn-us.com/cc92/6ab9/video/tos/alisg/x',
              contentType: 'video/mp4'),
          'mp4');
    });
  });

  group('DownloadTaskModel — headers persistence', () {
    test('headers round-trip through toMap/fromMap', () {
      final task = DownloadTaskModel(
        id: 'dl_test1',
        url: 'https://cdn.example.com/v.mp4',
        savedDir: '/tmp/x',
        fileName: 'v.mp4',
        status: DownloadStatus.queued,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
          'Referer': 'https://www.tiktok.com/',
        },
      );
      final restored = DownloadTaskModel.fromMap(task.toMap());
      expect(restored.headers, isNotNull);
      expect(restored.headers!['User-Agent'], 'Mozilla/5.0 (Linux; Android 14)');
      expect(restored.headers!['Referer'], 'https://www.tiktok.com/');
    });

    test('null headers stay null and corrupt JSON degrades safely', () {
      final task = DownloadTaskModel(
        id: 'dl_test2',
        url: 'https://cdn.example.com/v.mp4',
        savedDir: '/tmp/x',
        fileName: 'v.mp4',
        status: DownloadStatus.queued,
      );
      expect(task.toMap()['headers'], isNull);
      expect(DownloadTaskModel.fromMap(task.toMap()).headers, isNull);

      final corrupt = task.toMap()..['headers'] = '{not-json';
      expect(DownloadTaskModel.fromMap(corrupt).headers, isNull);

      final nonMap = task.toMap()..['headers'] = jsonEncode(['a', 'b']);
      expect(DownloadTaskModel.fromMap(nonMap).headers, isNull);
    });
  });

  group('ProbeSummary — resolved title carrier', () {
    ProbeSummary sample() => ProbeSummary.fromResponse(
          status: 200,
          headers: const {
            'content-type': ['video/mp4'],
            'content-length': ['464203'],
            'accept-ranges': ['bytes'],
          },
          url: 'https://v19.tiktokcdn-us.com/x',
        );

    test('parses real media probe', () {
      final s = sample();
      expect(s.kind, DownloadKind.video);
      expect(s.sizeBytes, 464203);
      expect(s.resumable, isTrue);
      expect(s.resolvedTitle, isNull);
    });

    test('withResolvedTitle carries the platform title', () {
      final s = sample().withResolvedTitle('#المصريه_الحساويه #نور');
      expect(s.resolvedTitle, '#المصريه_الحساويه #نور');
      expect(s.kind, DownloadKind.video);
      expect(s.sizeBytes, 464203);
    });

    test('range-GET probe: content-range carries the real total', () {
      // TikTok CDN: HEAD → 503, GET bytes=0-0 → 206 with content-range.
      final s = ProbeSummary.fromResponse(
        status: 206,
        headers: const {
          'content-type': ['video/mp4'],
          'content-length': ['1'],
          'content-range': ['bytes 0-0/542615'],
        },
        url: 'https://v16-notes.tiktokcdn-us.com/x',
      );
      expect(s.kind, DownloadKind.video);
      expect(s.sizeBytes, 542615); // total from content-range, not the 1 byte
      expect(s.resumable, isTrue); // 206 proves range support
      expect(s.contentType, 'video/mp4');
    });
  });

  group('UrlProbeService — HEAD-hostile fallback chain', () {
    test('falls back to range-GET when HEAD fails, keeps resolved title',
        () async {
      final seen = <String>[];
      final service = UrlProbeService(
        fetcher: (url, headers) async {
          seen.add('head');
          throw const AppException(AppErrorType.network);
        },
        rangeFetcher: (url, headers) async {
          seen.add('range');
          return Response<List<int>>(
            requestOptions: RequestOptions(path: url),
            statusCode: 206,
            headers: Headers.fromMap(const {
              'content-type': ['video/mp4'],
              'content-range': ['bytes 0-0/280000'],
            }),
          );
        },
      );
      final s = await service.probe('https://v16.tiktokcdn-us.com/v/abc');
      expect(seen, ['head', 'range']);
      expect(s.kind, DownloadKind.video);
      expect(s.sizeBytes, 280000);
      expect(s.resumable, isTrue);
    });

    test('plain HEAD success never triggers the range fallback', () async {
      final seen = <String>[];
      final service = UrlProbeService(
        fetcher: (url, headers) async {
          seen.add('head');
          return Response<List<int>>(
            requestOptions: RequestOptions(path: url),
            statusCode: 200,
            headers: Headers.fromMap(const {
              'content-type': ['video/mp4'],
              'content-length': ['1000'],
            }),
          );
        },
        rangeFetcher: (url, headers) async {
          seen.add('range');
          throw StateError('must not be called');
        },
      );
      final s = await service.probe('https://cdn.example.com/x.mp4');
      expect(seen, ['head']);
      expect(s.sizeBytes, 1000);
      expect(s.resumable, isFalse);
    });
  });
}
