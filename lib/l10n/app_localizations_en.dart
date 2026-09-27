// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'DRS Video';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get details => 'Details';

  @override
  String get share => 'Share';

  @override
  String get rename => 'Rename';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get open => 'Open';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get resumeAction => 'Resume';

  @override
  String get stop => 'Stop';

  @override
  String get done => 'Done';

  @override
  String get next => 'Next';

  @override
  String get previous => 'Previous';

  @override
  String get continueWord => 'Continue';

  @override
  String get search => 'Search';

  @override
  String get filter => 'Filter';

  @override
  String get sort => 'Sort';

  @override
  String get clear => 'Clear';

  @override
  String get loading => 'Loading…';

  @override
  String get error => 'Error';

  @override
  String get offline => 'You are offline';

  @override
  String get online => 'Online';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get refresh => 'Refresh';

  @override
  String get selectAll => 'Select all';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String itemsSelected(int count) {
    return '$count selected';
  }

  @override
  String get deleteConfirmTitle => 'Confirm delete';

  @override
  String deleteItemsMessage(int count) {
    return 'Permanently delete $count item(s)?';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Library';

  @override
  String get navPlaylists => 'Playlists';

  @override
  String get navDownloads => 'Downloads';

  @override
  String get navSettings => 'Settings';

  @override
  String get homeSearchHint => 'Search library, downloads and files…';

  @override
  String get homeContinueWatching => 'Continue watching';

  @override
  String get homeRecent => 'Recently added';

  @override
  String get homeFavorites => 'Favorites';

  @override
  String get homeRecommended => 'Recommended for you';

  @override
  String get homeDownloads => 'Downloads';

  @override
  String get homePlaylists => 'Playlists';

  @override
  String get homeSources => 'Sources';

  @override
  String get homeLocalFiles => 'Local files';

  @override
  String get homeQuickActions => 'Quick actions';

  @override
  String get homeOpenUrl => 'Open video URL';

  @override
  String get homeOpenFile => 'Open video file';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get emptyGenericTitle => 'Nothing here yet';

  @override
  String get emptyLibraryTitle => 'Your library is empty';

  @override
  String get emptyLibraryBody => 'Add a link or a local file to get started.';

  @override
  String get emptyFavoritesTitle => 'No favorites yet';

  @override
  String get emptyFavoritesBody => 'Mark videos as favorite to find them here.';

  @override
  String get emptyDownloadsTitle => 'No downloads yet';

  @override
  String get emptyDownloadsBody =>
      'Open a video URL and tap the download button to start.';

  @override
  String get emptyPlaylistsTitle => 'No playlists yet';

  @override
  String get emptyPlaylistsBody => 'Create a playlist to organize your videos.';

  @override
  String get emptyHistoryTitle => 'No watch history';

  @override
  String get emptyHistoryBody => 'Videos you watch will appear here.';

  @override
  String get emptyLocalFilesTitle => 'No local files';

  @override
  String get emptyLocalFilesBody =>
      'No videos found on this device, or permission not granted yet.';

  @override
  String get emptySearchTitle => 'No results';

  @override
  String get emptySearchBody => 'Try different keywords or adjust filters.';

  @override
  String get emptyContinueTitle => 'Nothing in progress';

  @override
  String get emptyContinueBody =>
      'Start watching a video and resume it from here later.';

  @override
  String get actionPlayFromStart => 'Play from start';

  @override
  String get actionAddToPlaylist => 'Add to playlist';

  @override
  String get actionRemoveFromPlaylist => 'Remove from playlist';

  @override
  String get actionFavorite => 'Add to favorites';

  @override
  String get actionUnfavorite => 'Remove from favorites';

  @override
  String get actionShareLink => 'Share link';

  @override
  String get actionShareFile => 'Share file';

  @override
  String get actionCopyLink => 'Copy link';

  @override
  String get actionOpenWith => 'Open with';

  @override
  String get actionFileInfo => 'File info';

  @override
  String get actionDownload => 'Download';

  @override
  String get actionNewPlaylist => 'New playlist';

  @override
  String get actionExport => 'Export';

  @override
  String get actionImport => 'Import';

  @override
  String get playerQuality => 'Quality';

  @override
  String get playerSpeed => 'Speed';

  @override
  String get playerAudioTrack => 'Audio track';

  @override
  String get playerSubtitleTrack => 'Subtitles';

  @override
  String get playerAddSubtitle => 'Add subtitle file';

  @override
  String get playerSleepTimer => 'Sleep timer';

  @override
  String get playerOff => 'Off';

  @override
  String get playerEndOfVideo => 'End of video';

  @override
  String playerMinutes(int count) {
    return '$count minutes';
  }

  @override
  String get playerPiP => 'Picture-in-Picture';

  @override
  String get playerLock => 'Lock controls';

  @override
  String get playerUnlock => 'Unlock controls';

  @override
  String get playerFullscreen => 'Fullscreen';

  @override
  String get playerAuto => 'Auto';

  @override
  String get playerSingleQuality => 'This source provides a single quality';

  @override
  String get playerNoAudioTracks => 'No alternative audio tracks';

  @override
  String get playerNoSubtitleTracks =>
      'No subtitles — you can add a subtitle file';

  @override
  String get playerExternalSubtitle => 'External file';

  @override
  String get playerSubLoaded => 'Subtitle file loaded';

  @override
  String get playerSubInvalid => 'Subtitle file is invalid or empty';

  @override
  String get playerBuffering => 'Buffering…';

  @override
  String get playerErrorTitle => 'Cannot play this video';

  @override
  String get playerErrorNetwork =>
      'Could not reach the source. Check your connection and the URL.';

  @override
  String get playerErrorTimeout => 'The source took too long to respond.';

  @override
  String get playerErrorUnsupported =>
      'This video format is not supported on this device.';

  @override
  String get playerErrorCorrupted =>
      'The file appears to be corrupted or incomplete.';

  @override
  String get playerErrorNotFound => 'The file or URL was not found (404).';

  @override
  String get playerErrorForbidden =>
      'The source blocks playback from outside its site.';

  @override
  String get playerErrorUnknown =>
      'An unexpected error occurred during playback.';

  @override
  String get openInBrowser => 'Open in built-in browser';

  @override
  String get openExternal => 'Open in external browser';

  @override
  String get openExternalUnavailable =>
      'No external browser is installed on this device';

  @override
  String get browserLoadFailed =>
      'Couldn\'t load this page. Check your connection or try an external browser.';

  @override
  String playerResumeFrom(String time) {
    return 'Resume from $time?';
  }

  @override
  String get playerStartOver => 'Start over';

  @override
  String get playerBrightness => 'Brightness';

  @override
  String get playerVolume => 'Volume';

  @override
  String get playerFrameStepHint => 'Frame step';

  @override
  String get playerSkipIntro => 'Skip intro';

  @override
  String get playerSkipOutro => 'Skip outro';

  @override
  String get playerNextVideo => 'Next video';

  @override
  String get playerPrevVideo => 'Previous video';

  @override
  String get playerCompleted => 'Playback finished';

  @override
  String get downloadsActive => 'Active';

  @override
  String get downloadsQueued => 'Queued';

  @override
  String get downloadsCompleted => 'Completed';

  @override
  String get downloadsFailed => 'Failed';

  @override
  String get downloadsPauseAll => 'Pause all';

  @override
  String get downloadsResumeAll => 'Resume all';

  @override
  String get downloadsPriority => 'Priority';

  @override
  String get downloadsPriorityHigh => 'High';

  @override
  String get downloadsPriorityNormal => 'Normal';

  @override
  String get downloadsPriorityLow => 'Low';

  @override
  String downloadsFreeSpace(String size) {
    return 'Free space: $size';
  }

  @override
  String get downloadsCorruptedFile =>
      'The file looks incomplete — retry to repair it.';

  @override
  String get downloadStarted => 'Download started';

  @override
  String get downloadCompletedNotif => 'Download completed';

  @override
  String get downloadFailedNotif => 'Download failed';

  @override
  String get downloadsWifiOnlyWarning =>
      'Wi-Fi-only downloads is on — waiting for Wi-Fi.';

  @override
  String get downloadsInsufficientSpace => 'Not enough storage space.';

  @override
  String get downloadsServerNoResume =>
      'Server does not support resume; it will restart when resumed.';

  @override
  String get libraryAll => 'All';

  @override
  String get libraryFavorites => 'Favorites';

  @override
  String get libraryDownloads => 'Downloads';

  @override
  String get libraryRecent => 'Recent';

  @override
  String get libraryContinue => 'Continue';

  @override
  String get libraryLocal => 'Local';

  @override
  String get libraryHistory => 'History';

  @override
  String get librarySortBy => 'Sort by';

  @override
  String get sortName => 'Name';

  @override
  String get sortDateAdded => 'Date added';

  @override
  String get sortRecentlyPlayed => 'Last played';

  @override
  String get sortDuration => 'Duration';

  @override
  String get sortSize => 'Size';

  @override
  String get filterType => 'Type';

  @override
  String get filterSource => 'Source';

  @override
  String get filterDuration => 'Duration';

  @override
  String get filterFavoritesOnly => 'Favorites only';

  @override
  String get durationShort => 'Under 5 min';

  @override
  String get durationMedium => '5 – 20 min';

  @override
  String get durationLong => '20 – 60 min';

  @override
  String get durationVeryLong => 'Over an hour';

  @override
  String get typeAll => 'All';

  @override
  String get typeLocal => 'Local file';

  @override
  String get typeNetwork => 'Link';

  @override
  String get typeDownload => 'Download';

  @override
  String get multiSelectTitle => 'Multi-select';

  @override
  String playlistsCount(int count) {
    return '$count videos';
  }

  @override
  String get playlistNameHint => 'Playlist name';

  @override
  String get playlistPlayAll => 'Play playlist';

  @override
  String get playlistShuffle => 'Shuffle';

  @override
  String get playlistRepeat => 'Repeat';

  @override
  String get repeatOff => 'No repeat';

  @override
  String get repeatAll => 'Repeat all';

  @override
  String get repeatOne => 'Repeat one';

  @override
  String get playlistReorderHint => 'Drag to reorder';

  @override
  String get playlistExported => 'Playlist exported for sharing';

  @override
  String get playlistImported => 'Playlist imported';

  @override
  String get playlistInvalidFile => 'Invalid playlist file';

  @override
  String get playlistPickVideos => 'Pick videos to add';

  @override
  String get searchHint => 'Search by title or source…';

  @override
  String get searchSuggestions => 'Suggestions';

  @override
  String get searchRecentQueries => 'Recent searches';

  @override
  String get searchResults => 'Results';

  @override
  String get searchClearHistory => 'Clear search history';

  @override
  String get sourcesTitle => 'Sources';

  @override
  String get sourcesLocalAdapter => 'Local files';

  @override
  String get sourcesLocalAdapterDesc => 'On-device videos via MediaStore';

  @override
  String get sourcesDirectAdapter => 'Direct links';

  @override
  String get sourcesDirectAdapterDesc =>
      'MP4 / MKV / WebM files and direct HLS links';

  @override
  String get sourcesAddTitle => 'Add source';

  @override
  String get sourcesNameHint => 'Source name';

  @override
  String get sourcesBaseUrlHint => 'Source base URL (https://…)';

  @override
  String get sourcesHeaderHint =>
      'Optional header (e.g. Authorization: Bearer …)';

  @override
  String get sourcesTest => 'Test connection';

  @override
  String get sourcesTestOk => 'Connection OK';

  @override
  String get sourcesTestFail => 'Connection failed';

  @override
  String get sourcesEnabled => 'Enabled';

  @override
  String get sourcesDisabled => 'Disabled';

  @override
  String get sourcesDeleteWarn =>
      'Only the source is removed; saved videos are kept.';

  @override
  String get sourcesPrivacyNote =>
      'The app never bypasses platform protections; it only works with sources that officially allow direct access.';

  @override
  String get localFilesPermissionNeeded =>
      'Media permission is required to show on-device videos.';

  @override
  String get localFilesGrant => 'Grant permission';

  @override
  String get localFilesScanning => 'Scanning media…';

  @override
  String get fileInfoTitle => 'File info';

  @override
  String get fileInfoPath => 'Path';

  @override
  String get fileInfoSize => 'Size';

  @override
  String get fileInfoDuration => 'Duration';

  @override
  String get fileInfoAdded => 'Added';

  @override
  String get fileInfoLastPlayed => 'Last played';

  @override
  String get fileInfoTimesPlayed => 'Plays';

  @override
  String get settingsPlayback => 'Playback';

  @override
  String get settingsDownloads => 'Downloads';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsStorage => 'Storage';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsAbout => 'About';

  @override
  String get setDefaultQuality => 'Default quality';

  @override
  String get qualityAuto => 'Auto (based on connection)';

  @override
  String get qualityHigh => 'High';

  @override
  String get qualityMedium => 'Medium';

  @override
  String get qualityLow => 'Data saver';

  @override
  String get setDefaultSpeed => 'Default playback speed';

  @override
  String get setAutoPlayNext => 'Autoplay next';

  @override
  String get setAutoPlayNextDesc =>
      'Start the next queued video when one finishes';

  @override
  String get setAlwaysResume => 'Always resume';

  @override
  String get setAlwaysResumeDesc => 'Resume from last position without asking';

  @override
  String get setPip => 'Picture-in-Picture';

  @override
  String get setPipDesc => 'Watch in a small window while navigating the app';

  @override
  String get setAutoPip => 'Auto PiP on exit';

  @override
  String get setAutoPipDesc =>
      'Switch to PiP when leaving the app (Android 12+)';

  @override
  String get setFloatingPlayer => 'In-app floating video window';

  @override
  String get setFloatingPlayerDesc =>
      'When you leave the player, the video keeps playing in a small draggable window (like YouTube and TikTok)';

  @override
  String get playerFloat => 'Minimize to floating window';

  @override
  String get shareOpenTitle => 'Open this video link?';

  @override
  String get shareOpenBody => 'The following link was shared with DRS Video:';

  @override
  String get sharePlayNow => 'Play now';

  @override
  String get shareSaveOnly => 'Save only';

  @override
  String get clipboardPaste => 'Play link from clipboard';

  @override
  String get platformsSupportedHint =>
      'Supports: direct links (mp4/mkv/...), HLS & DASH, RTSP/RTMP, FTP/SFTP, WebDAV, YouTube — and thousands of sites via share from any app';

  @override
  String get setBackground => 'Background playback';

  @override
  String get setBackgroundDesc =>
      'Keep audio with a media notification when minimized';

  @override
  String get setPreferFullscreen => 'Start in fullscreen';

  @override
  String get setDownloadFolder => 'Download folder';

  @override
  String get setDownloadFolderDesc =>
      'By default downloads go to the app\'s private folder — no permission needed';

  @override
  String get setUseCustomFolder => 'Choose custom folder';

  @override
  String get setCustomFolderNeedsAllFiles =>
      'A custom folder needs the \"All files access\" permission on Android 11+';

  @override
  String get setConcurrency => 'Concurrent downloads';

  @override
  String get setWifiOnly => 'Download over Wi-Fi only';

  @override
  String get setNotifyDone => 'Download complete notifications';

  @override
  String get setNotifyError => 'Download failure notifications';

  @override
  String get setNotifyStorage => 'Storage warnings';

  @override
  String get setThemeMode => 'Mode';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get setDynamicColor => 'Dynamic color';

  @override
  String get setDynamicColorDesc =>
      'Use system Material You palette on Android 12+';

  @override
  String get setAnimations => 'Animations';

  @override
  String get setLayout => 'Layout density';

  @override
  String get layoutCompact => 'Compact';

  @override
  String get layoutComfortable => 'Comfortable';

  @override
  String get setLanguage => 'Language';

  @override
  String get langSystem => 'System language';

  @override
  String get langArabic => 'العربية';

  @override
  String get langEnglish => 'English';

  @override
  String get storageThumbnails => 'Thumbnail cache';

  @override
  String get storageDownloadsSize => 'Downloads size';

  @override
  String get storageClearCache => 'Clear cache';

  @override
  String get storageCleared => 'Cleared';

  @override
  String get storageAnalyzer => 'Storage analyzer';

  @override
  String get storageLargestFiles => 'Largest files';

  @override
  String get storageOldestUnplayed => 'Oldest unplayed files';

  @override
  String get privacyHistoryEnabled => 'Watch history enabled';

  @override
  String get privacyHistoryDesc =>
      'Stored locally only, never sent to any server';

  @override
  String get privacyClearHistory => 'Clear watch history';

  @override
  String get privacyClearSearch => 'Clear search history';

  @override
  String get privacyClearAllData => 'Clear all local data';

  @override
  String get privacyClearAllConfirm =>
      'This deletes history, favorites, playlists and download records. Continue?';

  @override
  String get privacyLocalDataNote =>
      'All data (history, favorites, playlists) stays on your device only.';

  @override
  String get privacyPermissions => 'Permissions';

  @override
  String get privacyExportLogs => 'Export diagnostic logs';

  @override
  String get notifChannelDownloads => 'Downloads';

  @override
  String get notifChannelGeneral => 'General';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutLicenses => 'Open source licenses';

  @override
  String get aboutPrivacyPolicy => 'Privacy policy';

  @override
  String get aboutPrivacyBody =>
      'DRS Video collects no personal data and never sends your watch history to any server. Everything stays on your device. Network access is used only to play and download the content you choose.';

  @override
  String get aboutDescription =>
      'An advanced video player and library platform — no ads, no AI.';

  @override
  String get permNotificationTitle => 'Notifications permission';

  @override
  String get permNotificationDesc => 'Shows download progress and completion.';

  @override
  String get permMediaTitle => 'Media permission';

  @override
  String get permMediaDesc => 'Lists video files on your device.';

  @override
  String get permAllFilesTitle => 'All files access';

  @override
  String get permAllFilesDesc =>
      'Only needed to save downloads into a custom folder.';

  @override
  String get permOpenSettings => 'Open system settings';

  @override
  String get ob1Title => 'All your videos in one place';

  @override
  String get ob1Body =>
      'Library, favorites, playlists and history — organized locally on your device.';

  @override
  String get ob2Title => 'A professional player';

  @override
  String get ob2Body =>
      'Speed, subtitles, audio tracks, lock, PiP and gesture controls.';

  @override
  String get ob3Title => 'Real background downloads';

  @override
  String get ob3Body =>
      'Pause, resume and manage priorities — from sources that allow it.';

  @override
  String get obGetStarted => 'Get started';

  @override
  String get obSkip => 'Skip';

  @override
  String get openUrlTitle => 'Open video URL';

  @override
  String get openUrlHint => 'https://example.com/video.mp4';

  @override
  String get openUrlInvalid => 'Invalid URL — it must start with http/https';

  @override
  String get pickSubtitle => 'Pick a subtitle file (SRT / VTT)';

  @override
  String get renameTitle => 'Rename';

  @override
  String get reasonFavorite => 'From your favorites';

  @override
  String get reasonRecentlyPlayed => 'Recently played';

  @override
  String get reasonUnfinished => 'You didn\'t finish it';

  @override
  String reasonFromSource(String source) {
    return 'From $source';
  }

  @override
  String get reasonSimilarSource => 'Sources you like';

  @override
  String get updateThumb => 'Update';

  @override
  String get scanComplete => 'Scan complete';

  @override
  String get waiting => 'Waiting…';

  @override
  String get bootPreparing => 'Preparing the app…';

  @override
  String get bootStageCore => 'Preparing core services';

  @override
  String get bootStagePrefs => 'Loading settings';

  @override
  String get bootStageDatabase => 'Setting up the database';

  @override
  String get bootStageRepositories => 'Loading library and history';

  @override
  String get bootStageNotifications => 'Setting up notifications';

  @override
  String get bootStagePlayer => 'Preparing the playback engine';

  @override
  String get bootStageDownloads => 'Preparing the download manager';

  @override
  String get bootStageSources => 'Loading sources';

  @override
  String get bootSlow =>
      'Initialization is taking longer than usual. You can retry or keep waiting.';

  @override
  String get bootRetry => 'Retry';

  @override
  String get bootSafeMode => 'Safe mode';

  @override
  String get bootErrorTitle => 'The app could not start';

  @override
  String get bootErrorBody =>
      'An error occurred while starting the app. Try again, or start in safe mode with a reduced feature set.';

  @override
  String get bootErrorDetails => 'Technical details';

  @override
  String get bootErrorCopy => 'Copy details';

  @override
  String get bootErrorCopied => 'Details copied to clipboard';

  @override
  String get bootPrevCrashTitle =>
      'A problem was detected in the previous session';

  @override
  String get bootPrevCrashBody =>
      'The app did not close cleanly last time. You can copy the details below and share them so the cause can be fixed.';

  @override
  String get bootPrevCrashDetails => 'Crash details';

  @override
  String get setDiagnostics => 'Diagnostics & errors';

  @override
  String get diagDeviceSection => 'Device information';

  @override
  String get diagFactsApp => 'App';

  @override
  String get diagFactsDevice => 'Device';

  @override
  String get diagFactsAndroid => 'Android';

  @override
  String get diagFactsAbi => 'Architecture';

  @override
  String get diagFactsStorage => 'Storage';

  @override
  String get diagChecksSection => 'Service health checks';

  @override
  String get diagRunChecks => 'Run checks';

  @override
  String get diagStatusPass => 'OK';

  @override
  String get diagStatusDegraded => 'Degraded';

  @override
  String get diagStatusFail => 'Failed';

  @override
  String get diagCheckPrefs => 'Saved preferences';

  @override
  String get diagCheckDatabase => 'Database';

  @override
  String get diagCheckStorage => 'Internal storage';

  @override
  String get diagCheckPlayer => 'Playback engine (mpv)';

  @override
  String get diagCheckDownloader => 'Download engine';

  @override
  String get diagCheckNotifications => 'Notifications';

  @override
  String get diagCheckNative => 'Platform bridge (native)';

  @override
  String get diagCheckCache => 'Cache';

  @override
  String get diagCheckCrashes => 'Crash log';

  @override
  String get diagCrashesSection => 'Recorded crashes';

  @override
  String get diagNoCrashes => 'No crashes recorded from previous sessions.';

  @override
  String get diagPrevCrashDetails => 'View crash details';

  @override
  String get diagClearLogs => 'Clear logs';

  @override
  String get diagLogsCleared => 'Crash logs cleared';

  @override
  String get diagSessionLog => 'Current session log';

  @override
  String get diagSessionLogBody => 'Last 120 events recorded in this session';

  @override
  String get diagCopyReport => 'Copy';

  @override
  String get diagReportCopied => 'Copied to clipboard';

  @override
  String get diagShareReport => 'Share full report';

  @override
  String get diagLocalNote =>
      'Everything stays on your device; nothing is sent unless you share the report yourself.';

  @override
  String get dlDegradedTitle => 'The download engine is currently unavailable';

  @override
  String get dlDegradedRetry => 'Retry download engine setup';

  @override
  String get bootSafeModePreparing => 'Starting in safe mode…';

  @override
  String get libraryPlatforms => 'Platforms';

  @override
  String get platformsLinks => 'Links';

  @override
  String get platformsIptv => 'IPTV Lists';

  @override
  String get platformsNas => 'Network Drives';

  @override
  String get addLinkTitle => 'Add link';

  @override
  String get addLinkUrlHint => 'Video or stream URL';

  @override
  String get addLinkNameHint => 'Name (optional)';

  @override
  String get addLinkPlayNow => 'Play now';

  @override
  String get addLinkSaveOnly => 'Save only';

  @override
  String get addLinkInvalid => 'Unsupported or malformed URL';

  @override
  String get linkSaved => 'Link saved';

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String resumeFrom(String time) {
    return 'Resume from $time';
  }

  @override
  String get platformsEmptyLinks => 'No saved links yet';

  @override
  String get platformsEmptyLinksBody =>
      'Add a video or live stream URL (HTTP, HLS, DASH, RTSP, RTMP, FTP) to play it here';

  @override
  String get platformsEmptyIptv => 'No IPTV playlists yet';

  @override
  String get platformsEmptyIptvBody =>
      'Import an M3U/M3U8 playlist from a URL or a file and watch channels inside the app';

  @override
  String get platformsEmptyNas => 'No network drives yet';

  @override
  String get platformsEmptyNasBody =>
      'Add a WebDAV, FTP or SFTP server to browse its files and play videos from it';

  @override
  String get iptvImport => 'Import playlist';

  @override
  String get iptvImportUrl => 'Import from URL';

  @override
  String get iptvImportFile => 'Import from file';

  @override
  String get iptvImportNameHint => 'Playlist name (optional)';

  @override
  String get iptvImportUrlHint => 'M3U/M3U8 playlist URL';

  @override
  String get iptvImporting => 'Importing playlist…';

  @override
  String iptvImportDone(int count) {
    return 'Imported $count channels';
  }

  @override
  String iptvImportFail(String error) {
    return 'Import failed: $error';
  }

  @override
  String iptvChannels(int count) {
    return '$count channels';
  }

  @override
  String get iptvGroupsAll => 'All groups';

  @override
  String get iptvSearchChannels => 'Search channels';

  @override
  String get iptvDeleteConfirmTitle => 'Delete playlist?';

  @override
  String iptvDeleteConfirmBody(String name) {
    return '\"$name\" and its channels will be removed from the app';
  }

  @override
  String get iptvLoadFail => 'Could not load channels';

  @override
  String get iptvNoChannels => 'No matching channels';

  @override
  String get nasAddServer => 'Add network drive';

  @override
  String get nasName => 'Name';

  @override
  String get nasHost => 'Address (IP or host)';

  @override
  String get nasPort => 'Port';

  @override
  String get nasUsername => 'Username (optional)';

  @override
  String get nasPassword => 'Password (optional)';

  @override
  String get nasUseTls => 'Secure connection (HTTPS)';

  @override
  String nasConnectFail(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get nasDeleteConfirmTitle => 'Delete server?';

  @override
  String nasDeleteConfirmBody(String name) {
    return '\"$name\" will be forgotten; you can add it again later';
  }

  @override
  String nasBrowseFail(String error) {
    return 'Browse failed: $error';
  }

  @override
  String get nasEmptyFolder => 'Empty folder';

  @override
  String get nasUp => 'Parent folder';

  @override
  String get nasRoot => 'Root';

  @override
  String get liveBadge => 'LIVE';

  @override
  String qualityCap(int kbps) {
    return 'Up to $kbps kbps';
  }

  @override
  String get playerVideoTrack => 'Video track';

  @override
  String get addSubtitleUrl => 'Add subtitle URL';

  @override
  String get subtitleUrlHint => 'Subtitle file URL (SRT/VTT)';

  @override
  String get subtitleAdded => 'Subtitle loaded';

  @override
  String get subtitleInvalid => 'Could not load subtitle';

  @override
  String get platformsSites => 'Sites';

  @override
  String get sitesSearchHint => 'Search platforms (YouTube, TikTok, Netflix…)';

  @override
  String get sitesAll => 'All';

  @override
  String get sitesCatMine => 'My sites';

  @override
  String get sitesCatVideo => 'Video';

  @override
  String get sitesCatArabic => 'Arabic';

  @override
  String get sitesCatMovies => 'Movies';

  @override
  String get sitesCatLive => 'News & live';

  @override
  String get sitesCatSports => 'Sports';

  @override
  String get sitesCatMusic => 'Music';

  @override
  String get sitesCatAnime => 'Anime';

  @override
  String get sitesCatSocial => 'Social';

  @override
  String get sitesCatLearn => 'Learning';

  @override
  String get sitesCatTv => 'TV';

  @override
  String get sitesAddAny => 'Add any site';

  @override
  String get sitesAddTitle => 'Add site';

  @override
  String get sitesAddName => 'Name';

  @override
  String get sitesAddUrl => 'Address';

  @override
  String get sitesNameRequired => 'Name is required';

  @override
  String get sitesBookmarks => 'Bookmarks';

  @override
  String get bookmarksEmpty =>
      'No bookmarks yet — use the star inside the browser to save pages';

  @override
  String get bookmarkAdded => 'Added to bookmarks';

  @override
  String get bookmarkRemoved => 'Removed from bookmarks';

  @override
  String get bookmarkAdd => 'Save to bookmarks';

  @override
  String get bookmarkRemove => 'Remove from bookmarks';

  @override
  String get browserUaTooltip => 'Switch between mobile and desktop site';

  @override
  String browserBlockedSession(int count) {
    return 'Blocked on this page: $count';
  }

  @override
  String get browserAddressHint => 'Search or enter site address';

  @override
  String get browserShieldTooltip => 'Protection & ad blocking';

  @override
  String get browserStreamsTooltip => 'Videos detected on this page';

  @override
  String get browserStreamsTitle => 'Video detected on this page';

  @override
  String get browserPlayThisPage => 'Play this page in the DRS player';

  @override
  String get browserPlayInPlayer => 'Play in the native player';

  @override
  String get browserNoStreams =>
      'No playable video detected on this page yet — browse the site and try again';

  @override
  String get browserPlayFailed => 'Could not open this link in the player';

  @override
  String get protectionTitle => 'Protection & VPN';

  @override
  String get protectionAdBlockTitle => 'Ad protection';

  @override
  String get protectionAdBlock => 'Block ads & trackers';

  @override
  String get protectionAdBlockDesc =>
      'Blocks 75,000+ ad and tracker domains inside the built-in browser';

  @override
  String get protectionIncognito => 'Incognito browsing';

  @override
  String get protectionIncognitoDesc => 'Do not save browsing history';

  @override
  String protectionBlockedTotal(int count) {
    return 'Requests blocked so far: $count';
  }

  @override
  String get protectionResetCounter => 'Reset';

  @override
  String get protectionBlocklistInfo =>
      'The blocklist comes from the open-source StevenBlack project (MIT license) and ships with every release. No DRM system of any platform is circumvented.';

  @override
  String get browserYtAdKillTitle => 'YouTube ad protection';

  @override
  String get browserYtAdKillSub =>
      'Ads are auto-skipped and hidden in the player, search and home pages';

  @override
  String get ghTitle => 'GitHub & updates';

  @override
  String get ghUpdateSection => 'App update';

  @override
  String ghCurrentVersion(String v) {
    return 'Current version: $v';
  }

  @override
  String ghUpdateAvailable(String tag) {
    return 'New update available: $tag';
  }

  @override
  String get ghCheckUpdate => 'Check now';

  @override
  String get ghDownloading => 'Downloading…';

  @override
  String ghDownloadingPct(int p) {
    return 'Downloading… $p%';
  }

  @override
  String get ghInstalling => 'Downloaded — opening installer…';

  @override
  String get ghInstall => 'Install update';

  @override
  String get ghInstallFailed =>
      'Could not start the installer (check install-permission)';

  @override
  String get ghAutoCheck => 'Check for updates automatically';

  @override
  String get ghAutoCheckDesc => 'Silently checks GitHub when the app starts';

  @override
  String get ghReleasesSection => 'Recent releases';

  @override
  String get ghNoReleases => 'No releases found — check connectivity';

  @override
  String get ghNoNotes => 'No release notes';

  @override
  String get ghOpenRepo => 'Project repository';

  @override
  String get ghOpenReleases => 'Releases page';

  @override
  String get ghOpenDeveloper => 'Developer account';

  @override
  String get ghOpen => 'Open';

  @override
  String get playerBookmarks => 'Bookmarks';

  @override
  String get playerBookmarkEmpty =>
      'No bookmarks yet — add one at the current moment';

  @override
  String get playerBookmarkAdd => 'Bookmark here';

  @override
  String get playerCapture => 'Capture frame';

  @override
  String get playerCaptureOk => 'Frame saved to the app Pictures folder';

  @override
  String get playerCaptureFail => 'Capture failed';

  @override
  String get playerIntroEnd => 'Intro ends here';

  @override
  String playerIntroEndSet(int s) {
    return 'The next video in this folder will start at $s s';
  }

  @override
  String get protectionHonestNote =>
      'Honest note: ad blocking works inside the built-in browser. Some platforms (e.g. YouTube) bake ads into the video stream itself, which cannot be blocked without breaking playback. The VPN uses OpenVPN on Android devices only.';

  @override
  String get vpnTitle => 'Free VPN (OpenVPN)';

  @override
  String get vpnStateConnected => 'Connected';

  @override
  String get vpnStateBusy => 'Working';

  @override
  String get vpnStateError => 'Error';

  @override
  String get vpnStateUnsupported => 'Unsupported';

  @override
  String get vpnStateOff => 'Disconnected';

  @override
  String vpnConnectedTo(String name) {
    return 'Connected to $name';
  }

  @override
  String vpnConnecting(String stage) {
    return 'Connecting… ($stage)';
  }

  @override
  String get vpnDisconnectedHint =>
      'Pick a free server or import a .ovpn file for an encrypted connection';

  @override
  String get vpnPickServer => 'Pick a free server';

  @override
  String get vpnServersTitle => 'Free public servers (VPNGate)';

  @override
  String get vpnServersFail =>
      'Could not fetch the server list — check your connection';

  @override
  String get vpnNoServers => 'No servers available right now';

  @override
  String get vpnImport => 'Import .ovpn';

  @override
  String get vpnImportedFile => 'Imported file';

  @override
  String get vpnInvalidConfig =>
      'The file is not a valid OpenVPN configuration';

  @override
  String get vpnDisconnect => 'Disconnect';

  @override
  String vpnReconnect(String name) {
    return 'Reconnect: $name';
  }

  @override
  String get vpnConnectFailed => 'Connection failed — try another server';

  @override
  String get vpnError =>
      'Something went wrong while connecting. Try another server.';

  @override
  String get vpnUnsupported =>
      'The VPN client works on Android devices only (requires the system permission dialog).';

  @override
  String get didYouMeanPrefix => 'Did you mean';

  @override
  String get activityTitle => 'My Smart Activity';

  @override
  String get activityEmptyTitle => 'No activity yet';

  @override
  String get activityEmptyBody =>
      'Watch a few videos and your smart stats will appear here automatically.';

  @override
  String get activityFailed => 'Couldn\'t compute statistics';

  @override
  String get statWatchTime => 'Watch time';

  @override
  String get statWatched => 'Videos watched';

  @override
  String get statCompleted => 'Completed';

  @override
  String get statStreak => 'Day streak';

  @override
  String get hoursUnit => 'h';

  @override
  String get minutesUnit => 'min';

  @override
  String get daysUnit => 'days';

  @override
  String bestStreak(int days) {
    return 'Longest streak: $days days';
  }

  @override
  String peakHourLabel(int hour) {
    return 'Peak hour: $hour:00';
  }

  @override
  String get trend14Title => 'Last 14 days';

  @override
  String get trend14Caption => 'Bar height = watch time on that day';

  @override
  String get weekdayPatternTitle => 'Weekday pattern';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get topInterestsTitle => 'Top interests';

  @override
  String get cleanupTitle => 'Smart cleanup';

  @override
  String get cleanupNoDuplicates => 'No duplicates found';

  @override
  String get cleanupNoDuplicatesBody =>
      'Your library is clean — no duplicate videos detected.';

  @override
  String cleanupFoundClusters(int count) {
    return '$count possible duplicate group(s)';
  }

  @override
  String cleanupDeleteSelected(int count) {
    return 'Delete selected ($count)';
  }

  @override
  String get cleanupKeepSuggestion => 'Suggested copy to keep';

  @override
  String get cleanupConfirmTitle => 'Confirm duplicate removal';

  @override
  String cleanupConfirmBody(int count) {
    return '$count item(s) will be removed from the library. Files on disk are not touched.';
  }

  @override
  String cleanupDeleted(int count) {
    return '$count duplicate(s) removed';
  }

  @override
  String get cleanupFailed => 'Cleanup failed';

  @override
  String get sleepCustomMinutes => 'Custom minutes';

  @override
  String get sleepStart => 'Start';

  @override
  String get sleepFadeNote =>
      'Volume fades gently during the last 10 seconds before stop.';

  @override
  String get smartPlaylistsTitle => 'Smart playlists';

  @override
  String get smartContinueWatching => 'Continue watching';

  @override
  String get smartUnwatched => 'Unwatched';

  @override
  String get smartMostPlayed => 'Most played';

  @override
  String get smartRecentlyPlayed => 'Recently played';

  @override
  String get smartFavorites => 'Favorites';

  @override
  String smartBecauseYouWatched(String title) {
    return 'Because you watched $title';
  }

  @override
  String get smartSaveAsPlaylist => 'Save as playlist';

  @override
  String get smartPlaylistSaved => 'Playlist saved to your playlists';

  @override
  String get smartPlayAll => 'Play all';

  @override
  String get settingsBackup => 'Backup & restore';

  @override
  String get backupTitle => 'Backup & restore';

  @override
  String get backupIncludesTitle => 'What the backup file includes';

  @override
  String backupItemsCount(int count) {
    return '$count library items';
  }

  @override
  String backupPlaylistsCount(int count) {
    return '$count playlists';
  }

  @override
  String backupProgressCount(int count) {
    return '$count saved watch positions';
  }

  @override
  String backupSearchesCount(int count) {
    return '$count saved searches';
  }

  @override
  String get backupSettingsRow => 'All settings and preferences';

  @override
  String get backupNeverDeletes =>
      'Restore only adds — nothing is deleted from your current data.';

  @override
  String get backupExport => 'Export backup';

  @override
  String backupExportedTo(String path) {
    return 'File created: $path';
  }

  @override
  String get backupExportDone =>
      'Backup created — share it and keep it somewhere safe';

  @override
  String get backupImport => 'Restore from backup file';

  @override
  String get backupMergeNote =>
      'Restore merges into your library: existing items are skipped and nothing is deleted.';

  @override
  String get backupConfirmTitle => 'Restore this backup?';

  @override
  String backupConfirmBody(String version, String date) {
    return 'Backup from version $version made on $date. Its data will be merged with your current library.';
  }

  @override
  String get backupConfirmRestore => 'Restore';

  @override
  String get backupImportDoneTitle => 'Restore complete';

  @override
  String backupImportDone(int added, int skipped, int playlists, int merged,
      int progress, int searches) {
    return 'Added $added items, skipped $skipped existing • $playlists new and $merged merged playlists • $progress watch positions • $searches searches';
  }

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get sortPlayCount => 'Most played';

  @override
  String get sortResolution => 'Video resolution';

  @override
  String get sortDirectionAscending => 'Ascending order';

  @override
  String get sortDirectionDescending => 'Descending order';

  @override
  String get streamKindHls => 'HLS live stream — plays instantly';

  @override
  String get streamKindDash => 'DASH stream — plays instantly';

  @override
  String get streamKindFile => 'Direct video file';

  @override
  String get analyticsExport => 'Export analytics';

  @override
  String get analyticsExportCsv => 'Export full CSV';

  @override
  String get analyticsExportCsvDesc =>
      'Your whole library with play counts and progress — opens in Excel';

  @override
  String get analyticsExportSummary => 'Share activity summary';

  @override
  String get analyticsExportSummaryDesc =>
      'Ready-to-share text: watch time, streaks, peak hour';

  @override
  String get downloadsRetryAll => 'Retry all failed';

  @override
  String get setAutoResumeWifi => 'Auto-resume when Wi-Fi returns';

  @override
  String get setAutoResumeWifiDesc =>
      'Continues downloads that paused due to network loss — ones you paused stay paused';

  @override
  String get cloudBackupTitle => 'Cloud backup (WebDAV/SFTP)';

  @override
  String get cloudRefresh => 'Refresh list';

  @override
  String get cloudKindWebdav => 'WebDAV';

  @override
  String get cloudKindSftp => 'SFTP';

  @override
  String get cloudHost => 'Host';

  @override
  String get cloudPort => 'Port';

  @override
  String get cloudTls => 'HTTPS';

  @override
  String get cloudUser => 'Username';

  @override
  String get cloudPassword => 'Password';

  @override
  String get cloudBasePath => 'Base path (optional)';

  @override
  String cloudPathNote(String path) {
    return 'Backups will be stored in the $path folder on your server';
  }

  @override
  String get cloudTest => 'Test connection';

  @override
  String get cloudTestOk => 'Connection OK — folder ready';

  @override
  String get cloudUploadNow => 'Back up now';

  @override
  String cloudUploaded(String path) {
    return 'Uploaded to: $path';
  }

  @override
  String cloudFailed(String error) {
    return 'Operation failed: $error';
  }

  @override
  String get cloudAutoTitle => 'Daily auto backup';

  @override
  String get cloudAutoDesc =>
      'Uploads a backup automatically every 24h when you open this screen';

  @override
  String get cloudAutoNeedsConfig => 'Add a server first to enable auto backup';

  @override
  String cloudLastBackup(String stamp) {
    return 'Last cloud backup: $stamp';
  }

  @override
  String get cloudRemoteList => 'Backups on the server';

  @override
  String get cloudListHint => 'Tap to fetch the cloud backup list';

  @override
  String get cloudListEmpty => 'No backups on the server yet';

  @override
  String get appLock => 'App lock';

  @override
  String get appLockIntro =>
      'Protect the app with a PIN. It is asked when you return after leaving the app; the PIN itself is never stored on the device — only a cryptographic fingerprint of it.';

  @override
  String get appLockCreatePin => 'Create PIN';

  @override
  String get appLockChangePin => 'Change PIN';

  @override
  String get appLockRemovePin => 'Remove lock';

  @override
  String get appLockEnabledTitle => 'Lock enabled';

  @override
  String get appLockEnabledDesc =>
      'The PIN will be asked when you return to the app, based on the delay you choose.';

  @override
  String get appLockEnterCurrent => 'Enter the current PIN';

  @override
  String get appLockChoosePin => 'Choose a PIN (4 digits)';

  @override
  String get appLockConfirmPin => 'Re-enter the PIN to confirm';

  @override
  String get appLockPinMismatch => 'PINs do not match — try again';

  @override
  String get appLockSaved => 'PIN saved';

  @override
  String get appLockRemoved => 'App lock removed';

  @override
  String get appLockAutoLock => 'Re-lock after leaving';

  @override
  String get appLockImmediate => 'Immediately';

  @override
  String get appLockAfter1m => 'After 1 minute';

  @override
  String get appLockAfter5m => 'After 5 minutes';

  @override
  String get lockTitle => 'App locked';

  @override
  String get lockSubtitle => 'Enter your PIN to continue';

  @override
  String get lockWrongPin => 'Wrong PIN — try again';

  @override
  String lockLockedOut(int seconds) {
    return 'Too many attempts. Wait $seconds seconds';
  }

  @override
  String get lockPrivacyNote =>
      'The PIN is stored only as a salted SHA-256 fingerprint on this device. If you forget it, clearing the app\'s data is required.';

  @override
  String get playerAbRepeat => 'A-B segment loop';

  @override
  String get playerAbInactive => 'No segment marked for looping yet';

  @override
  String get playerAbSetStart => 'Set start (A)';

  @override
  String get playerAbSetStartHint => 'At the current position';

  @override
  String get playerAbSetEnd => 'Set end (B)';

  @override
  String get playerAbSetEndHint => 'At the current position';

  @override
  String get playerAbTooShort =>
      'Segment too short — move the position and retry';

  @override
  String get playerAbClear => 'Stop looping';

  @override
  String get playerAbNote =>
      'Great for Quran memorization and language learning: playback jumps back to A whenever it reaches B — even after a manual seek past the end. Use Stop looping to end it.';

  @override
  String get playerAudio => 'Audio';

  @override
  String get audioSheetTitle => 'Audio enhancement';

  @override
  String get audioPresetFlat => 'No EQ';

  @override
  String get audioPresetFlatDesc => 'Original sound, untouched';

  @override
  String get audioPresetBass => 'Bass boost';

  @override
  String get audioPresetBassDesc => 'Deeper music and movies on phone speakers';

  @override
  String get audioPresetVocal => 'Dialog boost';

  @override
  String get audioPresetVocalDesc => 'Clearer news, lectures and series';

  @override
  String get audioPresetNight => 'Night mode';

  @override
  String get audioPresetNightDesc =>
      'Cuts rumble, lifts speech clarity at low volume';

  @override
  String get audioPresetMovie => 'Cinema';

  @override
  String get audioPresetMovieDesc => 'Wide curve with a theater feel';

  @override
  String get audioBoost => 'Volume boost';

  @override
  String get audioBoostWarning => 'High boost: loud sources may distort';

  @override
  String get audioEnhanceNote =>
      'Applied live and saved as the default for every video you open.';

  @override
  String get vaultTitle => 'Private vault';

  @override
  String get vaultLockedTitle => 'Vault locked';

  @override
  String get vaultCreatePin => 'Create a vault PIN';

  @override
  String get vaultConfirmPin => 'Confirm the PIN';

  @override
  String get vaultSetupHint =>
      'This PIN guards your hidden videos only — it is separate from the app lock. 4 digits.';

  @override
  String get vaultPinMismatch => 'The two PINs do not match — start over';

  @override
  String get vaultPinInvalid => 'The PIN must be 4 digits';

  @override
  String get vaultPinCreated =>
      'Vault PIN created. Use \'Hide in vault\' from any video\'s menu.';

  @override
  String get vaultPinChanged => 'Vault PIN updated';

  @override
  String get vaultWrongPin => 'Wrong vault PIN';

  @override
  String get vaultEnterPin => 'Enter the vault PIN';

  @override
  String vaultLockedOut(int seconds) {
    return 'Too many attempts. Wait $seconds seconds';
  }

  @override
  String get vaultChangePin => 'Change vault PIN';

  @override
  String get vaultCurrentPin => 'Current PIN';

  @override
  String get vaultNewPin => 'New PIN (4 digits)';

  @override
  String get vaultLockNow => 'Lock now';

  @override
  String get vaultEmpty => 'The vault is empty';

  @override
  String get vaultEmptyHint =>
      'Long-press any video in the library and choose \'Hide in vault\' to move it here.';

  @override
  String get hideInVault => 'Hide in vault';

  @override
  String get unhideFromVault => 'Move out of vault';

  @override
  String get vaultItemHidden =>
      'Video hidden — find it in Settings → Private vault';

  @override
  String get vaultItemRestored => 'Video restored to the library';

  @override
  String get vaultRemoveForever => 'Delete permanently?';

  @override
  String get vaultRemoveForeverHint =>
      'The video file itself is deleted from the device, not just its library entry.';

  @override
  String get subtitleToolsTitle => 'Subtitle tools';

  @override
  String get subtitleToolsHint => 'Sync delay + Arabic legacy encoding fix';

  @override
  String get subtitleDelayTitle => 'Sync delay';

  @override
  String get subtitleDelayEarlier => 'Subtitles earlier';

  @override
  String get subtitleDelayLater => 'Subtitles later';

  @override
  String get subtitleDelayNone => 'No delay — subtitles are in sync';

  @override
  String subtitleDelayShownLater(String value) {
    return 'Subtitles appear $value s later';
  }

  @override
  String subtitleDelayShownEarlier(String value) {
    return 'Subtitles appear $value s earlier';
  }

  @override
  String get subtitleDelayReset => 'Reset delay';

  @override
  String get subtitleEncodingTitle => 'Text encoding';

  @override
  String get subtitleEncodingHint =>
      'Old Arabic .srt files show as scrambled letters? Pick the right encoding and DRS Video converts them to readable Arabic automatically.';

  @override
  String get encAuto => 'Auto-detect (recommended)';

  @override
  String get encUtf8 => 'UTF-8 (modern files)';

  @override
  String get encWin1256 => 'Windows-1256 (legacy Arabic)';

  @override
  String get encIso8859 => 'ISO-8859-6 (legacy Arabic)';

  @override
  String get encWin1252 => 'Windows-1252 (Latin)';

  @override
  String get subtitleLoadExternal => 'Load subtitle file';

  @override
  String get subtitleLoadOk => 'Subtitle loaded';

  @override
  String get subtitleLoadFailed => 'Could not load the subtitle file';

  @override
  String get audioOnlyTitle => 'Audio-only mode';

  @override
  String get audioOnlyHint => 'Skip video decoding — saves battery and data';

  @override
  String get audioOnlyNote =>
      'Sound keeps playing while the screen shows this page. Your choice is remembered for the next videos.';

  @override
  String get audioOnlyActive =>
      'Audio-only mode is on — video decoding is paused to save battery and data.';

  @override
  String get audioOnlyRestoreVideo => 'Restore video';

  @override
  String get playerBookmarkPrev => 'Previous';

  @override
  String get playerBookmarkNext => 'Next';

  @override
  String get pictureTitle => 'Picture calibration';

  @override
  String get pictureBrightness => 'Brightness';

  @override
  String get pictureContrast => 'Contrast';

  @override
  String get pictureSaturation => 'Saturation';

  @override
  String get pictureGamma => 'Gamma';

  @override
  String get pictureHue => 'Hue';

  @override
  String get pictureReset => 'Reset';

  @override
  String get pictureRotate => 'Rotate';

  @override
  String get pictureZoom => 'Zoom';

  @override
  String get pictureZoomReset => 'Reset zoom';

  @override
  String get pictureZoomHint =>
      'Pinch with two fingers to zoom and pan — long-press boosts speed to 2×.';

  @override
  String get translateTitle => 'Auto-translation';

  @override
  String get translateHint =>
      'Translates the current subtitle file into the chosen language via a free translation service (needs internet).';

  @override
  String get translateNoSubtitle =>
      'No external subtitle loaded — load one first to translate it.';

  @override
  String get translateButton => 'Translate now';

  @override
  String get translateDone => 'Translated and track swapped';

  @override
  String get translateDoneCached => 'Cached translation applied';

  @override
  String get translateAlreadyTarget => 'Already in this language';

  @override
  String get translateFailed =>
      'Translation failed — check your connection and retry';

  @override
  String get translateAutoPrefTitle => 'Auto-translate YouTube captions';

  @override
  String get translateAutoPrefSub =>
      'Automatically swap to the translated track after download';

  @override
  String get smartAutoSubsTitle => 'YouTube captions automatically';

  @override
  String get smartAutoSubsSub =>
      'Attach the available YouTube captions to the video';

  @override
  String get smartAutoSiblingTitle => 'Auto-load folder subtitle';

  @override
  String get smartAutoSiblingSub =>
      'Pick a same-folder subtitle file matching the video name';

  @override
  String get smartBatterySaverTitle => 'Battery saver';

  @override
  String get smartBatterySaverSub =>
      'Switch to audio-only below 20% battery while unplugged';

  @override
  String get smartDataSaverTitle => 'Data saver';

  @override
  String get smartDataSaverSub => 'Cap streaming quality to save mobile data';
}
