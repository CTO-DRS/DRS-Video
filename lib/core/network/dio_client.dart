import 'package:dio/dio.dart';
import '../errors/app_exception.dart';
import '../utils/logger.dart';
import 'cleartext_policy.dart';

/// Shared HTTP layer: timeouts, bounded retry with backoff, logging.
class DioClient {
  DioClient._() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 20),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (code) => code != null && code < 400,
      headers: {
        'User-Agent': 'DRSVideo/1.0.1 (Android)',
        'Accept': '*/*',
      },
    ));
    // P3: app-controlled endpoints (updates / resolvers / translation)
    // must never downgrade to plain HTTP — reject before a socket opens.
    _dio.interceptors.add(const CleartextGuardInterceptor());
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        AppLogger.instance
            .debug('http', '${options.method} ${options.uri} (try ${options.extra['try'] ?? 1})');
        handler.next(options);
      },
    ));
    _dio.interceptors.add(RetryInterceptor(_dio));
  }

  static final DioClient instance = DioClient._();

  late final Dio _dio;
  Dio get dio => _dio;

  /// HEAD probe used to learn size/content-type/range support without
  /// downloading the body.
  ///
  /// v1.14.2: [timeout] overrides the generous 15s/30s defaults per call
  /// (probes pass ~8s so a dead host fails fast instead of starving the
  /// UI), and [noRetry] skips RetryInterceptor — 3 retries × backoff used
  /// to turn one failed probe into ~45s of dead waiting.
  Future<Response<dynamic>> head(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
    bool noRetry = false,
  }) async {
    try {
      return await _dio.head(url,
          options: Options(
            headers: headers,
            followRedirects: true,
            connectTimeout: timeout,
            receiveTimeout: timeout,
            sendTimeout: timeout,
            extra: noRetry ? const {'drsNoRetry': true} : null,
          ));
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<Response<dynamic>> get(
    String url, {
    Map<String, String>? headers,
    ResponseType responseType = ResponseType.json,
  }) async {
    try {
      return await _dio.get(url,
          options: Options(headers: headers, responseType: responseType));
    } catch (e) {
      throw mapException(e);
    }
  }

  /// v1.14.1: 1-byte range GET for servers that reject HEAD outright —
  /// TikTok's CDN answers 503 to HEAD while serving GET normally. The
  /// 206 response carries the authoritative Content-Range total size and
  /// the real content-type. ResponseType.stream is used so a hostile
  /// server that ignores Range and answers 200 never buffers a huge body
  /// into memory — we read headers and close the stream.
  ///
  /// v1.14.2: tight connect budget + optional [noRetry] (probes).
  Future<Response<dynamic>> rangeProbe(String url,
      {Map<String, String>? headers, bool noRetry = false}) async {
    try {
      return await _dio.get(url,
          options: Options(
            headers: {...?headers, 'Range': 'bytes=0-0'},
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(seconds: 15),
            connectTimeout: const Duration(seconds: 8),
            extra: noRetry ? const {'drsNoRetry': true} : null,
          ));
    } catch (e) {
      throw mapException(e);
    }
  }
}

/// Retries idempotent requests (GET/HEAD) up to [maxAttempts] with backoff.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.maxAttempts = 3});

  final Dio _dio;
  final int maxAttempts;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // v1.14.2: opt-out flag — probe paths must fail FAST (a 3× retried
    // HEAD to a dead host cost ~45s before this guard).
    if (err.requestOptions.extra['drsNoRetry'] == true) {
      return handler.next(err);
    }
    final extra = err.requestOptions.extra;
    final tryCount = (extra['try'] as int? ?? 1) + 1;
    final method = err.requestOptions.method.toUpperCase();
    final retryable = method == 'GET' || method == 'HEAD';
    final transient = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;

    if (retryable && transient && tryCount <= maxAttempts) {
      final backoff = Duration(milliseconds: 400 * (1 << (tryCount - 1)));
      await Future.delayed(backoff);
      final opts = err.requestOptions;
      opts.extra['try'] = tryCount;
      AppLogger.instance.warning('http', 'retry #$tryCount ${opts.uri}');
      try {
        final response = await _dio.fetch(opts);
        return handler.resolve(response);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}
