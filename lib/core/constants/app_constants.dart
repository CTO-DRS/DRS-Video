/// App-wide constants for DRS Video.
library;

class AppConstants {
  AppConstants._();

  static const String appName = 'DRS Video';
  static const String appVersion = '1.13.0';

  static const String dbName = 'drs_video.db';
  static const int dbVersion = 5;

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

  /// Maximum software audio boost (dB) surfaced in the player sheet.
  static const double maxAudioBoostDb = 15;

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

  // ---- Streaming platforms (v1.2.x) ----

  /// source_id tag stored on direct stream links in media_items.
  static const String streamSourceLink = 'link';

  /// source_id prefix for IPTV channels: `iptv:<playlistId>`.
  static const String streamSourceIptv = 'iptv:';

  /// source_id prefix for NAS files: `nas:<serverId>`.
  static const String streamSourceNas = 'nas:';

  static const int ftpDefaultPort = 21;
  static const int sftpDefaultPort = 22;
  static const int webdavDefaultPort = 80;
  static const int webdavTlsDefaultPort = 443;

  /// Connection timeout for NAS/IPTV network operations.
  static const Duration nasConnectTimeout = Duration(seconds: 15);

  /// Chunk size used by the SFTP streaming proxy when bridging HTTP Range
  /// requests to offset reads.
  static const int streamChunkBytes = 256 * 1024;

  /// HLS bitrate caps (kbps) offered in the stream quality sheet.
  static const List<int> hlsQualityCapsKbps = [800, 1500, 3000, 6000, 12000, 25000];

  /// URI schemes accepted when saving a direct stream link.
  static const List<String> streamUrlSchemes = [
    'http', 'https', 'rtsp', 'rtmp', 'rtmps', 'ftp', 'ftps',
  ];

  /// URI schemes accepted from incoming share/view intents (v1.3.0).
  static const List<String> intentUrlSchemes = [
    'http', 'https', 'rtsp', 'rtmp', 'rtmps', 'mms', 'ftp', 'ftps', 'sftp',
  ];

  // ---- Floating window (v1.3.0) ----

  /// Floating video window: width = screen width fraction, clamped.
  static const double floatingWindowWidthFraction = 0.45;
  static const double floatingWindowMinWidth = 170.0;
  static const double floatingWindowMaxWidth = 300.0;
  static const double floatingWindowEdgeMargin = 8.0;

  /// Timeout used when resolving a YouTube title during smart-link save.
  static const Duration youtubeTitleTimeout = Duration(seconds: 6);

  // ---- Built-in platform browser (v1.4.0) ----

  /// Blocklist asset bundled for in-browser ad/tracker blocking
  /// (one real domain per line, StevenBlack unified list).
  static const String adBlockAsset = 'assets/blocklists/ad_domains.txt';

  /// Bundled real-platforms catalog asset (v1.4.0).
  static const String sitesCatalogAsset = 'assets/sites/catalog.json';

  /// GitHub project coordinates (v1.12.0 in-app updates + hub).
  static const String githubRepo = 'CTO-DRS/DRS-Video';
  static const String githubRepoUrl = 'https://github.com/$githubRepo';
  static const String githubReleasesUrl = '$githubRepoUrl/releases';
  static const String githubDeveloperUrl = 'https://github.com/CTO-DRS';

  /// User-Agent for the built-in browser. Desktop UA unlocks the full
  /// web versions of platforms (YouTube/TikTok desktop layouts).
  static const String browserDesktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// Default (mobile) UA keeps Android behavior of the sites.
  static const String browserMobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  /// File extensions considered a playable video/stream when detected
  /// inside the browser (shown in the "open in player" sheet).
  static const List<String> streamFileExtensions = [
    'm3u8', 'mpd', 'mp4', 'm4v', 'mkv', 'webm', 'ts', 'mov', 'flv', '3gp',
  ];

  /// Maximum number of browser history rows kept in SQLite.
  static const int browserHistoryCap = 500;

  /// Maximum number of detected streams remembered per browser page.
  static const int browserDetectedStreamsCap = 12;

  // ---- Free VPN (v1.4.0) ----

  /// VPNGate public API (University of Tsukuba project). Free OpenVPN
  /// servers, no registration. Configs are decoded from the CSV itself.
  static const String vpngateApiUrl = 'https://www.vpngate.net/api/iphone/';

