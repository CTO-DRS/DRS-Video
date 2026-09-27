import 'package:flutter/foundation.dart';
import '../core/network/connectivity_service.dart';
import '../core/storage/database_service.dart';
import '../core/storage/preferences_service.dart';
import '../services/permissions/permission_service.dart';
import '../services/security/pin_lock.dart';

/// Exposes runtime settings and data-clearing operations.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required PreferencesService prefs,
    required DatabaseService db,
    required ConnectivityService connectivity,
  })  : _prefs = prefs,
        _db = db,
        _connectivity = connectivity {
    _connectivity.addListener(notifyListeners);
  }

  final PreferencesService _prefs;
  final DatabaseService _db;
  final ConnectivityService _connectivity;

  bool get isOnline => _connectivity.isOnline;

  // Playback
  String get defaultQuality => _prefs.defaultQuality;
  double get defaultSpeed => _prefs.defaultSpeed;
  bool get autoPlayNext => _prefs.autoPlayNext;
  bool get alwaysResume => _prefs.alwaysResume;
  bool get enablePip => _prefs.enablePip;
  bool get autoPip => _prefs.autoPip;
  bool get enableFloatingPlayer => _prefs.enableFloatingPlayer;
  bool get backgroundPlayback => _prefs.backgroundPlayback;
  bool get preferFullscreen => _prefs.preferFullscreen;

  // Downloads
  String? get downloadDir => _prefs.downloadDir;
  int get maxConcurrent => _prefs.maxConcurrentDownloads;
  bool get wifiOnly => _prefs.wifiOnlyDownloads;
  bool get autoResumeOnWifi => _prefs.autoResumeOnWifi;

  void setAutoResumeOnWifi(bool v) => _set(() => _prefs.autoResumeOnWifi = v);
  bool get notifyDone => _prefs.notifyDownloadDone;
  bool get notifyError => _prefs.notifyDownloadError;
  bool get notifyStorage => _prefs.notifyStorageWarning;

  // Privacy
  bool get historyEnabled => _prefs.historyEnabled;

  // App lock (v1.9.0)
  bool get appLockEnabled => _prefs.appLockHash != null;
  AppLockDelay get appLockDelay =>
      AppLockDelayX.fromId(_prefs.appLockDelayId);

  /// Persists the packed `<salt>:<hash>` record produced by the live
  /// [AppLockController.setPin] — the PIN itself is never persisted.
  void persistAppLockHash(String packed) =>
      _set(() => _prefs.appLockHash = packed);

  /// Clears the stored hash after the live controller verified the
  /// current PIN.
  void clearAppLockHash() => _set(() => _prefs.appLockHash = null);

  void setAppLockDelay(AppLockDelay d) =>
      _set(() => _prefs.appLockDelayId = d.id);

  void _set(void Function() setter) {
    setter();
    notifyListeners();
  }

  void setDefaultQuality(String v) => _set(() => _prefs.defaultQuality = v);
  void setDefaultSpeed(double v) => _set(() => _prefs.defaultSpeed = v);
  void setAutoPlayNext(bool v) => _set(() => _prefs.autoPlayNext = v);
  void setAlwaysResume(bool v) => _set(() => _prefs.alwaysResume = v);
  void setEnablePip(bool v) => _set(() => _prefs.enablePip = v);
  void setAutoPip(bool v) => _set(() => _prefs.autoPip = v);
  void setEnableFloatingPlayer(bool v) =>
      _set(() => _prefs.enableFloatingPlayer = v);
  void setBackgroundPlayback(bool v) => _set(() => _prefs.backgroundPlayback = v);
  void setPreferFullscreen(bool v) => _set(() => _prefs.preferFullscreen = v);
  void setMaxConcurrent(int v) => _set(() => _prefs.maxConcurrentDownloads = v);
  void setWifiOnly(bool v) => _set(() => _prefs.wifiOnlyDownloads = v);
  void setNotifyDone(bool v) => _set(() => _prefs.notifyDownloadDone = v);
  void setNotifyError(bool v) => _set(() => _prefs.notifyDownloadError = v);
  void setNotifyStorage(bool v) => _set(() => _prefs.notifyStorageWarning = v);
  void setDownloadDir(String? v) => _set(() => _prefs.downloadDir = v);
  void setHistoryEnabled(bool v) => _set(() => _prefs.historyEnabled = v);

  /// Clears watch history (progress table).
  Future<void> clearHistory() async {
    final db = await _db.database;
    await db.delete('watch_progress');
  }

  /// Clears stored search queries.
  Future<void> clearSearchHistory() async {
    final db = await _db.database;
    await db.delete('search_history');
  }

  /// Nukes every local table + prefs (used by "clear all data").
  Future<void> clearAllLocalData() async {
    await _db.deleteAllData();
    await _prefs.clearAll();
  }

  /// Snapshot of granted permissions for the Privacy screen.
  Future<PermissionSnapshot> permissionSnapshot() async {
    final p = PermissionService.instance;
    return PermissionSnapshot(
      media: await p.mediaGranted(),
      notifications: await p.notificationsGranted(),
      allFiles: await p.allFilesGranted(),
    );
  }
}

class PermissionSnapshot {
  const PermissionSnapshot({
    required this.media,
    required this.notifications,
    required this.allFiles,
  });

  final bool media;
  final bool notifications;
  final bool allFiles;
}
