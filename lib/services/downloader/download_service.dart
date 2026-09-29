import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/preferences_service.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/serialized_runner.dart';
import '../../data/models/download_task.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/download_repository.dart';
import '../smart/intel_v4.dart';
import '../../data/repositories/library_repository.dart';
import '../notifications/notification_service.dart';
import '../platform/native_channel.dart';
import 'chunked_download_engine.dart';
import 'platform_download_resolver.dart';

/// v1.14.2: probe results handed in by the add-download sheet so
/// [DownloadService.start] skips its own HEAD/range probing — the flow
/// previously resolved + probed TWICE (sheet, then start), doubling the
/// user-visible latency on every download.
class PreflightInfo {
  const PreflightInfo({
    required this.expectedSize,
    required this.resumable,
    required this.contentType,
    this.disposition,
  });

  final int? expectedSize;
  final bool resumable;
  final String? contentType;
  final String? disposition;
}

/// Top-level callback required by flutter_downloader. Forwards native
/// download events into the Dart service.
@pragma('vm:entry-point')
void drsDownloadCallback(String id, int status, int progress) {
  DownloadService.instance?.handleNativeCallback(id, status, progress);
}

/// Real download engine on top of flutter_downloader (WorkManager):
/// background tasks, pause/resume/cancel/retry, queue with priorities,
/// speed and ETA calculation, integrity validation.
class DownloadService extends ChangeNotifier {
  DownloadService({
    required PreferencesService prefs,
    required DownloadRepository downloads,
    required LibraryRepository library,
    required ConnectivityService connectivity,
    required NotificationService notifications,
  })  : _prefs = prefs,
        _repo = downloads,
        _library = library,
        _connectivity = connectivity,
        _notifications = notifications;

  static DownloadService? instance;

  final PreferencesService _prefs;
  final DownloadRepository _repo;
  final LibraryRepository _library;
  final ConnectivityService _connectivity;
  final NotificationService _notifications;

  final Map<String, List<(DateTime, int)>> _samples = {}; // taskId -> samples
  final Map<String, double> _speeds = {}; // taskId -> bytes/s
  final Map<String, int> _retryCount = {}; // our id -> auto retries

  /// Engine progress tracking for the service-side freeze watchdog:
  /// bytes may tick (progress timer) without actually moving — we track
  /// CHANGES, not callbacks.
  final Map<String, int> _engineLastBytes = {};
  final Map<String, DateTime> _engineLastMove = {};

  /// One notification per file per window — see NotificationService.
  void _showFailNotif(DownloadTaskModel t, String reason) {
    unawaited(_notifications.showDownloadFailedDeduped(t.fileName, reason));
  }

  final Map<String, int> _resolveRetries = {}; // our id -> re-resolve retries

  /// Cross-session failure chain (persisted per task): how many FINAL
  /// failures in a row (across app restarts) this task accumulated by
  /// automatic recovery alone. At the ceiling the task stays paused — the
  /// user retries by hand, which resets the chain. This is what stops the
  /// post-update notification storms: dead links are no longer
  /// auto-reattacked on every launch / wifi flip.
  static const int maxFailChain = 2;

  int _failChain(String id) => _prefs.downloadFailChain(id);

  void _bumpFailChain(String id) =>
      _prefs.setDownloadFailChain(id, _failChain(id) + 1);

  void _resetFailChain(String id) => _prefs.setDownloadFailChain(id, 0);

  bool _chainBlocked(DownloadTaskModel t) =>
      failChainBlocksAutoRestart(_failChain(t.id));

  /// v1.14.4: live chunked engines (task.id -> engine) plus the tasks that
  /// already fell back to the native engine (server ignores Range — never
  /// try the chunked engine twice, it would loop).
  final Map<String, ChunkedDownloadEngine> _engines = {};
  final Set<String> _engineFellBack = {};

  /// v1.14.4: engine tasks the user paused this session — their run()
  /// future returning failed must NOT be treated as a real failure.
  final Set<String> _enginePaused = {};

  /// v1.14.4: stall watchdog — native tasks whose progress freezes get a
  /// connection kick (pause+resume with Range), then promotion to the
  /// chunked engine. This is the direct fix for "stuck at 0% forever".
  final StallTracker _stall = StallTracker();
  Timer? _watchdog;

  /// Tasks the user paused by hand this session (v1.8.0): auto-resume on
  /// WiFi must never override an explicit user decision.
  final Set<String> _userPaused = {};

  bool _initialized = false;
  bool _degraded = false;
  String? _initError;
  String? _defaultDir;
  bool _waitingForWifi = false;

  List<DownloadTaskModel> _tasks = [];
  List<DownloadTaskModel> get tasks => List.unmodifiable(_tasks);
  double? speedOf(String id) => _speeds[id];
  bool get waitingForWifi => _waitingForWifi;

  /// True when the native engine failed to initialize; the app still runs
  /// and this screen shows a retry action instead of crashing.
  bool get degraded => _degraded;
  String? get initError => _initError;

  int get activeCount => _tasks.where((t) => t.status == DownloadStatus.running).length;
  int get queuedCount => _tasks.where((t) => t.status == DownloadStatus.queued).length;

