import 'package:dio/dio.dart' show Response;

import '../../core/errors/app_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/logger.dart';
import '../smart/intel_v4.dart';
import 'platform_download_resolver.dart';

/// Probes a URL with a HEAD request and returns a pure [ProbeSummary] used
/// by the add-download sheet preview (العرض): file name, size, kind,
/// resumable state.
///
/// v1.14.1: platform share links (TikTok vm./vt., X, Facebook) are resolved
/// into their direct media URL first, so the preview shows the REAL video
/// (kind in vídeo, CDN size) instead of "document / text/html" — and the
/// probe carries the resolved CDN headers.
///
/// The HTTP fetch is injectable so unit tests can feed canned responses
/// without sockets.
class UrlProbeService {
  UrlProbeService({Future<Response<dynamic>> Function(String url, Map<String, String> headers)? fetcher})
      : _fetcher = fetcher ?? _defaultFetch;

  static Future<Response<dynamic>> _defaultFetch(
          String url, Map<String, String> headers) =>
      DioClient.instance.head(url, headers: headers);

  final Future<Response<dynamic>> Function(String url, Map<String, String> headers)
      _fetcher;

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
      final summary = ProbeSummary.fromResponse(
        status: res.statusCode ?? 0,
        headers: res.headers.map,
        url: effectiveUrl,
      );
      return resolvedTitle == null
          ? summary
          : summary.withResolvedTitle(resolvedTitle);
    } on FormatException catch (e) {
      throw AppException(AppErrorType.notFound, detail: e.message);
    } on AppException {
      rethrow;
    } catch (e) {
      AppLogger.instance.warning('probe', 'HEAD failed: $e');
      throw const AppException(AppErrorType.network);
    }
  }
}
