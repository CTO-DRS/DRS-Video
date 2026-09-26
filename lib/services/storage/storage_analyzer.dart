import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../platform/native_channel.dart';
import '../../core/storage/cache_manager.dart';
import '../../core/utils/logger.dart';

class StorageReport {
  const StorageReport({
    required this.freeBytes,
    required this.totalBytes,
    required this.downloadsBytes,
    required this.thumbnailsBytes,
    required this.tempBytes,
    required this.largestFiles,
    required this.oldestUnplayed,
  });

  final int freeBytes;
  final int totalBytes;
  final int downloadsBytes;
  final int thumbnailsBytes;
  final int tempBytes;
  final List<FileInfo> largestFiles;
  final List<FileInfo> oldestUnplayed;
}

class FileInfo {
  const FileInfo({required this.path, required this.sizeBytes, required this.modified});
  final String path;
  final int sizeBytes;
  final DateTime modified;
}

/// Storage analysis: sizes, biggest files, old unplayed files.
/// Heavy work runs in isolates to keep the UI responsive.
class StorageAnalyzer {
  const StorageAnalyzer();

  Future<StorageReport> analyze({
    required String downloadDir,
    required List<(String, DateTime?)> downloadedItems,
  }) async {
    final free = await NativeChannel.instance.freeSpaceBytes(downloadDir);
    final total = await NativeChannel.instance.totalSpaceBytes(downloadDir);
    final cache = await CacheManager.instance.stats();

    final files = await compute(_listVideoFilesSync, downloadDir);
    files.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    // Oldest unplayed: downloaded items with no last-played info.
    final unplayed = <FileInfo>[];
    for (final (path, lastPlayed) in downloadedItems) {
      if (lastPlayed != null) continue;
      final f = File(path);
      if (!f.existsSync()) continue;
      final stat = f.statSync();
      unplayed.add(FileInfo(path: path, sizeBytes: stat.size, modified: stat.modified));
    }
    unplayed.sort((a, b) => a.modified.compareTo(b.modified));

    return StorageReport(
      freeBytes: free,
      totalBytes: total,
      downloadsBytes: files.fold(0, (s, f) => s + f.sizeBytes),
      thumbnailsBytes: cache.thumbnailsBytes,
      tempBytes: cache.tempBytes,
      largestFiles: files.take(10).toList(),
      oldestUnplayed: unplayed.take(10).toList(),
    );
  }

  static List<FileInfo> _listVideoFilesSync(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    final result = <FileInfo>[];
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          final stat = e.statSync();
          if (stat.size > 1024) {
            result.add(FileInfo(path: e.path, sizeBytes: stat.size, modified: stat.modified));
          }
        } catch (err) {
          // Unreadable entry: skipped, but never silently.
          AppLogger.instance.warning('storage', 'stat failed for ${e.path}: $err');
        }
      }
    }
    return result;
  }

  static String fileNameOf(String path) => p.basename(path);
}