  /// Timeout for fetching/refreshing the free server list.
  static const Duration vpngateFetchTimeout = Duration(seconds: 30);

  /// Only servers at/above this speed (bits/sec) are offered by default.
  static const int vpngateMinSpeedBps = 1000000;
}

/// NAS transport protocols.
enum NasProtocol { webdav, ftp, sftp }

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
  static const enableFloatingPlayer = 'enable_floating_player';
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

  // ---- Built-in browser + protection (v1.4.0) ----
  static const adBlockEnabled = 'ad_block_enabled';
  static const browserIncognito = 'browser_incognito';
  static const browserDesktopUa = 'browser_desktop_ua';
  static const blockedRequestsCount = 'blocked_requests_count';
  static const vpnAutoReconnect = 'vpn_auto_reconnect';
  static const vpnLastServer = 'vpn_last_server';

  /// Library sort key + direction persistence (v1.7.0).
  static const librarySort = 'library_sort';
  static const librarySortDirection = 'library_sort_direction';

  /// Downloads v2 (v1.8.0): resume paused downloads automatically when
  /// WiFi returns (user-paused ones stay paused for the session).
  static const autoResumeOnWifi = 'auto_resume_on_wifi';

  /// Cloud backup (v1.8.0): config JSON, enable toggle, last upload time.
  static const cloudBackupConfig = 'cloud_backup_config';
  static const cloudBackupEnabled = 'cloud_backup_enabled';
  static const cloudBackupLastAt = 'cloud_backup_last_at';

  /// App lock (v1.9.0): salted PIN hash `<salt>:<hash>` and the re-lock
  /// delay id. The PIN itself is never stored.
  static const appLockHash = 'app_lock_hash';
  static const appLockDelay = 'app_lock_delay';

  /// Player power tools (v1.9.0): persisted A-B loop markers and audio
  /// enhancement defaults (preset id + boost dB).
  static const playerAbLoop = 'player_ab_loop';
  static const audioPreset = 'audio_preset';
  static const audioBoostDb = 'audio_boost_db';

  /// Private vault (v1.10.0): separate salted PIN hash for the hidden
  /// media vault — independent from the app lock PIN. PIN never stored.
  static const vaultHash = 'vault_hash';

  /// Per-media subtitle sync delay in seconds ('<itemId>' -> double).
  static const subDelayPrefix = 'sub_delay_';

  /// Audio-only default (v1.10.0): when true, playback starts with video
  /// decoding disabled (battery/data saver).
  static const audioOnlyDefault = 'audio_only_default';

  // ---- v1.12.0: updates + GitHub + smart playback -------------------------

  /// Auto-check GitHub Releases on app start (update screen tile).
  static const updateAutoCheck = 'update_auto_check';

  /// Attach YouTube captions automatically when the app resolves a video.
  static const autoSubtitles = 'auto_subtitles';

  /// Auto-load a same-folder subtitle file for local videos.
  static const autoSiblingSubs = 'auto_sibling_subs';

  /// Auto switch to audio-only when battery is low and unplugged.
  static const batterySaver = 'battery_saver';

  /// Cap stream quality (HLS/DASH) to reduce data usage.
  static const dataSaver = 'data_saver';

  /// Per-item video bookmarks: JSON list of {ms,label}.
  static const bookmarkPrefix = 'bookmarks_';

  /// Per-folder intro end marker (ms): 'intro_end_' + folderKey.
  static const introEndPrefix = 'intro_end_';

  // ---- v1.13.0: translation + picture calibration -------------------------

  /// Target language for subtitle auto-translation (ISO code, default ar).
  static const translateTargetLang = 'translate_target_lang';

  /// Auto-translate YouTube captions after auto-attach (background swap).
  static const autoTranslateSubs = 'auto_translate_subs';

  /// Persisted video picture calibration (VideoEq JSON).
  static const videoEq = 'video_eq';

  /// Persisted video rotation in degrees (0/90/180/270).
  static const videoRotate = 'video_rotate';
}

/// Download priority values.
enum DownloadPriority { high, normal, low }

/// Connection quality levels used by the playback optimizer.
enum NetworkLevel { offline, verySlow, slow, medium, fast }
