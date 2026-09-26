import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Typed wrapper over SharedPreferences for every app setting.
class PreferencesService {
  PreferencesService(this._prefs);

  final SharedPreferences _prefs;

  /// Direct access for framework glue (theme controller).
  SharedPreferences get raw => _prefs;

  // ---- appearance ----
  bool get dynamicColor => _prefs.getBool(PrefKeys.dynamicColor) ?? true;
  bool get animations => _prefs.getBool(PrefKeys.animationsEnabled) ?? true;

  // ---- playback ----
  String get defaultQuality => _prefs.getString(PrefKeys.defaultQuality) ?? 'auto';
  set defaultQuality(String v) => _prefs.setString(PrefKeys.defaultQuality, v);

  double get defaultSpeed => _prefs.getDouble(PrefKeys.defaultSpeed) ?? 1.0;
  set defaultSpeed(double v) => _prefs.setDouble(PrefKeys.defaultSpeed, v);

  bool get autoPlayNext => _prefs.getBool(PrefKeys.autoPlayNext) ?? true;
  set autoPlayNext(bool v) => _prefs.setBool(PrefKeys.autoPlayNext, v);
  bool get alwaysResume => _prefs.getBool(PrefKeys.alwaysResume) ?? false;
  set alwaysResume(bool v) => _prefs.setBool(PrefKeys.alwaysResume, v);
  bool get enablePip => _prefs.getBool(PrefKeys.enablePip) ?? true;
  set enablePip(bool v) => _prefs.setBool(PrefKeys.enablePip, v);
  bool get autoPip => _prefs.getBool(PrefKeys.autoPip) ?? false;
  set autoPip(bool v) => _prefs.setBool(PrefKeys.autoPip, v);
  bool get backgroundPlayback => _prefs.getBool(PrefKeys.backgroundPlayback) ?? true;
  set backgroundPlayback(bool v) => _prefs.setBool(PrefKeys.backgroundPlayback, v);
  bool get preferFullscreen => _prefs.getBool(PrefKeys.preferFullscreen) ?? false;
  set preferFullscreen(bool v) => _prefs.setBool(PrefKeys.preferFullscreen, v);

  // ---- downloads ----
  String? get downloadDir => _prefs.getString(PrefKeys.downloadDir);
  set downloadDir(String? v) =>
      v == null ? _prefs.remove(PrefKeys.downloadDir) : _prefs.setString(PrefKeys.downloadDir, v);

  int get maxConcurrentDownloads =>
      _prefs.getInt(PrefKeys.maxConcurrentDownloads) ?? AppConstants.defaultMaxConcurrentDownloads;
  set maxConcurrentDownloads(int v) =>
      _prefs.setInt(PrefKeys.maxConcurrentDownloads, v.clamp(1, AppConstants.hardMaxConcurrentDownloads));

  bool get wifiOnlyDownloads => _prefs.getBool(PrefKeys.wifiOnlyDownloads) ?? false;
  set wifiOnlyDownloads(bool v) => _prefs.setBool(PrefKeys.wifiOnlyDownloads, v);
  bool get notifyDownloadDone => _prefs.getBool(PrefKeys.notifyDownloadDone) ?? true;
  set notifyDownloadDone(bool v) => _prefs.setBool(PrefKeys.notifyDownloadDone, v);
  bool get notifyDownloadError => _prefs.getBool(PrefKeys.notifyDownloadError) ?? true;
  set notifyDownloadError(bool v) => _prefs.setBool(PrefKeys.notifyDownloadError, v);
  bool get notifyStorageWarning => _prefs.getBool(PrefKeys.notifyStorageWarning) ?? true;
  set notifyStorageWarning(bool v) => _prefs.setBool(PrefKeys.notifyStorageWarning, v);

  // ---- privacy / system ----
  bool get historyEnabled => _prefs.getBool(PrefKeys.historyEnabled) ?? true;
  set historyEnabled(bool v) => _prefs.setBool(PrefKeys.historyEnabled, v);

  bool get firstRunDone => _prefs.getBool(PrefKeys.firstRunDone) ?? false;
  set firstRunDone(bool v) => _prefs.setBool(PrefKeys.firstRunDone, v);

  int get maxThumbnailCacheMb =>
      _prefs.getInt(PrefKeys.maxThumbnailCacheMb) ?? (AppConstants.maxThumbnailCacheBytes ~/ (1024 * 1024));

  Future<void> clearAll() => _prefs.clear();
}
