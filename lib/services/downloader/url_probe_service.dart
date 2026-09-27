import 'package:dio/dio.dart' show Response;

import '../../core/errors/app_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/logger.dart';
import '../smart/intel_v4.dart';
import 'platform_download_resolver.dart';

/// v1.14.2: probe result CARRYING the resolved platform media. The
/// add-download sheet passes both to DownloadService.start so resolution
/// + probing run exactly ONCE per download instead of twice.
class ProbeWithMedia {
  const ProbeWithMedia({required this.summary, this.media});
  final ProbeSummary summary;
  final ResolvedPlatformMedia? media;
}

/// Probes a URL and returns a pure [ProbeSummary] used by the add-download
/// sheet preview (العرض): file name, size, kind, resumable state.
///
/// Strategy (v1.14.1):
/// 1. Platform share links (TikTok vm./vt., X, Facebook) are resolved into
///    their direct media URL first, so the preview shows the REAL video
///    (kind video, CDN size) instead of "document / text/html".
/// 2. HEAD request with the resolved CDN headers.
/// 3. HEAD-hostile servers (TikTok's CDN answers 503 to HEAD while serving
///    GET normally) fall back to a 1-byte range GET whose 206 response
///    carries content-type + total size via Content-Range.
///
/// The fetchers are injectable so unit tests can feed canned responses
/// without sockets.
class UrlProbeService {
  UrlProbeService({
    Future<Response<dynamic>> Function(String url, Map<String, String> headers)?
        fetcher,
    Future<Response<dynamic>> Function(String url, Map<String, String> headers)?
        rangeFetcher,
  })  : _fetcher = fetcher ?? _defaultFetch,
        _rangeFetcher = rangeFetcher ?? _defaultRangeFetch;

  static Future<Response<dynamic>> _defaultFetch(
          String url, Map<String, String> headers) =>
      DioClient.instance.head(url,
          headers: headers,
          timeout: const Duration(seconds: 8),
          noRetry: true);

  static Future<Response<dynamic>> _defaultRangeFetch(
          String url, Map<String, String> headers) =>
      DioClient.instance.rangeProbe(url, headers: headers, noRetry: true);

  final Future<Response<dynamic>> Function(String url, Map<String, String> headers)
      _fetcher;
  final Future<Response<dynamic>> Function(String url, Map<String, String> headers)
      _rangeFetcher;

  /// Returns a summary, or throws [AppException] with a user-actionable type.
  /// Network errors are NOT swallowed: the sheet shows them verbatim.
  Future<ProbeSummary> probe(String url) async =>
      (await probeWithMedia(url)).summary;

  /// v1.14.2: the same probe, also returning the resolved platform media
  /// (direct URL + CDN headers + title) so the caller can start the
  /// download WITHOUT re-resolving and re-probing (the double work that
  /// made the flow feel dead-slow).
  Future<ProbeWithMedia> probeWithMedia(String url) async {
    var effectiveUrl = url;
    var headers = const <String, String>{};
    String? resolvedTitle;
    ResolvedPlatformMedia? media;

    // Platform pages are HTML — resolve the real media URL first so the
    // preview reflects what will actually be downloaded. Resolution
    // failures do NOT block probing (the download engine reports them).
    try {
      final resolved = await PlatformDownloadResolver.instance.resolve(url);
      if (resolved != null) {
        media = resolved;
        effectiveUrl = resolved.directUrl;
        headers = resolved.headers;
        resolvedTitle = resolved.title;
      }
    } catch (e) {
      AppLogger.instance.warning('probe', 'platform resolve skipped: $e');
    }

    // v1.14.2: tight 8s budget + noRetry — a probe must answer in seconds,
    // never crawl through 3× retry backoffs.
    try {
      final res = await _fetcher(effectiveUrl, headers);
      return ProbeWithMedia(
        summary: _summarize(res, effectiveUrl, resolvedTitle),
        media: media,
      );
    } on AppException {
      // HEAD-hostile CDN → 1-byte range GET fallback (real content-type +
      // total size from Content-Range, byte-budgeted so it can never pull
      // a huge body).
      try {
        final r = await _rangeFetcher(effectiveUrl, headers);
        return ProbeWithMedia(
          summary: _summarize(r, effectiveUrl, resolvedTitle),
          media: media,
        );
      } catch (e) {
        AppLogger.instance
            .warning('probe', 'HEAD + range-GET both failed: $e');
        rethrow;
      }
    }
  }

  ProbeSummary _summarize(
      Response<dynamic> res, String url, String? resolvedTitle) {
    final summary = ProbeSummary.fromResponse(
      status: res.statusCode ?? 0,
      headers: res.headers.map,
      url: url,
    );
    return resolvedTitle == null
        ? summary
        : summary.withResolvedTitle(resolvedTitle);
  }
}
