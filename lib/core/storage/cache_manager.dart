import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';
import '../utils/logger.dart';

class CacheStats {
  const CacheStats({required this.thumbnailsBytes, required this.tempBytes, required this.files});

  final int thumbnailsBytes;
  final int tempBytes;
  final int files;

  int get totalBytes => thumbnailsBytes + tempBytes;
}

/// Thumbnail/metadata cache with size limit and LRU cleanup.
class CacheManager {
  CacheManager._();
  static final CacheManager instance = CacheManager._();

  Directory? _thumbDir;

  Future<Directory> thumbDir() async {
    if (_thumbDir != null) return _thumbDir!;
    final base = await getApplicationSupportDirectory();
    _thumbDir = Directory(p.join(base.path, 'thumbs'));
    if (!_thumbDir!.existsSync()) await _thumbDir!.create(recursive: true);
    return _thumbDir!;
  }

  /// Returns a cached thumbnail path for [key] if present, else null.
  Future<String?> get(String key) async {
    final dir = await thumbDir();
    final file = File(p.join(dir.path, '$key.jpg'));
    return file.existsSync() ? file.path : null;
  }

  Future<String> put(String key, List<int> bytes) async {
    final dir = await thumbDir();
    final file = File(p.join(dir.path, '$key.jpg'));
    await file.writeAsBytes(bytes);
    unawaited(_enforceLimit());
    return file.path;
  }

  /// Deletes least-recently-used thumbnails until total is under the limit.
  Future<void> _enforceLimit() async {
    try {
      final dir = await thumbDir();
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      var total = 0;
      for (final f in files) {
        total += await f.length();
      }
      if (total <= AppConstants.maxThumbnailCacheBytes) return;
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in files) {
        if (total <= AppConstants.maxThumbnailCacheBytes) break;
        total -= await f.length();
        await f.delete();
      }
    } catch (e) {
      AppLogger.instance.warning('cache', 'enforce failed: $e');
    }
  }

  static int _dirSizeSync(String path) {
    var total = 0;
    final dir = Directory(path);
    if (!dir.existsSync()) return 0;
    final entities = dir.listSync(recursive: true, followLinks: false);
    for (final e in entities) {
      if (e is File) total += e.lengthSync();
    }
    return total;
  }

  Future<CacheStats> stats() async {
    final dir = await thumbDir();
    final temp = await getTemporaryDirectory();
    final results = await Future.wait([
      compute(_dirSizeSync, dir.path),
      compute(_dirSizeSync, temp.path),
    ]);
    final thumbFiles = dir.existsSync() ? dir.listSync().length : 0;
    return CacheStats(
        thumbnailsBytes: results[0], tempBytes: results[1], files: thumbFiles);
  }

  Future<void> clearThumbnails() async {
    final dir = await thumbDir();
    if (dir.existsSync()) await dir.delete(recursive: true);
    await thumbDir();
  }

  Future<void> clearTemp() async {
    final temp = await getTemporaryDirectory();
    if (temp.existsSync()) {
      await for (final e in temp.list()) {
        try {
          await e.delete(recursive: true);
        } catch (err) {
          // Best-effort cleanup — logged, never silent.
          AppLogger.instance.warning('cache', 'temp delete failed: $err');
        }
      }
    }
  }
}

/// Simple fire-and-forget helper.
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    AppLogger.instance.warning('cache', 'unawaited error: $e');
  });
}
