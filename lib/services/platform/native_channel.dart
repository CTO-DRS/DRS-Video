import 'dart:io';
import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

/// Bridge to Android-side capabilities implemented in MainActivity (Kotlin):
/// MediaStore queries, thumbnails, PiP, MediaScanner, StatFs, brightness.
class NativeChannel {
  NativeChannel._();

  static final NativeChannel instance = NativeChannel._();

  static const MethodChannel _ch = MethodChannel(AppConstants.nativeChannel);

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException catch (e, s) {
      AppLogger.instance
          .error('native', '$method failed: ${e.code} ${e.message}', e, s);
      return null;
    } on MissingPluginException {
      AppLogger.instance.warning('native', '$method: no plugin');
      return null;
    }
  }

  /// All on-device videos from MediaStore:
  /// [{id, title, path, durationMs, sizeBytes, width, height, addedAt}]
  Future<List<Map<String, Object?>>> localVideos() async {
    final raw = await _invoke<List<dynamic>>('media/videos');
    if (raw == null) return [];
    return raw.map((e) => Map<String, Object?>.from(e as Map)).toList();
  }

  /// Extracts/saves a thumbnail for a MediaStore id, returns path or null.
  Future<String?> thumbnail(int mediaStoreId) =>
      _invoke<String>('media/thumbnail', {'id': mediaStoreId});

  /// Prompts the system delete dialog (Android 11+) or deletes directly.
  Future<bool> deleteUris(List<String> paths) async {
    final ok = await _invoke<bool>('media/delete', {'paths': paths});
    return ok ?? false;
  }

  Future<void> scanFile(String path) =>
      _invoke<void>('media/scan', {'path': path});

  Future<int> freeSpaceBytes(String path) async {
    final v = await _invoke<int>('storage/free', {'path': path});
    return v ?? -1;
  }

  Future<int> totalSpaceBytes(String path) async {
    final v = await _invoke<int>('storage/total', {'path': path});
    return v ?? -1;
  }

  Future<void> enterPip({required int width, required int height}) =>
      _invoke<void>('pip/start', {'width': width, 'height': height});

  Future<void> setAutoPip(bool enabled) =>
      _invoke<void>('pip/auto', {'enabled': enabled});

  /// Sets window brightness 0..1 (gesture control); null resets to system.
  Future<void> setBrightness(double? value) =>
      _invoke<void>('window/brightness', {'value': value});

  Future<bool> isPipSupported() async => (await _invoke<bool>('pip/supported')) ?? false;

  /// Opens the system "All files access" settings page.
  Future<void> openManageAllFiles() => _invoke<void>('settings/allFiles');

  /// Last session's native (Java/Kotlin) crash log, or null when the
  /// previous session ended cleanly. Used by the boot screen so a hard
  /// crash never stays silent.
  Future<String?> nativeCrashLog() => _invoke<String>('crash/nativeLog');

  /// Clears native + marks the session healthy (called after a
  /// successful boot; the Dart-side store is cleared separately).
  Future<void> clearNativeCrashLog() => _invoke<void>('crash/clearAll');

  // ---- v1.1.0: gallery screenshots + SAF JSON pick/create (backup) ----

  /// Copies a local image file into the system gallery
  /// (Pictures/DRS Video). Returns the final location (content URI or
  /// file path), or null on failure.
  Future<String?> saveImageToGallery(String filePath) =>
      _invoke<String>('gallery/saveImage', {'path': filePath});

  /// Opens the system file picker for a JSON backup file.
  /// Returns a content:// uri string, or null when cancelled.
  Future<String?> pickJsonForRestore() => _invoke<String>('files/pickJson');

  /// Opens the system "create document" dialog for a new backup file.
  /// Returns a content:// uri string, or null when cancelled.
  Future<String?> createJsonForSave(String suggestedName) =>
      _invoke<String>('files/createJson', {'name': suggestedName});

  /// Reads UTF-8 text from a previously picked (or created) document uri.
  Future<String?> readPickedTextFile(String uri) =>
      _invoke<String>('files/read', {'uri': uri});

  /// Writes UTF-8 text into a previously created document uri.
  Future<bool> writeCreatedTextFile(String uri, String content) async {
    final ok = await _invoke<bool>(
        'files/write', {'uri': uri, 'content': content});
    return ok ?? false;
  }
}

/// Wraps local file system helpers shared by services.
class LocalFs {
  LocalFs._();

  static int dirSizeSync(String path) {
    var total = 0;
    final dir = Directory(path);
    if (!dir.existsSync()) return 0;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += e.lengthSync();
        } catch (err) {
          // Unreadable file: skipped from the total, but never silently.
          AppLogger.instance.warning('native', 'size failed for ${e.path}: $err');
        }
      }
    }
    return total;
  }
}
