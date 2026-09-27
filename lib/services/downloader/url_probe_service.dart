import 'package:dio/dio.dart' show Response;

import '../../core/errors/app_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/logger.dart';
import '../smart/intel_v4.dart';

/// Probes a URL with a HEAD request and returns a pure [ProbeSummary] used
/// by the add-download sheet preview (العرض): file name, size, kind,
/// resumable state.
///
/// The HTTP fetch is injectable so unit tests can feed canned responses
/// without sockets.
class UrlProbeService {
  UrlProbeService({Future<Response<dynamic>> Function(String url)? fetcher})
      : _fetcher = fetcher ?? _defaultFetch;

  static Future<Response<dynamic>> _defaultFetch(String url) =>
      DioClient.instance.head(url);

  final Future<Response<dynamic>> Function(String url) _fetcher;

  /// Returns a summary, or throws [AppException] with a user-actionable type.
  /// Network errors are NOT swallowed: the sheet shows them verbatim.
  Future<ProbeSummary> probe(String url) async {
    try {
      final res = await _fetcher(url);
      return ProbeSummary.fromResponse(
        status: res.statusCode ?? 0,
        headers: res.headers.map,
        url: url,
      );
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
