import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/validators.dart';
import '../platform/native_channel.dart';

/// Video-oriented file manager for app-managed folders plus MediaStore items.
class FileManagerService {
  const FileManagerService();

  Future<List<FileInfo2>> listDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    final files = <FileInfo2>[];
    await for (final e in dir.list()) {
      if (e is File && Validators.isVideoFile(e.path)) {
        try {
          final stat = e.statSync();
          files.add(FileInfo2(
            path: e.path,
            sizeBytes: stat.size,
            modified: stat.modified,
          ));
        } catch (err) {
          // Unreadable entry: skipped, but never silently.
          AppLogger.instance.warning('fs', 'stat failed for ${e.path}: $err');
        }
      }
    }
    return files;
  }

  Future<void> rename(String oldPath, String newTitle) async {
    final dir = p.dirname(oldPath);
    final ext = p.extension(oldPath);
    final sanitized = Validators.sanitizeFileName(newTitle);
    final newPath = p.join(dir, '$sanitized$ext');
    if (newPath == oldPath) return;
    if (File(newPath).existsSync()) {
      throw const AppException(AppErrorType.invalidInput, detail: 'name exists');
    }
    try {
      await File(oldPath).rename(newPath);
      await NativeChannel.instance.scanFile(newPath);
    } catch (e) {
      throw AppException(AppErrorType.storage, detail: e.toString());
    }
  }

  Future<void> delete(String path) async {
    final ok = await NativeChannel.instance.deleteUris([path]);
    if (!ok) {
      // Fallback for app-private files where no system dialog appears.
      final f = File(path);
      if (f.existsSync()) {
        await f.delete();
      } else {
        throw const AppException(AppErrorType.notFound);
      }
    }
  }

  Future<String> moveToDir(String path, String targetDir) async {
    final target = p.join(targetDir, p.basename(path));
    if (File(target).existsSync()) {
      throw const AppException(AppErrorType.invalidInput, detail: 'exists');
    }
    final moved = await File(path).rename(target);
    await NativeChannel.instance.scanFile(target);
    AppLogger.instance.info('fs', 'moved to ${moved.path}');
    return moved.path;
  }
}

class FileInfo2 {
  const FileInfo2({
    required this.path,
    required this.sizeBytes,
    required this.modified,
  });

  final String path;
  final int sizeBytes;
  final DateTime modified;

  String get name => p.basename(path);
}
