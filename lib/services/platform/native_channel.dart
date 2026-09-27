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

  /// Toggles FLAG_SECURE (v1.10.0 private vault): while active the app's
  /// surface cannot be screenshotted, recorded, or shown in recents.
  Future<void> setSecureFlag(bool secure) =>
      _invoke<void>('window/secure', {'secure': secure});

  Future<bool> isPipSupported() async => (await _invoke<bool>('pip/supported')) ?? false;

  /// Opens the system "All files access" settings page.
  Future<void> openManageAllFiles() => _invoke<void>('settings/allFiles');

  /// Hands [url] to the system (external browser / matching app).
  /// Returns false when no external handler is installed. Used as the
  /// escape hatch when the in-app WebView cannot render a page (v1.4.2).
  Future<bool> openExternal(String url) async =>
      (await _invoke<bool>('open/external', {'url': url})) ?? false;

  // ---- in-app self-update (v1.12.0) ----

  /// Fires the system package-installer for a staged APK [path] (inside
  /// the app's cache dir, exposed through FileProvider). Returns false
  /// when no installer is available or the user blocked installs.
  Future<bool> installApk(String path) async =>
      (await _invoke<bool>('update/install', {'path': path})) ?? false;

  /// Current battery state: {'level': 0..100 (-1 unknown), 'plugged': bool}.
  Future<Map<String, Object?>> batteryState() async {
    final raw = await _invoke<Map<Object?, Object?>>('battery/state');
    return <String, Object?>{
      'level': (raw?['level'] as num?)?.toInt() ?? -1,
      'plugged': (raw?['plugged'] as bool?) ?? false,
    };
  }

  /// Last session's native (Java/Kotlin) crash log, or null when the
  /// previous session ended cleanly. Used by the boot screen so a hard
  /// crash never stays silent.
  Future<String?> nativeCrashLog() => _invoke<String>('crash/nativeLog');

  /// Clears native + marks the session healthy (called after a
  /// successful boot; the Dart-side store is cleared separately).
  Future<void> clearNativeCrashLog() => _invoke<void>('crash/clearAll');

  // ---- incoming share/view intents (v1.3.0) ----

  void Function(String url)? _onIntentUrl;

  /// Registers the callback fired when MainActivity receives a new
  /// share/view intent while the app is running (onNewIntent).
  void handleIntentUrls(void Function(String url) onUrl) {
    _onIntentUrl = onUrl;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'intent/url') {
        final url = call.arguments as String?;
        if (url != null && url.isNotEmpty) {
          _onIntentUrl?.call(url);
        }
        return null;
      }
      return null;
    });
  }

  /// URL from the intent that launched the app (cold start), or null.
  Future<String?> initialIntentUrl() => _invoke<String>('intent/initial');
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
