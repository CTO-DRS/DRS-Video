import 'package:dio/dio.dart';

/// Error types mapped to localized user-facing messages in the UI layer.
enum AppErrorType {
  network,
  timeout,
  notFound,
  forbidden,
  unsupported,
  corrupted,
  storage,
  permission,
  cancelled,
  invalidInput,
  unknown,
}

class AppException implements Exception {
  const AppException(this.type, {this.detail});

  final AppErrorType type;
  final String? detail;

  @override
  String toString() => 'AppException(${type.name}, detail: $detail)';
}

/// Converts any thrown error (Dio / IO / player) into a stable [AppException].
AppException mapException(Object error, {StackTrace? stack}) {
  if (error is AppException) return error;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppException(AppErrorType.timeout, detail: error.message);
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return AppException(AppErrorType.network, detail: error.message);
      case DioExceptionType.badCertificate:
        return AppException(AppErrorType.forbidden, detail: error.message);
      case DioExceptionType.cancel:
        return AppException(AppErrorType.cancelled, detail: error.message);
      case DioExceptionType.badResponse:
      case DioExceptionType.transformTimeout:
        final code = error.response?.statusCode ?? 0;
        if (code == 404) return AppException(AppErrorType.notFound, detail: '$code');
        if (code == 401 || code == 403) {
          return AppException(AppErrorType.forbidden, detail: '$code');
        }
        if (code == 415) return AppException(AppErrorType.unsupported, detail: '$code');
        return AppException(AppErrorType.network, detail: 'HTTP $code');
    }
  }
  final msg = error.toString().toLowerCase();
  if (msg.contains('no space left') || msg.contains('enospc')) {
    return const AppException(AppErrorType.storage);
  }
  if (msg.contains('permission')) return const AppException(AppErrorType.permission);
  if (msg.contains('format') || msg.contains('codec') || msg.contains('demuxer')) {
    return const AppException(AppErrorType.unsupported);
  }
  if (msg.contains('corrupt') || msg.contains('invalid data')) {
    return const AppException(AppErrorType.corrupted);
  }
  return AppException(AppErrorType.unknown, detail: error.toString());
}
