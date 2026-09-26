import 'package:dio/dio.dart';
import '../errors/app_exception.dart';
import '../utils/logger.dart';

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
  Future<Response<dynamic>> head(String url, {Map<String, String>? headers}) async {
    try {
      return await _dio.head(url, options: Options(headers: headers, followRedirects: true));
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
}

/// Retries idempotent requests (GET/HEAD) up to [maxAttempts] with backoff.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.maxAttempts = 3});

  final Dio _dio;
  final int maxAttempts;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
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
