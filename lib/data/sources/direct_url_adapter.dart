import 'dart:io';
import '../../core/network/dio_client.dart';
import '../../core/utils/validators.dart';
import '../../core/errors/app_exception.dart';
import '../models/playlist.dart';
import 'source_adapter.dart';

/// Handles any direct media URL (progressive files or HLS manifests).
/// Performs a HEAD probe to learn size, type and Range support.
class DirectUrlAdapter extends SourceAdapter {
  DirectUrlAdapter(this._dioClient);

  final DioClient _dioClient;

  @override
  String get id => 'direct';

  @override
  String get name => 'Direct URL';

  @override
  bool get supportsDownload => true;

  static const _videoMimePrefixes = ['video/', 'application/vnd.apple.mpegurl', 'application/x-mpegurl'];

  @override
  bool canHandle(String url) =>
      Validators.isValidVideoUrl(url) || Validators.isVideoFile(url);

  @override
  Future<ResolvedMedia> resolve(String url, {Map<String, String>? extraHeaders}) async {
    if (!Validators.isValidVideoUrl(url)) {
      throw const AppException(AppErrorType.invalidInput);
    }
    final headers = <String, String>{...?extraHeaders};

    // HEAD probe; some servers reject HEAD, fall back gracefully.
    int? size;
    String? contentType;
    var resumable = false;
    try {
      final res = await _dioClient.head(url, headers: headers);
      size = _parseLength(res.headers.value(HttpHeaders.contentLengthHeader));
      contentType = res.headers.value(HttpHeaders.contentTypeHeader);
      final acceptRanges = res.headers.value(HttpHeaders.acceptRangesHeader);
      resumable = acceptRanges != null && acceptRanges.toLowerCase() == 'bytes';
      final contentRange = res.headers.value('content-range');
      if (contentRange != null) resumable = true;
    } on AppException catch (e) {
      // HEAD unsupported (403/405) does not necessarily mean the URL is bad.
      if (e.type == AppErrorType.notFound) rethrow;
      AppLogger2.log('direct', 'HEAD probe failed: $e');
    }

    final ext = Validators.extensionOf(url);
    final looksLikeVideo = _videoMimePrefixes.any((p) => (contentType ?? '').startsWith(p)) ||
        Validators.isVideoFile(url) ||
        ext == 'm3u8' ||
        ext == 'mpd';

    if (!looksLikeVideo) {
      // Still allow: server may serve video without a recognizable type.
      AppLogger2.log('direct', 'unknown content-type "$contentType" for $url');
    }

    return ResolvedMedia(
      title: Validators.titleFromUrl(url),
      streamUrl: url,
      headers: headers.isEmpty ? null : headers,
      sizeBytes: size,
      resumable: resumable,
      contentType: contentType,
    );
  }

  static int? _parseLength(String? v) => v == null ? null : int.tryParse(v.trim());
}

/// Small logger indirection so this file stays framework-free.
class AppLogger2 {
  static void log(String tag, String message) {
    // ignore: avoid_print
    assert(() {
      print('[$tag] $message');
      return true;
    }());
  }
}
