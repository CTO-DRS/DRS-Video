import 'package:flutter/foundation.dart';
import '../core/errors/app_exception.dart';
import '../core/constants/app_constants.dart';
import '../core/network/connectivity_service.dart';
import '../core/utils/logger.dart';
import '../data/models/download_task.dart';
import '../data/models/media_item.dart';
import '../services/downloader/download_service.dart';
import '../services/downloader/platform_download_resolver.dart';
import '../services/platform/native_channel.dart';

/// Thin UI-facing wrapper over [DownloadService].
class DownloadsController extends ChangeNotifier {
  DownloadsController({required DownloadService service, required this.connectivity})
      : _service = service {
    _service.addListener(notifyListeners);
    connectivity.addListener(notifyListeners);
  }

  final DownloadService _service;
  final ConnectivityService connectivity;

  List<DownloadTaskModel> get tasks => _service.tasks;
  int get activeCount => _service.activeCount;
  int get queuedCount => _service.queuedCount;
  bool get waitingForWifi => _service.waitingForWifi;
  bool get wifiOnly => _service.waitingForWifi;
  bool get isOnline => connectivity.isOnline;

  double? speedOf(String id) => _service.speedOf(id);

  String? etaOf(DownloadTaskModel t) {
    final speed = _service.speedOf(t.id);
    if (speed == null || speed <= 0 || t.expectedSize == null) return null;
    final remaining = t.expectedSize! * (100 - t.progress) ~/ 100;
    return '$remaining|$speed';
  }

  Future<int> freeSpace() async {
    final dir = await _service.downloadDir;
    return NativeChannel.instance.freeSpaceBytes(dir);
  }

  Future<void> refresh() async {
    // Lazy init (v1.0.2): WorkManager is initialized when this tab is
    // opened — never at app boot. Degraded state shows in this screen.
    await _service.init();
    await _service.checkStorageWarning();
    notifyListeners();
  }

  /// Starts a download for a library item (pre-flight checks inside service).
  Future<DownloadTaskModel> startForItem(MediaItem item) async {
    if (!isOnline) {
      throw const AppException(AppErrorType.network);
    }
    return _service.start(
      url: item.uri,
      title: item.title,
      sourceId: item.sourceId,
      headers: item.headers,
    );
  }

  /// v1.14.0: starts a raw-URL download from the add-download sheet
  /// (paste-link flow). The service picks the extension/classification.
  /// v1.14.2: [resolvedMedia] + [preflight] come from the sheet's single
  /// probe pass so start() neither re-resolves nor re-probes.
  Future<DownloadTaskModel> startFromUrl({
    required String url,
    required String title,
    DownloadPriority priority = DownloadPriority.normal,
    ResolvedPlatformMedia? resolvedMedia,
    PreflightInfo? preflight,
  }) async {
    if (!isOnline) {
      throw const AppException(AppErrorType.network);
    }
    return _service.start(
      url: url,
      title: title,
      priority: priority,
      resolvedMedia: resolvedMedia,
      preflight: preflight,
    );
  }

  Future<void> pause(String id) => _guarded(() => _service.pause(id));
  Future<void> resume(String id) => _guarded(() => _service.resume(id));
  Future<void> cancel(String id) => _guarded(() => _service.cancel(id));
  Future<void> retry(String id) => _guarded(() => _service.retry(id));

  /// v1.8.0: re-enqueue every failed task from the toolbar button.
  Future<void> retryAll() => _guarded(_service.retryAll);
  Future<void> remove(String id, {bool deleteFile = false}) =>
      _guarded(() => _service.remove(id, deleteFile: deleteFile));
  Future<void> setPriority(String id, DownloadPriority p) =>
      _guarded(() => _service.setPriority(id, p));
  Future<void> pauseAll() => _guarded(_service.pauseAll);
  Future<void> resumeAll() => _guarded(_service.resumeAll);

  Future<void> _guarded(Future<void> Function() op) async {
    try {
      await op();
    } catch (e, s) {
      AppLogger.instance.error('downloads-ui', 'op failed', e, s);
      notifyListeners();
    }
  }
}
