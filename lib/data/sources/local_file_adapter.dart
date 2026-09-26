import 'dart:io';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/validators.dart';
import '../models/playlist.dart';
import 'source_adapter.dart';

/// Resolves local video files picked by the user.
class LocalFileAdapter extends SourceAdapter {
  @override
  String get id => 'local';

  @override
  String get name => 'Local file';

  @override
  bool get supportsDownload => false; // already on device

  @override
  bool canHandle(String url) =>
      !url.startsWith('http') && Validators.isVideoFile(url);

  @override
  Future<ResolvedMedia> resolve(String url, {Map<String, String>? extraHeaders}) async {
    final file = File(url);
    if (!file.existsSync()) {
      throw const AppException(AppErrorType.notFound, detail: 'file missing');
    }
    final stat = file.statSync();
    if (stat.size == 0) {
      throw const AppException(AppErrorType.corrupted, detail: 'empty file');
    }
    final ext = Validators.extensionOf(url);
    if (!AppConstants.videoExtensions.contains(ext)) {
      throw AppException(AppErrorType.unsupported, detail: '.$ext');
    }
    return ResolvedMedia(
      title: Validators.sanitizeFileName(
        Validators.extensionOf(url).isEmpty
            ? url
            : url.split(Platform.pathSeparator).last,
      ).replaceAll(RegExp(r'\.[a-z0-9]+$'), ''),
      streamUrl: url,
      sizeBytes: stat.size,
      resumable: true,
      contentType: 'video/$ext',
    );
  }
}
