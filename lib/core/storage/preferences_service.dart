import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../utils/logger.dart';

/// Typed wrapper over SharedPreferences for every app setting.
class PreferencesService {
  PreferencesService(this._prefs);

  final SharedPreferences _prefs;

  /// Direct access for framework glue (theme controller).
  SharedPreferences get raw => _prefs;

  // ---- downloads v2 / cloud backup (v1.8.0) ------------------------------

  bool get autoResumeOnWifi => _prefs.getBool(PrefKeys.autoResumeOnWifi) ?? true;
  set autoResumeOnWifi(bool v) => _prefs.setBool(PrefKeys.autoResumeOnWifi, v);

  String? get cloudBackupConfigRaw => _prefs.getString(PrefKeys.cloudBackupConfig);
  set cloudBackupConfigRaw(String? v) => v == null
      ? _prefs.remove(PrefKeys.cloudBackupConfig)
      : _prefs.setString(PrefKeys.cloudBackupConfig, v);

  bool get cloudBackupEnabled =>
      _prefs.getBool(PrefKeys.cloudBackupEnabled) ?? false;
  set cloudBackupEnabled(bool v) =>
      _prefs.setBool(PrefKeys.cloudBackupEnabled, v);

  DateTime? get cloudBackupLastAt {
    final ms = _prefs.getInt(PrefKeys.cloudBackupLastAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  set cloudBackupLastAt(DateTime? v) => v == null
      ? _prefs.remove(PrefKeys.cloudBackupLastAt)
      : _prefs.setInt(PrefKeys.cloudBackupLastAt, v.millisecondsSinceEpoch);

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

  /// In-app draggable floating video window (v1.3.0): when the player
  /// screen is closed while playing, the video shrinks into a small
  /// draggable window that keeps playing (YouTube/TikTok style).
  bool get enableFloatingPlayer => _prefs.getBool(PrefKeys.enableFloatingPlayer) ?? true;
  set enableFloatingPlayer(bool v) =>
      _prefs.setBool(PrefKeys.enableFloatingPlayer, v);

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

  // ---- built-in browser + protection (v1.4.0) ----

  /// In-browser ad/tracker blocking (bundled StevenBlack domains).
  bool get adBlockEnabled => _prefs.getBool(PrefKeys.adBlockEnabled) ?? true;
  set adBlockEnabled(bool v) => _prefs.setBool(PrefKeys.adBlockEnabled, v);

  /// When true the browser records NO history and no watch hand-offs.
  bool get browserIncognito => _prefs.getBool(PrefKeys.browserIncognito) ?? false;
  set browserIncognito(bool v) => _prefs.setBool(PrefKeys.browserIncognito, v);

  /// Desktop user-agent toggle (full web layouts of platforms).
  bool get browserDesktopUa => _prefs.getBool(PrefKeys.browserDesktopUa) ?? false;
  set browserDesktopUa(bool v) => _prefs.setBool(PrefKeys.browserDesktopUa, v);

  /// Lifetime count of ad/tracker requests blocked inside the browser.
  int get blockedRequestsCount => _prefs.getInt(PrefKeys.blockedRequestsCount) ?? 0;
  set blockedRequestsCount(int v) => _prefs.setInt(PrefKeys.blockedRequestsCount, v);

  /// Remember the last free-VPN server and offer one-tap reconnect.
  bool get vpnAutoReconnect => _prefs.getBool(PrefKeys.vpnAutoReconnect) ?? false;
  set vpnAutoReconnect(bool v) => _prefs.setBool(PrefKeys.vpnAutoReconnect, v);

  /// Serialized JSON of the last VPN server (VPNGate row or imported
  /// config) so the protection screen can offer one-tap reconnect.
  String? get vpnLastServer => _prefs.getString(PrefKeys.vpnLastServer);
  set vpnLastServer(String? v) =>
      v == null ? _prefs.remove(PrefKeys.vpnLastServer) : _prefs.setString(PrefKeys.vpnLastServer, v);

  // ---- app lock (v1.9.0) ---------------------------------------------------

  /// Salted PIN hash in the `<salt>:<hash>` form — the PIN itself is
  /// never persisted. null = no lock configured.
  String? get appLockHash => _prefs.getString(PrefKeys.appLockHash);
  set appLockHash(String? v) => v == null
      ? _prefs.remove(PrefKeys.appLockHash)
      : _prefs.setString(PrefKeys.appLockHash, v);

  /// Re-lock delay id ('immediate' | '1m' | '5m').
  String? get appLockDelayId => _prefs.getString(PrefKeys.appLockDelay);
  set appLockDelayId(String? v) => v == null
      ? _prefs.remove(PrefKeys.appLockDelay)
      : _prefs.setString(PrefKeys.appLockDelay, v);

  // ---- player power tools (v1.9.0) -----------------------------------------

  /// Persisted A-B loop markers as 'aMs:bMs' (empty when unset).
  String? get playerAbLoop => _prefs.getString(PrefKeys.playerAbLoop);
  set playerAbLoop(String? v) => v == null
      ? _prefs.remove(PrefKeys.playerAbLoop)
      : _prefs.setString(PrefKeys.playerAbLoop, v);

  /// Default audio preset id (AudioPreset.name).
  String? get audioPresetId => _prefs.getString(PrefKeys.audioPreset);
  set audioPresetId(String? v) => v == null
      ? _prefs.remove(PrefKeys.audioPreset)
      : _prefs.setString(PrefKeys.audioPreset, v);

  /// Default audio boost in dB (0..15).
  double get audioBoostDb => _prefs.getDouble(PrefKeys.audioBoostDb) ?? 0.0;
  set audioBoostDb(double v) => _prefs.setDouble(
      PrefKeys.audioBoostDb, v.clamp(0.0, AppConstants.maxAudioBoostDb).toDouble());

  // ---- private vault + subtitles (v1.10.0) --------------------------------

  /// Salted vault PIN hash `<salt>:<hash>` — independent from the app
  /// lock. null = no vault PIN configured.
  String? get vaultHash => _prefs.getString(PrefKeys.vaultHash);
  set vaultHash(String? v) => v == null
      ? _prefs.remove(PrefKeys.vaultHash)
      : _prefs.setString(PrefKeys.vaultHash, v);

  /// Persisted subtitle delay (seconds, may be negative) for [itemId].
  double? subtitleDelayFor(String itemId) {
    final v = _prefs.getDouble('${PrefKeys.subDelayPrefix}$itemId');
    return v;
  }

  Future<void> setSubtitleDelayFor(String itemId, double seconds) =>
      _prefs.setDouble(
          '${PrefKeys.subDelayPrefix}$itemId', seconds.clamp(-60.0, 60.0));

  Future<void> clearSubtitleDelayFor(String itemId) =>
      _prefs.remove('${PrefKeys.subDelayPrefix}$itemId');

  /// Audio-only default: start playback with video decoding disabled.
  bool get audioOnlyDefault => _prefs.getBool(PrefKeys.audioOnlyDefault) ?? false;
  set audioOnlyDefault(bool v) => _prefs.setBool(PrefKeys.audioOnlyDefault, v);

  // ---- updates + GitHub + smart playback (v1.12.0) -------------------------

  /// Auto-check GitHub Releases on startup.
  bool get updateAutoCheck => _prefs.getBool(PrefKeys.updateAutoCheck) ?? true;
  set updateAutoCheck(bool v) => _prefs.setBool(PrefKeys.updateAutoCheck, v);

  /// Attach YouTube captions automatically when available.
  bool get autoSubtitles => _prefs.getBool(PrefKeys.autoSubtitles) ?? true;
  set autoSubtitles(bool v) => _prefs.setBool(PrefKeys.autoSubtitles, v);

  /// Auto-load a same-folder subtitle file for local videos.
  bool get autoSiblingSubs => _prefs.getBool(PrefKeys.autoSiblingSubs) ?? true;
  set autoSiblingSubs(bool v) => _prefs.setBool(PrefKeys.autoSiblingSubs, v);

  /// Auto audio-only when battery is low and unplugged.
  bool get batterySaver => _prefs.getBool(PrefKeys.batterySaver) ?? false;
  set batterySaver(bool v) => _prefs.setBool(PrefKeys.batterySaver, v);

  /// Cap stream quality to reduce data usage.
  bool get dataSaver => _prefs.getBool(PrefKeys.dataSaver) ?? false;
  set dataSaver(bool v) => _prefs.setBool(PrefKeys.dataSaver, v);

  /// Per-item bookmarks (JSON list of {ms,label}).
  String? bookmarksRawFor(String itemId) =>
      _prefs.getString('${PrefKeys.bookmarkPrefix}$itemId');
  Future<void> setBookmarksRawFor(String itemId, String raw) =>
      _prefs.setString('${PrefKeys.bookmarkPrefix}$itemId', raw);

  /// Per-folder intro end marker (ms). null = not set.
  int? introEndFor(String folderKey) =>
      _prefs.getInt('${PrefKeys.introEndPrefix}$folderKey');
  Future<void> setIntroEndFor(String folderKey, int ms) =>
      _prefs.setInt('${PrefKeys.introEndPrefix}$folderKey', ms);
  Future<void> clearIntroEndFor(String folderKey) =>
      _prefs.remove('${PrefKeys.introEndPrefix}$folderKey');

  /// v1.14.7: cross-session failure chain per download task (int). Bumped
  /// on every FINAL failure produced by automatic recovery alone; at the
  /// ceiling the task is parked (manual retry resets it).
  int downloadFailChain(String taskId) =>
      _prefs.getInt('${PrefKeys.downloadFailChainPrefix}$taskId') ?? 0;
  Future<void> setDownloadFailChain(String taskId, int chain) =>
      _prefs.setInt('${PrefKeys.downloadFailChainPrefix}$taskId', chain);

  // ---- translation + picture calibration (v1.13.0) -------------------------

  /// Target language for subtitle auto-translation (default Arabic).
  String get translateTargetLang =>
      _prefs.getString(PrefKeys.translateTargetLang) ?? 'ar';
  set translateTargetLang(String v) =>
      _prefs.setString(PrefKeys.translateTargetLang, v);

  /// Auto-translate YouTube captions right after auto-attach.
  bool get autoTranslateSubs =>
      _prefs.getBool(PrefKeys.autoTranslateSubs) ?? true;
  set autoTranslateSubs(bool v) => _prefs.setBool(PrefKeys.autoTranslateSubs, v);

  /// Persisted picture calibration (VideoEq JSON string).
  String? get videoEqRaw => _prefs.getString(PrefKeys.videoEq);
  Future<void> setVideoEq(String raw) => _prefs.setString(PrefKeys.videoEq, raw);

  /// Persisted video rotation degrees.
  int get videoRotate => _prefs.getInt(PrefKeys.videoRotate) ?? 0;
  Future<void> setVideoRotate(int deg) =>
      _prefs.setInt(PrefKeys.videoRotate, deg);

  Future<void> clearAll() => _prefs.clear();

  // ---- backup snapshot (v1.7.0) ------------------------------------------

  /// Keys excluded from backup: device/session state that should never be
  /// transplanted onto another installation.
  static const _backupExcludedKeys = <String>{
    PrefKeys.firstRunDone,
    PrefKeys.blockedRequestsCount,
  };

  /// A typed snapshot of every stored preference (minus excluded keys).
  /// Values keep their runtime types so jsonEncode stays faithful.
  Map<String, Object?> exportSnapshot() {
    final out = <String, Object?>{};
    for (final key in _prefs.getKeys()) {
      if (_backupExcludedKeys.contains(key)) continue;
      final v = _prefs.get(key);
      if (v != null) out[key] = v;
    }
    return out;
  }

  /// Applies a snapshot produced by [exportSnapshot]. Unknown keys are
  /// written as-is (forward compatible), values must match a supported
  /// type. Returns how many keys were actually written.
  Future<int> applySnapshot(Map<String, Object?> data) async {
    var applied = 0;
    for (final entry in data.entries) {
      final v = entry.value;
      try {
        if (v is String) {
          await _prefs.setString(entry.key, v);
        } else if (v is int) {
          await _prefs.setInt(entry.key, v);
        } else if (v is bool) {
          await _prefs.setBool(entry.key, v);
        } else if (v is double) {
          await _prefs.setDouble(entry.key, v);
        } else if (v is List) {
          await _prefs.setStringList(
              entry.key, v.whereType<String>().toList());
        } else {
          continue;
        }
        applied++;
      } catch (e) {
        AppLogger.instance.warning('prefs', 'snapshot key ${entry.key} skipped: $e');
      }
    }
    return applied;
  }
}