  /// Failure-tolerant startup: never throws. Any failure degrades the
  /// service (visible retry state) instead of killing the whole app.
  Future<void> init() async {
    if (_initialized) return;
    try {
      await FlutterDownloader.initialize(debug: kDebugMode, ignoreSsl: false);
      FlutterDownloader.registerCallback(drsDownloadCallback);
      _defaultDir = _prefs.downloadDir ?? await _ensureDefaultDir();
      await _syncWithNative();
      _connectivity.addListener(_pump);
      _watchdog ??= Timer.periodic(const Duration(seconds: 15), (_) {
        unawaited(_watchdogTick());
      });
      _initialized = true;
      AppLogger.instance.info('dl', 'initialized, dir=$_defaultDir');
    } catch (e, s) {
      _degraded = true;
      _initError = e.toString();
      AppLogger.instance.error('dl', 'init failed (degraded)', e, s);
    }
  }

  /// User-facing recovery for the degraded state.
  Future<void> retryInit() async {
    _degraded = false;
    _initError = null;
    await init();
    notifyListeners();
  }

  Future<String> _ensureDefaultDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/downloads');
    if (!dir.existsSync()) await dir.create(recursive: true);
    _prefs.downloadDir = dir.path;
    return dir.path;
  }

  Future<String> get downloadDir async =>
      _defaultDir ??= _prefs.downloadDir ?? await _ensureDefaultDir();

  /// Reconciles our DB with the native WorkManager truth (e.g. after the
  /// app was killed while downloads were running).
  Future<void> _syncWithNative() async {
    final native = await FlutterDownloader.loadTasks();
    final dbTasks = await _repo.all();
    final byTaskId = {for (final t in dbTasks) if (t.taskId != null) t.taskId!: t};

    for (final n in native ?? <DownloadTask>[]) {
      final t = byTaskId[n.taskId];
      if (t == null) continue;
      final mapped = _mapStatus(n.status);
      if (mapped != t.status || n.progress != t.progress) {
        t.status = mapped;
        t.progress = n.progress;
        await _repo.update(t);
      }
      if (mapped == DownloadStatus.completed) {
        await _onNativeComplete(t);
      }
    }
    // Any row still "running" without a live native task becomes paused —
    // v1.14.4: EXCEPT engine tasks (pseudo task id), which re-queue so the
    // pump restarts them and the sidecar resumes exact byte watermarks.
    for (final t in dbTasks) {
      if (t.status == DownloadStatus.running &&
          !((native ?? []).any((n) => n.taskId == t.taskId))) {
        if (t.taskId != null && t.taskId!.startsWith('engine_')) {
          t.status = DownloadStatus.queued;
        } else {
          t.status = DownloadStatus.paused;
        }
        await _repo.update(t);
      }
    }
    _tasks = await _repo.all();
    notifyListeners();
  }

  DownloadStatus _mapStatus(DownloadTaskStatus s) => switch (s) {
        DownloadTaskStatus.enqueued => DownloadStatus.queued,
        DownloadTaskStatus.running => DownloadStatus.running,
        DownloadTaskStatus.complete => DownloadStatus.completed,
        DownloadTaskStatus.failed => DownloadStatus.failed,
        DownloadTaskStatus.canceled => DownloadStatus.cancelled,
        DownloadTaskStatus.paused => DownloadStatus.paused,
        DownloadTaskStatus.undefined => DownloadStatus.failed,
      };

  /// Starts a download for a media URL. Throws [AppException] on pre-flight
  /// failures (invalid URL, no space, network gate).
  ///
  /// v1.14.1 platform fix: share links (TikTok vm./vt., X, Facebook) are
  /// HTML *pages*, not media. They are resolved into the real stream URL
  /// (with CDN headers) BEFORE probing/enqueuing, and a page-like probe
  /// response aborts with a clear error instead of saving a .txt/.html
  /// document that pretends to be the video.
  ///
  /// v1.14.2 speed fix: [resolvedMedia] + [preflight] come from the sheet's
  /// single probe pass — when provided, resolution and HEAD/range probing
  /// are SKIPPED here (the flow runs each step exactly once).
  Future<DownloadTaskModel> start({
    required String url,
    required String title,
    String? sourceId,
    Map<String, String>? headers,
    DownloadPriority priority = DownloadPriority.normal,
    String? desiredFileName,
    ResolvedPlatformMedia? resolvedMedia,
    PreflightInfo? preflight,
  }) async {
    // Lazy init: WorkManager is no longer touched at app boot (v1.0.2
    // startup hardening); initialize right before the first real use.
    await init();
    final dir = await downloadDir;
    final originUrl = url; // v1.14.2: kept for signed-URL re-resolve

    // --- platform page → direct media ---------------------------------
    ResolvedPlatformMedia? resolved = resolvedMedia;
    if (resolved == null && PlatformDownloadResolver.needsResolution(url)) {
      resolved = await PlatformDownloadResolver.instance.resolve(url);
      if (resolved == null) {
        // Honest failure: we refuse to enqueue an HTML page. The sheet
        // maps invalidInput to a message telling the user to re-copy the
        // share link or open the page in the built-in browser.
        AppLogger.instance.warning('dl', 'platform resolve failed: $url');
        throw const AppException(AppErrorType.invalidInput);
      }
    }
    if (resolved != null) {
      url = resolved.directUrl;
      headers = <String, String>{...?headers, ...resolved.headers};
      final rt = resolved.title;
      if (rt != null && rt.isNotEmpty &&
          (title.trim().isEmpty || title.trim() == 'download')) {
        title = rt;
      }
      AppLogger.instance.info('dl',
          'resolved ${resolved.platform} link → ${Uri.parse(url).host}');
    }

    // Pre-flight: probe size/resume support (real HEAD request). v1.14.2:
    // skipped entirely when the sheet already probed with the same URL.
    int? expectedSize;
    var resumable = false;
    String? probedMime;
    String? disposition;
    if (preflight != null) {
      expectedSize = preflight.expectedSize;
      resumable = preflight.resumable;
      probedMime = preflight.contentType;
      disposition = preflight.disposition;
      AppLogger.instance.info('dl',
          'preflight reused: size=$expectedSize mime=$probedMime');
    } else {
      try {
        final res = await DioClient.instance.head(url,
            headers: headers, timeout: const Duration(seconds: 8));
        final len = res.headers.value(HttpHeaders.contentLengthHeader);
        expectedSize = len == null ? null : int.tryParse(len.trim());
        final range = res.headers.value(HttpHeaders.acceptRangesHeader) ?? '';
        resumable = range.toLowerCase() == 'bytes';
        probedMime = res.headers.value(HttpHeaders.contentTypeHeader);
        disposition = res.headers.value('content-disposition');
        AppLogger.instance
            .info('dl', 'probe ok: size=$expectedSize resumable=$resumable');
      } on AppException catch (e) {
        if (e.type == AppErrorType.notFound ||
            e.type == AppErrorType.forbidden) {
          rethrow;
        }
        AppLogger.instance.warning('dl', 'probe failed, continuing anyway: $e');
        // v1.14.1: HEAD-hostile CDNs (TikTok answers 503 to HEAD while GET
        // works) — a 1-byte range GET recovers mime/size/resume so the HTML
        // guard and integrity check still see the truth.
        try {
          final r = await DioClient.instance.rangeProbe(url, headers: headers);
          final cr = r.headers.value('content-range');
          final m =
              RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(cr ?? '');
          if (m != null) expectedSize = int.tryParse(m.group(1)!);
          probedMime = r.headers.value(HttpHeaders.contentTypeHeader);
          disposition = r.headers.value('content-disposition');
          resumable = (r.statusCode ?? 0) == 206;
          AppLogger.instance.info(
              'dl', 'range probe ok: size=$expectedSize mime=$probedMime');
        } catch (e2) {
          AppLogger.instance
              .warning('dl', 'range probe failed too: $e2 (continuing)');
        }
      }
    }

    // --- v1.14.1: HTML guard -------------------------------------------
    // A page-like response means this URL is still a web page (extraction
    // failed / interstitial / login wall). NEVER save it as the file the
    // user believes is the video — that is exactly the .txt bug.
    if (PlatformDownloadResolver.shouldAbortAsPageSave(
        contentType: probedMime, url: url)) {
      AppLogger.instance
          .warning('dl', 'blocked page-like save: $probedMime $url');
      throw const AppException(AppErrorType.invalidInput);
    }

    // Storage check.
    if (expectedSize != null) {
      final free = await NativeChannel.instance.freeSpaceBytes(dir);
      if (free >= 0 && free < expectedSize + (50 * 1024 * 1024)) {
        throw const AppException(AppErrorType.storage);
      }
    }

    // Unique, sanitized file name (path traversal safe). v1.14.0: the
    // fallback extension now follows the probed content-type so ANY kind of
    // file downloads with the right extension (video/audio/image/archive…).
    final urlExt = _extOf(url, '');
    final fallbackExt = DownloadClassifier.extensionFor(
        url: url, contentType: probedMime);
    final ext = urlExt.isNotEmpty ? urlExt : fallbackExt;
    var name = desiredFileName ??
        FileNameSuggester.suggest(
          url: url,
          contentType: probedMime,
          disposition: disposition,
          fallback: title,
        );
    if (!name.toLowerCase().endsWith('.$ext')) name = '$name.$ext';
    name = _uniqueName(dir, name);

    final task = DownloadTaskModel(
      id: 'dl_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      url: url,
      savedDir: dir,
      fileName: name,
      status: DownloadStatus.queued,
      expectedSize: expectedSize,
      priority: priority,
      headers: (headers == null || headers.isEmpty) ? null : headers,
      originUrl: (resolved != null && originUrl != url) ? originUrl : null,
    );
    await _repo.insert(task);
    _tasks = await _repo.all();
    notifyListeners();
    unawaited(_pump());
    return task;
  }

  static String _extOf(String url, String fallback) {
    final clean = url.split('?').first.split('#').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1 || clean.length - dot > 6) return fallback;
    return clean.substring(dot + 1).toLowerCase();
  }

  String _uniqueName(String dir, String desired) {
    var name = desired.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (File('$dir/$name').existsSync()) {
      name = '$base ($i)$ext';
      i++;
    }
    return name;
  }

  /// Scheduler: fills free slots from the queue honoring priorities,
  /// Wi-Fi-only policy and user-configured concurrency.
  ///
  /// P4-M1: _pump is fired from 15+ sites — several fire-and-forget
  /// (native paused/cancelled callbacks, the connectivity listener) —
  /// and mutates shared scheduler state across many awaits (slot
  /// counting, _engines, task rows). Two overlapping passes both counted
  /// the same free slots and BOTH started the same queued task
  /// (double-enqueue → two engines writing one file). Every pass now
  /// runs strictly serialized in request order; the body is wrapped so
  /// a failing pass can never break the chain or leak an unhandled
  /// zone error.
  final SerializedRunner _pumpGate = SerializedRunner();

  Future<void> _pump() => _pumpGate.run(_runPump);

  Future<void> _runPump() async {
    try {
      await _pumpBody();
    } catch (e, s) {
      AppLogger.instance.error('dl', 'pump pass failed: $e', e, s);
    }
  }

  Future<void> _pumpBody() async {
    await init();
    final wifi = _connectivity.isWifi;
    _waitingForWifi = false;

    if (_prefs.wifiOnlyDownloads && !wifi) {
      _waitingForWifi = _tasks.any((t) => t.status == DownloadStatus.queued);
      if (_waitingForWifi) notifyListeners();
      return;
    }

    // v1.8.0: WiFi returned — silently resume tasks that were paused
    // because of a missing connection. Tasks the user paused by hand stay
    // paused (session-scoped _userPaused set) so we never fight the user.
    if (wifi && _prefs.autoResumeOnWifi) {
      final waiting = _tasks
          .where((t) =>
              t.status == DownloadStatus.paused &&
              !_userPaused.contains(t.id) &&
              !_chainBlocked(t)) // v1.14.7: dead links stay paused
          .toList();
      for (final t in waiting) {
        if (t.taskId != null) {
          await FlutterDownloader.resume(taskId: t.taskId!);
          t.status = DownloadStatus.running;
          await _repo.update(t);
        } else {
          t.status = DownloadStatus.queued;
          await _repo.update(t);
        }
      }
      if (waiting.isNotEmpty) {
        AppLogger.instance.info('dl', 'auto-resumed ${waiting.length} on wifi');
      }
    }

    final running = _tasks.where((t) => t.status == DownloadStatus.running).length;
    var slots = _prefs.maxConcurrentDownloads - running;
    if (slots <= 0) return;

    // v1.14.7 cross-session fail-chain: queued tasks that already burned
    // their automatic recovery budget in previous sessions are parked as
    // paused (visible retry button). Nothing auto-attacks dead links on
    // launch — the notification storm source is closed.
    for (final t in _tasks
        .where((t) => t.status == DownloadStatus.queued && _chainBlocked(t))
        .toList()) {
      t.status = DownloadStatus.paused;
      await _repo.update(t);
      AppLogger.instance.info(
          'dl', 'fail-chain parked ${t.fileName} (chain=${_failChain(t.id)})');
    }

    final queue = _tasks
        .where((t) => t.status == DownloadStatus.queued)
        .toList()
      ..sort(compareQueueOrder);

    for (final task in queue) {
      if (slots <= 0) break;
      // v1.14.4: large platform-resolved files run on the stall-proof
      // chunked engine (parallel Range segments + auto-resume). Servers
      // that ignore Range fall back to the native engine exactly once.
      if (!_engineFellBack.contains(task.id) && engineEligible(task.expectedSize)) {
        try {
          final partial = File(task.filePath);
          final seed = partial.existsSync() ? partial.lengthSync() : 0;
          final free = await NativeChannel.instance.freeSpaceBytes(task.savedDir);
          final engine = ChunkedDownloadEngine(
            url: task.url,
            headers: task.headers ?? const {},
            filePath: task.filePath,
            total: task.expectedSize!,
            maxSegments: segmentCountFor(task.expectedSize!, freeBytes: free),
            seedOffset: seed,
            onProgress: (bytes) => _onEngineProgress(task.id, bytes),
            onLog: (m) => AppLogger.instance
                .info('dl-engine', '${task.fileName}: $m'),
          );
          _engines[task.id] = engine;
          task.taskId = 'engine_${task.id}';
          task.status = DownloadStatus.running;
          await _repo.update(task);
          _stall.forget(task.id);
          _samples[task.taskId!] = [(DateTime.now(), 0)];
          slots--;
          unawaited(_runEngine(task, engine));
          AppLogger.instance.info('dl',
              'chunked engine started ${task.fileName} (${task.expectedSize} B, seed=$seed)');
          continue;
        } catch (e) {
          AppLogger.instance.warning('dl', 'engine start failed: $e');
          _engines.remove(task.id);
          _engineFellBack.add(task.id);
          // fall through to the native engine below
        }
      }
      try {
        final taskId = await FlutterDownloader.enqueue(
          url: task.url,
          savedDir: task.savedDir,
          fileName: task.fileName,
          // v1.14.7: progress lives in the downloads screen + throttled
          // local notifications — native per-task notifications were one
          // side of the endless-notification-storm report.
          showNotification: false,
          openFileFromNotification: false,
          // v1.14.1: CDN headers (User-Agent/Referer) now travel with the
          // native task — web-scrape addresses 403 without them.
          headers: task.headers ?? const {},
        );
        if (taskId == null) {
          throw StateError('enqueue returned null');
        }
        task.taskId = taskId;
        task.status = DownloadStatus.running;
        await _repo.update(task);
        _samples[taskId] = [(DateTime.now(), task.bytesDone)];
        _stall.touch(task.id);
        slots--;
        AppLogger.instance.info('dl', 'started ${task.fileName}');
      } catch (e) {
        task.status = DownloadStatus.failed;
        task.error = e.toString();
        await _repo.update(task);
        AppLogger.instance.error('dl', 'enqueue failed: $e');
      }
    }
    _tasks = await _repo.all();
    notifyListeners();
  }

  DownloadStatus _statusFromRaw(int raw) => switch (raw) {
        1 => DownloadStatus.queued,
        2 => DownloadStatus.running,
        3 => DownloadStatus.completed,
        4 => DownloadStatus.failed,
        5 => DownloadStatus.cancelled,
        6 => DownloadStatus.paused,
        _ => DownloadStatus.failed,
      };

  void handleNativeCallback(String taskId, int nativeStatus, int progress) {
    DownloadTaskModel? task;
    for (final t in _tasks) {
      if (t.taskId == taskId) {
        task = t;
        break;
      }
    }
    if (task == null) return;
    final status = _statusFromRaw(nativeStatus);
    if (progress > task.progress) _stall.touch(task.id);
    _trackSpeed(taskId, task, progress);
    _maybePersist(task, status, progress);

    if (status == DownloadStatus.completed) {
      unawaited(_onNativeComplete(task));
    } else if (status == DownloadStatus.failed) {
      unawaited(_onNativeFailed(task));
    } else if (status == DownloadStatus.paused ||
        status == DownloadStatus.cancelled) {
      unawaited(_pump());
    }
    notifyListeners();
  }

  void _trackSpeed(String taskId, DownloadTaskModel task, int progress) {
    final bytes = task.expectedSize == null ? 0 : task.expectedSize! * progress ~/ 100;
    final samples = _samples.putIfAbsent(taskId, () => []);
    final now = DateTime.now();
    samples.add((now, bytes));
    while (samples.length > 12) {
      samples.removeAt(0);
    }
    if (samples.length >= 2) {
      final first = samples.first;
      final dt = now.difference(first.$1).inMilliseconds;
      if (dt > 500) {
        _speeds[task.id] = (bytes - first.$2) * 1000 / dt;
      }
    }
  }

  void _maybePersist(DownloadTaskModel task, DownloadStatus status, int progress) {
    // Persist meaningful transitions or ~2% deltas to limit DB churn.
    final delta = (progress - task.progress).abs();
    if (status != task.status || delta >= 2) {
      task.status = status;
      task.progress = progress;
      unawaited(_repo.update(task));
    }
  }

  Future<void> _onNativeComplete(DownloadTaskModel task) async {
    // Integrity validation: file exists and size matches when known.
    final file = File(task.filePath);
    if (!file.existsSync()) {
      task.status = DownloadStatus.failed;
      task.error = 'missing after completion';
      await _repo.update(task);
      return;
    }
    final actual = file.lengthSync();
    if (task.expectedSize != null && task.expectedSize! > 0) {
      final tolerance = task.expectedSize! * 0.02;
      if ((actual - task.expectedSize!).abs() > tolerance) {
        task.status = DownloadStatus.failed;
        task.error = 'size mismatch: $actual != ${task.expectedSize}';
        await _repo.update(task);
        if (_prefs.notifyDownloadError) {
          _showFailNotif(task, 'corrupted');
        }
        return;
      }
    }
    task.status = DownloadStatus.completed;
    task.progress = 100;
    task.completedAt = DateTime.now();
    await _repo.update(task);

    await NativeChannel.instance.scanFile(task.filePath);

    // Register in the library as a playable downloaded item.
    var item = await _library.byUri(task.filePath);
    if (item == null) {
      item = MediaItem(
        id: 'md_${task.id}',
        title: task.fileName.replaceAll(RegExp(r'\.[a-z0-9]+$'), ''),
        uri: task.filePath,
        type: MediaItemType.download,
        sourceId: 'downloads',
        sizeBytes: actual,
        durationMs: null,
        addedAt: DateTime.now(),
      );
      await _library.upsert(item);
      task.mediaItemId = item.id;
      await _repo.update(task);
    }
    if (_prefs.notifyDownloadDone) {
      await _notifications.showDownloadCompleted(task.fileName);
    }
    await _pump();
    notifyListeners();
  }

  /// v1.14.2 pure retry gate: a task re-resolves from its origin link when
  /// the origin is a platform share page and the session re-resolve budget
  /// (2) is not exhausted. Signed CDN URLs expire — same-URL retries can
  /// never recover them.
  static bool shouldReresolveOnFailure({String? originUrl, required int attempts}) {
    if (originUrl == null) return false;
    if (attempts >= 2) return false;
    return PlatformDownloadResolver.needsResolution(originUrl);
  }

  Future<void> _onNativeFailed(DownloadTaskModel task) async {
    // v1.14.2: platform share links resolve to SIGNED CDN URLs that
    // expire — retrying the same dead URL can NEVER succeed. When the task
    // carries its origin link, re-resolve it into a fresh URL and enqueue
    // a new native task (max 2 times per session per task).
    final origin = task.originUrl;
    if (origin != null &&
        shouldReresolveOnFailure(
            originUrl: origin, attempts: _resolveRetries[task.id] ?? 0)) {
      _resolveRetries[task.id] = (_resolveRetries[task.id] ?? 0) + 1;
      try {
        final fresh = await PlatformDownloadResolver.instance.resolve(origin);
        if (fresh != null) {
          if (task.taskId != null) {
            await FlutterDownloader.remove(
                taskId: task.taskId!, shouldDeleteContent: true);
          }
          task.url = fresh.directUrl;
          if (fresh.headers.isNotEmpty) task.headers = fresh.headers;
          task.progress = 0;
          task.error = null;
          final newTaskId = await FlutterDownloader.enqueue(
            url: task.url,
            savedDir: task.savedDir,
            fileName: task.fileName,
            // v1.14.7: silent re-enqueues — automatic recovery must never
            // spawn fresh native notifications (notification storm fix).
            showNotification: false,
            openFileFromNotification: false,
            headers: task.headers ?? const {},
          );
          task.taskId = newTaskId;
          task.status = DownloadStatus.running;
          await _repo.update(task);
          _samples[newTaskId ?? task.id] = [(DateTime.now(), 0)];
          AppLogger.instance.info('dl',
              're-resolved ${task.fileName} → fresh native task (attempt ${_resolveRetries[task.id]})');
          notifyListeners();
          return;
        }
      } catch (e) {
        AppLogger.instance.warning('dl', 're-resolve retry failed: $e');
      }
    }

    // Deterministic auto-retry: one extra attempt with backoff.
    final tries = _retryCount.putIfAbsent(task.id, () => 0);
    if (tries < 1 && task.taskId != null) {
      _retryCount[task.id] = tries + 1;
      await Future.delayed(const Duration(seconds: 3));
      await FlutterDownloader.retry(taskId: task.taskId!);
      AppLogger.instance.info('dl', 'auto retry ${task.fileName}');
      return;
    }
    task.status = DownloadStatus.failed;
    task.error ??= 'unknown error';
    await _repo.update(task);
    _bumpFailChain(task.id);
    if (_prefs.notifyDownloadError) {
      _showFailNotif(task, task.error ?? '');
    }
    await _pump();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // v1.14.4 stall-proof machinery
  // ---------------------------------------------------------------------

  static bool isEngineTask(DownloadTaskModel t) =>
      t.taskId != null && t.taskId!.startsWith('engine_');

  /// Runs the engine future and routes the outcome. Kept separate so the
  /// pump never awaits a whole download.
  Future<void> _runEngine(
      DownloadTaskModel task, ChunkedDownloadEngine engine) async {
    final outcome = await engine.run();
    // Re-read the task: other transitions may have touched it meanwhile.
    final t = _byId(task.id);
    if (t == null) {
      _engines.remove(task.id);
      return;
    }
    switch (outcome) {
      case ChunkedEngineOutcome.completed:
        _engines.remove(t.id);
        _stall.forget(t.id);
        await _onNativeComplete(t);
        break;
      case ChunkedEngineOutcome.nonResumable:
        // Server ignores Range: this engine can never help. Hand the task
        // to the native single-GET engine exactly once.
        _engines.remove(t.id);
        _engineFellBack.add(t.id);
        t.taskId = null;
        t.status = DownloadStatus.queued;
        await _repo.update(t);
        AppLogger.instance.info('dl',
            '${t.fileName}: server ignores Range → native engine fallback');
        await _pump();
        break;
      case ChunkedEngineOutcome.failed:
        _engines.remove(t.id);
        if (_enginePaused.contains(t.id)) {
          _enginePaused.remove(t.id);
          break; // user pause — state already persisted
        }
        await _onEngineFailed(t);
        break;
    }
    notifyListeners();
  }

  /// Engine byte watermark → task progress + real speed samples.
  void _onEngineProgress(String id, int bytes) {
    final task = _byId(id);
    if (task == null || !isEngineTask(task)) return;
    _stall.touch(id);
    if (_engineLastBytes[id] != bytes) {
      _engineLastBytes[id] = bytes; // track MOVEMENT, not callback ticks
      _engineLastMove[id] = DateTime.now();
    }
    final key = task.taskId ?? id;
    final samples = _samples.putIfAbsent(key, () => []);
    final now = DateTime.now();
    samples.add((now, bytes));
    while (samples.length > 12) {
      samples.removeAt(0);
    }
    if (samples.length >= 2) {
      final first = samples.first;
      final dt = now.difference(first.$1).inMilliseconds;
      if (dt > 500) {
        _speeds[task.id] = (bytes - first.$2) * 1000 / dt;
      }
    }
    final p = percentOf(bytes, task.expectedSize ?? 0).round();
    if (p != task.progress || task.status != DownloadStatus.running) {
      task.progress = p;
      task.status = DownloadStatus.running;
      unawaited(_repo.update(task));
      notifyListeners();
    }
  }

  /// Engine-level failure: re-resolve expired signed URLs (byte watermarks
  /// survive the URL swap), then deterministic engine restarts.
  Future<void> _onEngineFailed(DownloadTaskModel task) async {
    final origin = task.originUrl;
    if (origin != null &&
        shouldReresolveOnFailure(
            originUrl: origin, attempts: _resolveRetries[task.id] ?? 0)) {
      _resolveRetries[task.id] = (_resolveRetries[task.id] ?? 0) + 1;
      try {
        final fresh = await PlatformDownloadResolver.instance.resolve(origin);
        if (fresh != null) {
          task.url = fresh.directUrl;
          if (fresh.headers.isNotEmpty) task.headers = fresh.headers;
          task.error = null;
          task.status = DownloadStatus.running;
          await _repo.update(task);
          final engine = _buildEngine(task);
          _engines[task.id] = engine;
          AppLogger.instance.info('dl',
              're-resolved ${task.fileName} → engine restart (attempt ${_resolveRetries[task.id]})');
          unawaited(_runEngine(task, engine));
          return;
        }
      } catch (e) {
        AppLogger.instance.warning('dl', 'engine re-resolve failed: $e');
      }
    }
    final tries = _retryCount.putIfAbsent(task.id, () => 0);
    if (tries < 2) {
      _retryCount[task.id] = tries + 1;
      await Future.delayed(const Duration(seconds: 3));
      task.status = DownloadStatus.running;
      await _repo.update(task);
      final engine = _buildEngine(task);
      _engines[task.id] = engine;
      AppLogger.instance.info('dl',
          'engine auto-restart ${task.fileName} (try ${tries + 1})');
      unawaited(_runEngine(task, engine));
      return;
    }
    task.status = DownloadStatus.failed;
    task.error ??= 'network stall: segments exhausted';
    await _repo.update(task);
    _bumpFailChain(task.id);
    if (_prefs.notifyDownloadError) {
      _showFailNotif(task, task.error ?? '');
    }
    await _pump();
    notifyListeners();
  }

  ChunkedDownloadEngine _buildEngine(DownloadTaskModel task) {
    final partial = File(task.filePath);
    final seed = partial.existsSync() ? partial.lengthSync() : 0;
    return ChunkedDownloadEngine(
      url: task.url,
      headers: task.headers ?? const {},
      filePath: task.filePath,
      total: task.expectedSize!,
      seedOffset: seed,
      onProgress: (bytes) => _onEngineProgress(task.id, bytes),
      onLog: (m) =>
          AppLogger.instance.info('dl-engine', '${task.fileName}: $m'),
    );
  }

  /// Watchdog heartbeat: kick stalled native tasks (pause+resume forces a
  /// fresh TCP connection with Range), then promote them to the chunked
  /// engine when kicks are exhausted. v1.14.7 also watches ENGINE tasks
  /// (previously excluded — a frozen watermark stayed 'running' forever,
  /// the other half of the 'download stays stuck' report) and fails any
  /// non-promotable native task instead of kicking it endlessly.
  Future<void> _watchdogTick() async {
    if (!_initialized) return;
    final stalled = _tasks
        .where((t) =>
            t.status == DownloadStatus.running &&
            !isEngineTask(t) &&
            t.taskId != null &&
            _stall.isStalled(t.id))
        .toList();
    for (final t in stalled) {
      final escalated = _stall.kick(t.id);
      if (!escalated) {
        try {
          await FlutterDownloader.pause(taskId: t.taskId!);
          await Future.delayed(const Duration(milliseconds: 500));
          await FlutterDownloader.resume(taskId: t.taskId!);
          AppLogger.instance
              .info('dl', 'stall kick ${t.fileName} (connection restarted)');
        } catch (e) {
          AppLogger.instance.warning('dl', 'stall kick failed: $e');
        }
      } else if (!engineEligible(t.expectedSize)) {
        // v1.14.7: cannot be promoted (unknown size) — fail LOUDLY instead
        // of pause/resume-kicking the same dead task every 45s forever
        // (each kick re-raised its native notification).
        try {
          await FlutterDownloader.cancel(taskId: t.taskId!);
        } catch (_) {}
        _stall.forget(t.id);
        t.status = DownloadStatus.failed;
        t.error = 'stalled repeatedly — tap retry';
        await _repo.update(t);
        _bumpFailChain(t.id);
        if (_prefs.notifyDownloadError) {
          _showFailNotif(t, t.error ?? '');
        }
        await _pump();
        notifyListeners();
      } else {
        await _promoteToEngine(t);
      }
    }
    await _watchEngineFreezes();
  }

  /// v1.14.7: engine tasks with a frozen watermark (no byte movement for
  /// 3 minutes while claiming to run) are failed with a clear reason.
  static const Duration _engineFreezeLimit = Duration(minutes: 3);

  Future<void> _watchEngineFreezes() async {
    final now = DateTime.now();
    final frozen = _tasks
        .where((t) =>
            t.status == DownloadStatus.running &&
            isEngineTask(t) &&
            _engineLastMove[t.id] != null &&
            now.difference(_engineLastMove[t.id]!) > _engineFreezeLimit)
        .toList();
    for (final t in frozen) {
      _engines.remove(t.id)?.pause();
      t.status = DownloadStatus.failed;
      t.error = 'connection froze — tap retry (progress kept)';
      await _repo.update(t);
      _engineLastBytes.remove(t.id);
      _engineLastMove.remove(t.id);
      _stall.forget(t.id);
      AppLogger.instance.warning('dl', 'engine freeze-fail ${t.fileName}');
      if (_prefs.notifyDownloadError) {
        _showFailNotif(t, t.error ?? '');
      }
    }
    if (frozen.isNotEmpty) {
      await _pump();
      notifyListeners();
    }
  }

  /// Moves a stalled native task onto the chunked engine, seeding from the
  /// native partial file so no bytes are wasted.
  Future<void> _promoteToEngine(DownloadTaskModel t) async {
    if (!engineEligible(t.expectedSize)) return; // native retries continue
    try {
      await FlutterDownloader.cancel(taskId: t.taskId!);
    } catch (_) {}
    _stall.forget(t.id);
    _samples.remove(t.taskId);
    t.taskId = null;
    t.status = DownloadStatus.queued;
    await _repo.update(t);
    AppLogger.instance
        .info('dl', 'promoted ${t.fileName} to chunked engine');
    await _pump();
  }

  Future<void> pause(String id) async {
    await init();
    final t = _byId(id);
    if (t == null) return;
    if (isEngineTask(t)) {
      _userPaused.add(id);
      _enginePaused.add(id);
      _engines[id]?.pause();
      t.status = DownloadStatus.paused;
      await _repo.update(t);
      notifyListeners();
      return;
    }
    if (t.taskId == null) return;
    _userPaused.add(id);
    await FlutterDownloader.pause(taskId: t.taskId!);
    t.status = DownloadStatus.paused;
    await _repo.update(t);
    await _pump();
    notifyListeners();
  }

  Future<void> resume(String id) async {
    await init();
    final t = _byId(id);
    if (t == null) return;
    _userPaused.remove(id);
    _enginePaused.remove(id);
    if (isEngineTask(t) || t.taskId == null) {
      // Engine tasks re-queue: the pump restarts them and the sidecar
      // resumes exact byte watermarks.
      t.status = DownloadStatus.queued;
      await _repo.update(t);
      await _pump();
    } else {
      await FlutterDownloader.resume(taskId: t.taskId!);
      t.status = DownloadStatus.running;
      await _repo.update(t);
      _stall.touch(id);
    }
    notifyListeners();
  }

  Future<void> cancel(String id) async {
    final t = _byId(id);
    if (t == null) return;
    if (isEngineTask(t)) {
      final engine = _engines.remove(id);
      if (engine != null) {
        await engine.cancelAndCleanup();
      } else {
        await _cleanupEngineArtifacts(t);
      }
      _engineLastBytes.remove(id);
      _engineLastMove.remove(id);
    } else if (t.taskId != null) {
      await FlutterDownloader.cancel(taskId: t.taskId!);
    }
    _stall.forget(id);
    t.status = DownloadStatus.cancelled;
    await _repo.update(t);
    await _pump();
    notifyListeners();
  }

  /// Removes leftover part files + sidecar of an engine task.
  Future<void> _cleanupEngineArtifacts(DownloadTaskModel t) async {
    for (final p in [
      '${t.filePath}.drsmeta',
      '${t.filePath}.drsmeta.tmp',
      for (var i = 0; i < 4; i++) '${t.filePath}.part$i',
    ]) {
      try {
        final f = File(p);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> retry(String id) async {
    await init();
    final t = _byId(id);
    if (t == null) return;
    _retryCount.remove(id);
    _stall.forget(id);
    // Manual retry is an explicit user decision — it resets the
    // cross-session failure chain and un-parks the task.
    _resetFailChain(id);
    if (isEngineTask(t)) {
      t.status = DownloadStatus.queued;
    } else if (t.taskId != null) {
      await FlutterDownloader.retry(taskId: t.taskId!);
      t.status = DownloadStatus.running;
    } else {
      t.status = DownloadStatus.queued;
    }
    await _repo.update(t);
    await _pump();
    notifyListeners();
  }

  /// Removes the record and optionally the downloaded content.
  Future<void> remove(String id, {bool deleteFile = false}) async {
    final t = _byId(id);
    if (t == null) return;
    if (isEngineTask(t)) {
      _engines.remove(id)?.pause();
      _engineLastBytes.remove(id);
      _engineLastMove.remove(id);
      if (deleteFile) {
        await _cleanupEngineArtifacts(t);
        final f = File(t.filePath);
        if (f.existsSync()) await f.delete();
      }
    } else if (t.taskId != null) {
      await FlutterDownloader.remove(
          taskId: t.taskId!, shouldDeleteContent: deleteFile);
    } else if (deleteFile) {
      final f = File(t.filePath);
      if (f.existsSync()) await f.delete();
    }
    if (t.mediaItemId != null) {
      await _library.delete(t.mediaItemId!);
    }
    await _repo.delete(id);
    _speeds.remove(id);
    _tasks = await _repo.all();
    notifyListeners();
  }

  Future<void> setPriority(String id, DownloadPriority p) async {
    final t = _byId(id);
    if (t == null) return;
    t.priority = p;
    await _repo.update(t);
    await _pump();
    notifyListeners();
  }

  Future<void> pauseAll() async {
    for (final t in _tasks.where((t) => t.status == DownloadStatus.running).toList()) {
      await pause(t.id);
    }
  }

  Future<void> resumeAll() async {
    for (final t in _tasks
        .where((t) => t.status == DownloadStatus.paused || t.status == DownloadStatus.queued)
        .toList()) {
      await resume(t.id);
    }
  }

  /// Re-enqueues every failed task that hasn't exhausted its auto-retries
  /// (v1.8.0 downloads v2: one-tap recovery from the toolbar).
  Future<void> retryAll() async {
    await init();
    final failed = _tasks.where((t) => t.status == DownloadStatus.failed).toList();
    for (final t in failed) {
      _retryCount.remove(t.id);
      await retry(t.id);
    }
    if (failed.isNotEmpty) {
      AppLogger.instance.info('dl', 'retryAll: ${failed.length} tasks');
      notifyListeners();
    }
  }

  DownloadTaskModel? _byId(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Estimated remaining bytes for the storage warning notification.
  Future<void> checkStorageWarning() async {
    if (!_prefs.notifyStorageWarning) return;
    final dir = await downloadDir;
    final free = await NativeChannel.instance.freeSpaceBytes(dir);
    if (free >= 0 && free < 300 * 1024 * 1024 && activeCount > 0) {
      await _notifications.showStorageWarning();
    }
  }
}

/// Pure cross-session gate: a task whose automatic recovery produced
/// [chain] consecutive final failures stays parked until the user retries
/// by hand (which resets the chain). Kills the post-update notification
/// storm — dead links are never auto-reattacked on every launch/wifi flip.
bool failChainBlocksAutoRestart(int chain, {int max = 2}) => chain >= max;
