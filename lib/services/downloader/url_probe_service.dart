import 'package:dio/dio.dart' show Response;

import '../../core/errors/app_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/logger.dart';
import '../smart/intel_v4.dart';
import 'platform_download_resolver.dart';

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
      DioClient.instance.head(url, headers: headers);

  static Future<Response<dynamic>> _defaultRangeFetch(
          String url, Map<String, String> headers) =>
      DioClient.instance.rangeProbe(url, headers: headers);

  final Future<Response<dynamic>> Function(String url, Map<String, String> headers)
      _fetcher;
  final Future<Response<dynamic>> Function(String url, Map<String, String> headers)
      _rangeFetcher;

  /// Returns a summary, or throws [AppException] with a user-actionable type.
  /// Network errors are NOT swallowed: the sheet shows them verbatim.
  Future<ProbeSummary> probe(String url) async {
    var effectiveUrl = url;
    var headers = const <String, String>{};
    String? resolvedTitle;

    // Platform pages are HTML — resolve the real media URL first so the
    // preview reflects what will actually be downloaded. Resolution
    // failures do NOT block probing (the download engine reports them).
    try {
      final resolved = await PlatformDownloadResolver.instance.resolve(url);
      if (resolved != null) {
        effectiveUrl = resolved.directUrl;
        headers = resolved.headers;
        resolvedTitle = resolved.title;
      }
    } catch (e) {
      AppLogger.instance.warning('probe', 'platform resolve skipped: $e');
    }

    try {
      final res = await _fetcher(effectiveUrl, headers);
      return _summarize(res, effectiveUrl, resolvedTitle);
    } on AppException {
      // HEAD-hostile CDN → 1-byte range GET fallback (real content-type +
      // total size from Content-Range, byte-budgeted so it can never pull
      // a huge body).
      try {
        final r = await _rangeFetcher(effectiveUrl, headers);
        return _summarize(r, effectiveUrl, resolvedTitle);
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
