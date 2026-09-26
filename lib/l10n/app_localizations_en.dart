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
}
