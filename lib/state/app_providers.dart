import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/connectivity_service.dart';
import '../core/network/dio_client.dart';
import '../core/storage/database_service.dart';
import '../core/storage/preferences_service.dart';
import '../core/utils/logger.dart';
import '../data/repositories/bookmark_repository.dart';
import '../data/repositories/download_repository.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/playlist_repository.dart';
import '../data/repositories/source_repository.dart';
import '../data/sources/direct_url_adapter.dart';
import '../data/sources/local_file_adapter.dart';
import '../data/sources/source_adapter.dart';
import '../services/backup/backup_service.dart';
import '../services/downloader/download_service.dart';
import '../services/files/file_manager_service.dart';
import '../services/notifications/notification_service.dart';
import '../services/player/player_service.dart';
import '../services/recommendations/recommendation_engine.dart';
import '../services/recommendations/playback_optimizer.dart';
import '../services/sharing/share_service.dart';
import '../services/storage/storage_analyzer.dart';

/// Signature shared by the real [bootstrap] and test overrides.
typedef BootstrapFn = Future<AppServices> Function({
  bool minimal,
  void Function(String stage)? onStage,
  bool Function(String step)? failStepForTest,
});

/// Records which optional services degraded during startup, so the UI can
/// surface honest states instead of failing silently.
class ServiceHealth {
  final List<String> warnings = [];
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Composition root: builds every service/repo once and wires dependencies.
class AppServices {
  AppServices({
    required this.prefs,
    required this.db,
    required this.connectivity,
    required this.library,
    required this.history,
    required this.playlists,
    required this.bookmarks,
    required this.downloadsRepo,
    required this.sources,
    required this.player,
    required this.downloader,
    required this.registry,
    required this.engine,
    required this.optimizer,
    required this.share,
    required this.fileManager,
    required this.analyzer,
    required this.backup,
    required this.health,
  });

  final PreferencesService prefs;
  final DatabaseService db;
  final ConnectivityService connectivity;
  final LibraryRepository library;
  final HistoryRepository history;
  final PlaylistRepository playlists;
  final BookmarkRepository bookmarks;
  final DownloadRepository downloadsRepo;
  final SourceRepository sources;
  final PlayerService player;
  final DownloadService downloader;
  final SourceRegistry registry;
  final RecommendationEngine engine;
  final PlaybackOptimizer optimizer;
  final ShareService share;
  final FileManagerService fileManager;
  final StorageAnalyzer analyzer;
  final BackupService backup;
  final ServiceHealth health;
}

/// Boots all services. Never leaves the app without a UI:
/// [runApp] already happened; this runs inside the widget tree.
///
/// CRITICAL v1.0.2 CONTRACT — boot performs NO risky native work:
/// only SharedPreferences + sqflite (simple, stable platform calls).
/// The mpv engine, flutter_downloader (WorkManager) and local
/// notifications are created LAZILY on first real use. A native crash
/// there (e.g. libmpv load failure on some devices) cannot be caught by
/// any Dart handler, so it must never run before the user can see and
/// use the app shell.
///
/// - Critical steps (prefs, database) may throw -> the boot gate shows a
///   real error screen with the cause + retry + safe mode.
/// - Optional steps are labels only: their real initialization is lazy
///   and each feature screen degrades gracefully with its own retry.
///   [minimal] keeps them skipped entirely (safe mode).
Future<AppServices> bootstrap({
  bool minimal = false,
  void Function(String stage)? onStage,
  bool Function(String step)? failStepForTest,
}) async {
  void step(String name) {
    onStage?.call(name);
    if (failStepForTest?.call(name) ?? false) {
      throw StateError('simulated bootstrap failure at step: $name');
    }
  }

  final health = ServiceHealth();

  // Label only: the mpv engine is now created lazily on first playback
  // (see PlayerService.ensureEngine) so a native library failure can
  // never abort startup.
  step('media');

  step('prefs');
  final prefs = PreferencesService(await SharedPreferences.getInstance());

  final db = DatabaseService.instance;
  step('database');
  try {
    await db.database; // open eagerly
  } catch (e) {
    // One retry: transient locks/IO hiccups on slow devices are common.
    AppLogger.instance.warning('db', 'first open failed, retrying: $e');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await db.database;
  }

  step('repositories');
  final connectivity = ConnectivityService();
  final library = LibraryRepository(db);
  final history = HistoryRepository(db);
  final playlists = PlaylistRepository(db);
  final bookmarks = BookmarkRepository(db);
  final downloadsRepo = DownloadRepository(db);
  final sources = SourceRepository(db);

  // Label only: notifications initialize lazily before the first real
  // notification is posted (see NotificationService).
  if (!minimal) {
    step('notifications');
  }

  step('player');
  // Engine creation is ALWAYS deferred (never at boot), even outside
  // safe mode: libmpv loading is a native operation that a Dart
  // try/catch cannot intercept if it segfaults.
  final player = PlayerService(
    prefs: prefs,
    history: history,
    library: library,
    connectivity: connectivity,
    bookmarks: bookmarks,
    createEngineNow: false,
  );

  final downloader = DownloadService(
    prefs: prefs,
    downloads: downloadsRepo,
    library: library,
    connectivity: connectivity,
    notifications: NotificationService.instance,
  );
  // Label only: flutter_downloader (WorkManager) initializes lazily when
  // the Downloads tab is opened or the first download starts.
  if (!minimal) {
    step('downloads');
  }

  step('sources');
  final registry = SourceRegistry(adapters: [
    LocalFileAdapter(),
    DirectUrlAdapter(DioClient.instance),
  ]);

  AppLogger.instance.info(
      'boot',
      'critical services ready (prefs+db); player/downloader/notifications '
      'initialize lazily on first use');

  return AppServices(
    prefs: prefs,
    db: db,
    connectivity: connectivity,
    library: library,
    history: history,
    playlists: playlists,
    bookmarks: bookmarks,
    downloadsRepo: downloadsRepo,
    sources: sources,
    player: player,
    downloader: downloader,
    registry: registry,
    engine: const RecommendationEngine(),
    optimizer: const PlaybackOptimizer(),
    share: const ShareService(),
    fileManager: const FileManagerService(),
    analyzer: const StorageAnalyzer(),
    backup: BackupService(
      library: library,
      history: history,
      playlists: playlists,
      bookmarks: bookmarks,
      prefs: prefs,
    ),
    health: health,
  );
}
