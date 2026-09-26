/// App-wide constants for DRS Video.
library;

class AppConstants {
  AppConstants._();

  static const String appName = 'DRS Video';
  static const String appVersion = '1.0.0';

  static const String dbName = 'drs_video.db';
  static const int dbVersion = 1;

  /// Android MethodChannel used by MainActivity (Kotlin).
  static const String nativeChannel = 'drs.video/native';

  /// Seek step used by double-tap gestures and seek buttons (ms).
  static const int seekStepMs = 10000;

  /// Frame-step approximation for frame-by-frame seeking (ms).
  static const int frameStepMs = 42;

  /// Auto-hide delay for player controls.
  static const Duration controlsHideDelay = Duration(seconds: 3);

  /// How often playback position is persisted while playing.
  static const Duration progressSaveInterval = Duration(seconds: 5);

  /// Minimum watched position before it is stored as resumable.
  static const int minResumablePositionMs = 5000;

  /// Speed presets offered in the player.
  static const List<double> speedPresets = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0];

  /// Sleep timer presets in minutes.
  static const List<int> sleepTimerPresets = [5, 10, 15, 30, 45, 60];

  static const List<String> videoExtensions = [
    'mp4', 'mkv', 'webm', 'avi', 'mov', 'm4v', '3gp', 'ts', 'mpg', 'mpeg', 'flv', 'wmv', 'ogv',
  ];

  static const List<String> subtitleExtensions = ['srt', 'vtt'];

  static const List<String> playlistExportExtension = ['json'];

  /// Thumbnail cache upper bound (bytes) before automatic cleanup.
  static const int maxThumbnailCacheBytes = 100 * 1024 * 1024;

  /// Default maximum concurrent downloads.
  static const int defaultMaxConcurrentDownloads = 2;

  /// Absolute cap for concurrent native download tasks.
  static const int hardMaxConcurrentDownloads = 4;

  /// Progress-bar height used in cards.
  static const double cardProgressHeight = 3.0;
}

/// Storage keys used by [PreferencesService].
class PrefKeys {
  PrefKeys._();

  static const themeMode = 'theme_mode';
  static const dynamicColor = 'dynamic_color';
  static const animationsEnabled = 'animations_enabled';
  static const layoutMode = 'layout_mode';
  static const languageCode = 'language_code';

  static const defaultQuality = 'default_quality';
  static const defaultSpeed = 'default_speed';
  static const autoPlayNext = 'auto_play_next';
  static const alwaysResume = 'always_resume';
  static const enablePip = 'enable_pip';
  static const autoPip = 'auto_pip';
  static const backgroundPlayback = 'background_playback';
  static const preferFullscreen = 'prefer_fullscreen';

  static const downloadDir = 'download_dir';
  static const maxConcurrentDownloads = 'max_concurrent_downloads';
  static const wifiOnlyDownloads = 'wifi_only_downloads';
  static const notifyDownloadDone = 'notify_download_done';
  static const notifyDownloadError = 'notify_download_error';
  static const notifyStorageWarning = 'notify_storage_warning';

  static const historyEnabled = 'history_enabled';
  static const firstRunDone = 'first_run_done';

  static const maxThumbnailCacheMb = 'max_thumbnail_cache_mb';
}

/// Download priority values.
enum DownloadPriority { high, normal, low }

/// Connection quality levels used by the playback optimizer.
enum NetworkLevel { offline, verySlow, slow, medium, fast }
