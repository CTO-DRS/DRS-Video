import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/storage/preferences_service.dart';
import '../../core/utils/logger.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../recommendations/playback_optimizer.dart';
import '../smart/intel_v2.dart';
import '../smart/intel_v3.dart';
import '../subtitles/subtitle_translator.dart';
import 'ab_repeat.dart';
import 'audio_enhancer.dart';
import 'audio_handler.dart';
import 'sleep_timer.dart';
import 'subtitle_charset.dart';
import 'subtitle_parser.dart';

enum RepeatMode { off, all, one }

/// Global playback facade over media_kit: queue, progress persistence,
/// tracks, subtitles, sleep timer and background audio.
///
/// Lives for the entire app session so playback (and the mini player)
/// survives screen navigation.
class PlayerService extends ChangeNotifier {
  PlayerService({
    required PreferencesService prefs,
    required HistoryRepository history,
    required LibraryRepository library,
    required ConnectivityService connectivity,
    bool createEngineNow = true,
  })  : _prefs = prefs,
        _history = history,
        _library = library,
        _connectivity = connectivity {
    sleepTimer.addListener(_onSleepTimerTick);
    if (createEngineNow) _createEngine();
  }

  bool _creatingEngine = false;

  /// Lazily creates the native engine. Called on first real playback
  /// (open/retry) — NEVER at app boot, so a native libmpv failure can
  /// never abort startup. Idempotent and re-entrancy safe.
  Future<void> ensureEngine() async {
    if (_player != null || _creatingEngine) return;
    _creatingEngine = true;
    try {
      _createEngine();
    } finally {
      _creatingEngine = false;
    }
    notifyListeners();
  }

  /// Creates the native mpv engine. NEVER throws: on devices where the
  /// native lib cannot load the app still runs and the player UI shows a
  /// real error state with a retry action.
  void _createEngine() {
    try {
      // Registers the native libmpv bindings; must precede Player()
      // and is safe to call repeatedly.
      MediaKit.ensureInitialized();
      final policy = const PlaybackOptimizer().optimize(
        connection: _connectivity.level,
        userQualitySetting: _prefs.defaultQuality,
        screenShortSideDp: 400,
      );
      final p = Player(
        configuration: PlayerConfiguration(
          bufferSize: policy.maxBufferSizeMb * 1024 * 1024,
          logLevel: MPVLogLevel.warn,
        ),
      );
      _videoController = VideoController(p);
      _player = p;
      _attachStreams();
      loadAudioEnhanceDefaults();
      AppLogger.instance.info('player', 'engine ready');
    } catch (e, s) {
      _player = null;
      _videoController = null;
      _engineError = e.toString();
      AppLogger.instance.error('player', 'engine init failed', e, s);
    }
  }

  final PreferencesService _prefs;
  final HistoryRepository _history;
  final LibraryRepository _library;
  final ConnectivityService _connectivity;

  /// Exposed for playback-policy refreshes from the UI layer.
  ConnectivityService get connectivity => _connectivity;

  Player? _player;
  VideoController? _videoController;
  String? _engineError;
  DrsAudioHandler? _audioHandler;
  StreamSubscription<Duration>? _posSub;

  /// True when the native engine is up.
  bool get engineReady => _player != null;

  /// True when the engine failed to initialize (degraded mode).
  bool get engineFailed => _engineError != null;
  String? get engineError => _engineError;

  /// Tries to bring the engine back (user-facing retry).
  Future<void> retryEngine() => ensureEngine();

  Player get _engine => _player ?? (throw StateError(_engineError ?? 'engine unavailable'));

  MediaItem? _current;
  List<MediaItem> _queue = [];
  int _queueIndex = -1;
  List<int> _shuffledOrder = [];
  RepeatMode _repeat = RepeatMode.off;
  bool _shuffle = false;
  AppException? _lastError;
  Timer? _saveTimer;

  final SleepTimer sleepTimer = SleepTimer(() {
    final svc = PlayerService.instance;
    final p = svc?._player;
    p?.pause();
    // Fade done — restore full volume so the NEXT session isn't muted.
    svc?._restoreSleepVolume();
  });

  double _preFadeVolume = -1;

  /// v1.6.0 sleep fade-out: volume ramps down linearly during the final
  /// SleepTimer.fadeWindow seconds, then pause fires. Restoring happens on
  /// cancel and on fire, so manual cancel never leaves a muted player.
  void _onSleepTimerTick() {
    final fade = sleepTimer.fadeFactor;
    if (fade == null) {
      // Timer inactive or outside the fade window — reset if we were fading.
      if (_preFadeVolume >= 0 && !sleepTimer.isEndOfVideo) _restoreSleepVolume();
      return;
    }
    if (_preFadeVolume < 0) _preFadeVolume = volume;
    final target = _preFadeVolume * fade;
    if ((target - volume).abs() > 0.5) {
      setVolume(target);
    }
  }

  void _restoreSleepVolume() {
    if (_preFadeVolume < 0) return;
    final v = _preFadeVolume;
    _preFadeVolume = -1;
    if (_player != null) setVolume(v);
  }

  static PlayerService? instance;

  VideoController? get videoController => _videoController;
  MediaItem? get current => _current;
  bool get hasMedia => _current != null;
  bool get isPlaying => _player?.state.playing ?? false;
  bool get isBuffering => _player?.state.buffering ?? false;
  bool get isCompleted => _player?.state.completed ?? false;
  Duration get position => _player?.state.position ?? Duration.zero;
  Duration? get duration {
    final d = _player?.state.duration ?? Duration.zero;
    return d > Duration.zero ? d : null;
  }
  double get rate => _player?.state.rate ?? 1.0;
  double get volume => _player?.state.volume ?? 100.0;
  AppException? get lastError => _lastError;
  RepeatMode get repeat => _repeat;
  bool get shuffle => _shuffle;
  List<MediaItem> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;

  Tracks get tracks => _player?.state.tracks ?? const Tracks();
  AudioTrack get audioTrack => _player?.state.track.audio ?? AudioTrack.auto();
  SubtitleTrack get subtitleTrack =>
      _player?.state.track.subtitle ?? SubtitleTrack.auto();
  VideoTrack get videoTrack => _player?.state.track.video ?? VideoTrack.auto();

  Future<void> ensureAudioHandler() async {
    if (!_prefs.backgroundPlayback) return;
    _audioHandler ??= await initAudioService(this);
    _audioHandler!.attach();
  }

  void _attachStreams() {
    final p = _player;
    if (p == null) return;
    p.stream.playing.listen((_) => _notify());
    p.stream.buffering.listen((_) => _notify());
    p.stream.completed.listen(_onCompleted);
    p.stream.error.listen((e) {
      _lastError = _classifyPlayerError(e);
      AppLogger.instance.error('player', 'media error: $e');
      _notify();
    });
    p.stream.track.listen((_) => _notify());
    p.stream.rate.listen((_) => _notify());
    _posSub = p.stream.position.listen((_) {
      // A-B segment loop (v1.9.0): rewind to A when playback crosses B.
      // Checked BEFORE the notify to keep the loop tight.
      if (_ab.isActive) {
        final target = _ab.rewindTargetMs(p.state.position.inMilliseconds);
        if (target != null) {
          unawaited(p.seek(Duration(milliseconds: target)).catchError((Object e) {
            AppLogger.instance.warning('player', 'ab-loop seek failed: $e');
          }));
        }
      }
      // Rebuild only lightweight widgets that depend on position.
      notifyListeners();
    });
  }

  /// Maps raw mpv/FFmpeg error text to a typed [AppException]. Every branch
  /// keeps the original message in [AppException.detail] so the Diagnostics
  /// screen and logs show the REAL cause, never "Unknown Error".
  AppException _classifyPlayerError(String raw) {
    final l = raw.toLowerCase();
    AppException typed(AppErrorType t) => AppException(t, detail: raw);

    if (l.contains('404') || l.contains('not found') || l.contains('no such file')) {
      return typed(AppErrorType.notFound);
    }
    if (l.contains('403') || l.contains('401') || l.contains('forbidden') ||
        l.contains('unauthorized') || l.contains('access denied')) {
      return typed(AppErrorType.forbidden);
    }
    if (l.contains('timeout') || l.contains('timed out')) {
      return typed(AppErrorType.timeout);
    }
    // TLS/certificate failures, DNS resolution failures, redirects and
    // unreachable hosts are all network-layer problems.
    if (l.contains('ssl') || l.contains('tls') || l.contains('certificate')) {
      return typed(AppErrorType.network);
    }
    if (l.contains('name or service not known') || l.contains('resolve') ||
        l.contains('no address') || l.contains('dns')) {
      return typed(AppErrorType.network);
    }
    if (l.contains('redirect') || l.contains('connection') ||
        l.contains('unreachable') || l.contains('network')) {
      return typed(AppErrorType.network);
    }
    if (l.contains('invalid uri') || l.contains('protocol not supported') ||
        l.contains('unsupported protocol') || l.contains('malformed')) {
      return typed(AppErrorType.invalidInput);
    }
    if (l.contains('codec') || l.contains('format') || l.contains('demuxer') ||
        l.contains('unsupported') || l.contains('unknown protocol')) {
      return typed(AppErrorType.unsupported);
    }
    if (l.contains('corrupt') || l.contains('invalid data') || l.contains('seek failed')) {
      return typed(AppErrorType.corrupted);
    }
    return typed(AppErrorType.unknown);
  }

  void _notify() => notifyListeners();

  /// Opens [item]; optionally within a [queue] at [startIndex].
  ///
  /// [audioFileUrl] loads an external audio track together with the
  /// video stream (mpv `audio-file`) — used by YouTube resolution where
  /// high-quality video-only and audio-only URLs come separately. Pass
  /// null to clear any previous external track.
  Future<void> open(
    MediaItem item, {
    List<MediaItem>? queue,
    int startIndex = 0,
    String? audioFileUrl,
    String? autoSubtitlePath,
  }) async {
    _lastError = null;
    _current = item;
    _currentSubtitlePath = null; // fresh media → fresh subtitle state
    if (queue != null && queue.isNotEmpty) {
      _queue = List.of(queue);
      _queueIndex = startIndex.clamp(0, queue.length - 1);
      _reshuffle();
    } else if (_currentIsNotInQueue(item)) {
      _queue = [item];
      _queueIndex = 0;
      _reshuffle();
    }
    await ensureAudioHandler();
    _audioHandler?.setNowPlaying(id: item.id, title: item.title);

    // Engine may be missing (lazy or degraded) — attempt one recovery,
    // then surface a real error state instead of crashing.
    if (_player == null) {
      await ensureEngine();
      if (_player == null) {
        _lastError = AppException(
          AppErrorType.unsupported,
          detail: _engineError ?? 'Playback engine unavailable',
        );
        _notify();
        return;
      }
    }

    try {
      await _applyExternalAudio(audioFileUrl);
      await _engine.open(
        Media(
          // Streams use the per-session playback URL (SFTP proxy / ftp://
          // with credentials / WebDAV URL); everything else uses the uri.
          item.playbackUrl,
          httpHeaders: item.headers,
          start: await _initialStart(item),
        ),
        play: true,
      );
      await _engine.setRate(_prefs.defaultSpeed);
      final cap = DataSaver.effectiveHlsCap(
        _hlsBitrateCap,
        saverOn: _prefs.dataSaver,
      );
      if (cap != null) {
        await _applyHlsBitrate(cap);
      }
      // Audio enhancement defaults (v1.9.0) — applied per media load
      // because mpv resets the af chain on new files.
      await _applyAudioEnhance();
      // Subtitle delay (v1.10.0): mpv resets sub-delay per file too.
      await _applySubtitleDelay();
      // v1.13.0: picture calibration + rotation defaults — re-applied per
      // media load (mpv resets eq/rotate per file, same as af/sub-delay).
      await _applyVideoEq();
      await _applyVideoRotate();
      // Audio-only default (v1.10.0): re-applied per media for the same
      // reason — vid resets to auto on every new load.
      await _applyAudioOnly();
      // Restore persisted A-B markers per media (keyed to the item id).
      _loadAbLoopFor(item.id);
      // v1.12.0: auto-attached subtitle (YouTube captions / sibling file)
      // — loaded through the same normalization pipeline as manual loads.
      if (autoSubtitlePath != null) {
        await addExternalSubtitle(autoSubtitlePath, 'DRS');
        // v1.13.0: optionally auto-translate the attached captions in the
        // background (skipped silently when already in the target lang).
        if (_prefs.autoTranslateSubs) {
          unawaited(_backgroundAutoTranslate(item.id));
        }
      }
    } catch (e, s) {
      // Media()/open()/setRate() must never escape as an unhandled error:
      // classify and surface a real error state instead of crashing.
      _lastError = _classifyPlayerError(e.toString());
      AppLogger.instance.error('player', 'open failed: ${item.uri}', e, s);
      _notify();
      return;
    }
    _startSaveTimer();
    unawaited(_library.markPlayed(item.id).catchError((Object e) {
      AppLogger.instance.warning('player', 'markPlayed failed: $e');
      return null;
    }));
    unawaited(_refreshMeta(item));
    _notify();
  }

  bool _currentIsNotInQueue(MediaItem item) =>
      _queue.isEmpty || _queueIndex < 0 || _queue[_queueIndex].id != item.id;

  /// Sets (or clears) mpv's external audio file BEFORE the next load —
  /// the option is applied file-locally at load time, so it must always
  /// be explicit: null/empty clears any track set by a previous open.
  /// Never throws: a failure here must not block normal playback.
  Future<void> _applyExternalAudio(String? audioFileUrl) async {
    final platform = _player?.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('audio-file', audioFileUrl ?? '');
    } catch (e) {
      AppLogger.instance.warning('player', 'audio-file set failed: $e');
    }
  }

  Future<Duration?> _initialStart(MediaItem item) async {
    // Live IPTV channels always start at the live edge.
    if (item.liveHint) return null;
    if (!_prefs.historyEnabled) return null;
    final p = await _history.progressFor(item.id);
    final resume = (p == null || p.completed ||
            p.positionMs < AppConstants.minResumablePositionMs)
        ? null
        : p.positionMs;
    final total = p?.durationMs ?? 0;
    if (resume != null && total > 0 && resume >= total * 0.95) return null;

    // v1.12.0 intro-skip memory: when the folder's intro end is known and
    // the user has NOT already watched past it, jump straight past it.
    // A saved resume position always wins when it lies beyond the intro.
    if (resume == null) {
      final introEnd = _prefs.introEndFor(IntroSkip.folderKeyOf(item.uri));
      final skip = IntroSkip.startMs(
        introEndMs: introEnd,
        resumePositionMs: resume,
      );
      if (skip != null) {
        _pendingResume = null;
        return Duration(milliseconds: skip);
      }
    }
    if (resume == null) return null;
    _pendingResume = Duration(milliseconds: resume);
    return _pendingResume;
  }

  Duration? _pendingResume;

  Future<void> _refreshMeta(MediaItem item) async {
    try {
      final duration = _player?.state.duration.inMilliseconds ?? 0;
      if (duration > 0 && (item.durationMs == null || item.durationMs! <= 0)) {
        item.durationMs = duration;
        await _library.updateMeta(item.id, durationMs: duration);
      }
    } catch (e) {
      AppLogger.instance.warning('player', 'meta refresh failed: $e');
    }
  }

  void _startSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(AppConstants.progressSaveInterval, (_) {
      if (isPlaying) unawaited(saveProgress());
    });
  }

  /// Persists the current watch position (Smart Resume data).
  Future<void> saveProgress({bool? completed}) async {
    final item = _current;
    final player = _player;
    if (item == null || player == null || !_prefs.historyEnabled) return;
    // Live streams have no meaningful watch position.
    if (item.liveHint) return;
    final pos = player.state.position.inMilliseconds;
    final dur = player.state.duration.inMilliseconds;
    if (dur > 0 && pos < AppConstants.minResumablePositionMs && completed != true) {
      return; // barely started — nothing to resume
    }
    final isDone = completed ?? (dur > 0 && pos >= dur * 0.95);
    await _history.upsertProgress(WatchProgress(
      itemId: item.id,
      positionMs: pos,
      durationMs: dur > 0 ? dur : item.durationMs,
      completed: isDone,
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> _onCompleted(bool completed) async {
    if (!completed) return;
    _saveTimer?.cancel();
    await saveProgress(completed: true);
    if (sleepTimer.consumeEndOfVideo()) {
      AppLogger.instance.info('player', 'sleep timer: end of video reached');
      return;
    }
    if (_prefs.autoPlayNext && await _hasNext(considerRepeat: true)) {
      await playNext();
    }
    _notify();
  }

  Future<bool> _hasNext({required bool considerRepeat}) async {
    if (_queue.isEmpty) return false;
    if (_repeat == RepeatMode.all) return true;
    return _queueIndex < _queue.length - 1;
  }

  Future<void> resume() async {
    if (_current == null || _player == null) return;
    await _engine.play();
    _startSaveTimer();
    _notify();
  }

  Future<void> pause() async {
    if (_player == null) return;
    await _engine.pause();
    await saveProgress();
    _saveTimer?.cancel();
    _notify();
  }

  Future<void> toggle() => isPlaying ? pause() : resume();

  Future<void> stop() async {
    await saveProgress();
    if (_player == null) {
      _current = null;
      _notify();
      return;
    }
    await _engine.stop();
    _saveTimer?.cancel();
    _current = null;
    _notify();
  }

  Future<void> seekTo(Duration d) async {
    if (_player == null) return;
    await _engine.seek(d);
    _notify();
  }

  Future<void> seekBy(int deltaMs) async {
    final target = position + Duration(milliseconds: deltaMs);
    final dur = duration;
    final clamped = dur != null && target > dur ? dur : (target < Duration.zero ? Duration.zero : target);
    await seekTo(clamped);
  }

  Future<void> frameStep(int direction) async {
    // v1.13.0: real frame stepping through mpv's frame-step commands when
    // the native engine is up (exact frame advance); the seek fallback
    // covers the degenerate/missing-engine cases.
    final platform = _player?.platform;
    if (platform is NativePlayer && direction != 0) {
      try {
        await platform.command([direction > 0 ? 'frame-step' : 'frame-back-step']);
        _notify();
        return;
      } catch (e) {
        AppLogger.instance.warning('player', 'frame-step failed: $e');
      }
    }
    await seekBy(direction * AppConstants.frameStepMs);
  }

  Future<void> setRate(double r) async {
    if (_player == null) return;
    await _engine.setRate(r.clamp(0.25, 4.0));
    _prefs.defaultSpeed = r;
    _notify();
  }

  Future<void> setVolume(double v) async {
    if (_player == null) return;
    await _engine.setVolume(v.clamp(0.0, 100.0));
    _notify();
  }

  void setRepeat(RepeatMode mode) {
    _repeat = mode;
    _notify();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _reshuffle();
    _notify();
  }

  void _reshuffle() {
    if (!_shuffle || _queue.isEmpty) {
      _shuffledOrder = List.generate(_queue.length, (i) => i);
      return;
    }
    final order = List.generate(_queue.length, (i) => i)..removeAt(_queueIndex);
    order.shuffle();
    order.insert(0, _queueIndex);
    _shuffledOrder = order;
  }

  int _nextQueueIndex({required bool forward}) {
    if (_queue.isEmpty) return -1;
    final order = _shuffle ? _shuffledOrder : List.generate(_queue.length, (i) => i);
    final pos = order.indexOf(_queueIndex);
    if (forward) {
      if (pos < order.length - 1) return order[pos + 1];
      if (_repeat == RepeatMode.all) return order.first;
    } else {
      if (pos > 0) return order[pos - 1];
      if (_repeat == RepeatMode.all) return order.last;
    }
    return -1;
  }

  Future<void> playNext() async {
    final next = _nextQueueIndex(forward: true);
    if (next < 0) return;
    _queueIndex = next;
    await open(_queue[next]);
  }

  Future<void> playPrevious() async {
    if (position > const Duration(seconds: 3)) {
      await seekTo(Duration.zero);
      return;
    }
    final prev = _nextQueueIndex(forward: false);
    if (prev < 0) return;
    _queueIndex = prev;
    await open(_queue[prev]);
  }

  // ---- track management ----

  Future<void> selectAudioTrack(AudioTrack track) async {
    if (_player == null) return;
    await _engine.setAudioTrack(track);
    _notify();
  }

  Future<void> selectSubtitleTrack(SubtitleTrack track) async {
    if (_player == null) return;
    await _engine.setSubtitleTrack(track);
    _notify();
  }

  Future<void> selectVideoTrack(VideoTrack track) async {
    if (_player == null) return;
    await _engine.setVideoTrack(track);
    _notify();
  }

  /// Loads an external SRT/VTT file into mpv (validated first).
  ///
  /// v1.10.0: the raw BYTES are read and run through the charset toolkit —
  /// legacy Windows-1256/ISO-8859-6 files are converted to UTF-8 in the
  /// cache dir and mpv is pointed at the normalized copy, so Arabic
  /// subtitles from old sites render correctly instead of mojibake.
  Future<bool> addExternalSubtitle(String path, String title) async {
    try {
      final isUrl = path.startsWith('http://') || path.startsWith('https://');
      String loadPath = path;
      if (!isUrl) {
        final bytes = await File(path).readAsBytes();
        final content = SubtitleCharset.decode(bytes);
        // Real validation: parse before anything touches the engine so
        // the user gets honest feedback on broken files.
        SubtitleParser.parse(content);
        final normalized = await _writeNormalizedSubtitle(content);
        if (normalized != null) loadPath = normalized;
      }
      if (_player == null) return false;
      await _engine.setSubtitleTrack(SubtitleTrack.uri(loadPath, title: title));
      _currentSubtitlePath = loadPath; // v1.13.0: translation source
      _notify();
      return true;
    } catch (e) {
      AppLogger.instance.warning('player', 'external subtitle failed: $e');
      return false;
    }
  }

  /// Loads external subtitle bytes with an explicit (or auto) encoding —
  /// the manual-encoding path of the subtitle toolkit sheet.
  Future<bool> loadSubtitleFromBytes(
    List<int> bytes,
    String title, {
    SubtitleEncoding? encoding,
  }) async {
    try {
      final content = SubtitleCharset.decode(bytes, encoding: encoding);
      SubtitleParser.parse(content); // throws FormatException on garbage
      final normalized = await _writeNormalizedSubtitle(content);
      if (_player == null) return normalized != null ? true : false;
      await _engine.setSubtitleTrack(
        SubtitleTrack.uri(normalized ?? '', title: title),
      );
      if (normalized != null) _currentSubtitlePath = normalized;
      _notify();
      return normalized != null;
    } catch (e) {
      AppLogger.instance.warning('player', 'subtitle bytes failed: $e');
      return false;
    }
  }

  /// Writes decoded subtitle text as a UTF-8 copy in the cache dir and
  /// returns its path (null when the write is impossible).
  Future<String?> _writeNormalizedSubtitle(String content) async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory(p.join(base.path, 'subtitles'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File(p.join(dir.path, 'ext_$stamp.srt'));
      await file.writeAsString(content, flush: true, encoding: utf8);
      return file.path;
    } catch (e) {
      AppLogger.instance.warning('player', 'subtitle normalize failed: $e');
      return null;
    }
  }

  // ---- A-B segment loop (v1.9.0) ----

  final AbRepeat _ab = AbRepeat();

  /// Read-only view of the current A-B markers (null = unset).
  ({int? aMs, int? bMs}) get abMarkers => (aMs: _ab.aMs, bMs: _ab.bMs);

  bool get abActive => _ab.isActive;

  /// Marks point A at the current position. Returns (aMs, bMs) after the
  /// update so the UI can show exact markers.
  ({int? aMs, int? bMs}) setLoopA() {
    _ab.setA(position.inMilliseconds);
    _persistAbLoop();
    _notify();
    return abMarkers;
  }

  /// Marks point B at the current position (A defaults to 0 when unset).
  /// Returns false when the segment would be too short.
  bool setLoopB() {
    final ok = _ab.setB(position.inMilliseconds);
    if (ok) _persistAbLoop();
    _notify();
    return ok;
  }

  /// Clears the A-B loop entirely.
  void clearAbLoop() {
    _ab.clear();
    _persistAbLoop();
    _notify();
  }

  /// Persists markers for the CURRENT media as `<itemId>|<aMs>|<bMs>`.
  /// Restored only when the same media is reopened — markers for one
  /// video never leak into another.
  void _persistAbLoop() {
    final item = _current;
    final a = _ab.aMs;
    final b = _ab.bMs;
    if (item == null || a == null || b == null) {
      _prefs.playerAbLoop = null;
      return;
    }
    _prefs.playerAbLoop = '${item.id}|$a|$b';
  }

  /// Restores the persisted loop ONLY for [itemId]; anything else clears
  /// the in-memory markers.
  void _loadAbLoopFor(String itemId) {
    var restored = false;
    final raw = _prefs.playerAbLoop;
    if (raw != null) {
      final parts = raw.split('|');
      if (parts.length == 3 && parts[0] == itemId) {
        final a = int.tryParse(parts[1]);
        final b = int.tryParse(parts[2]);
        if (a != null && b != null && b > a + AbRepeat.minSegmentMs) {
          _ab.aMs = a;
          _ab.bMs = b;
          restored = true;
        }
      }
    }
    if (!restored) _ab.clear();
  }

  // ---- audio enhancement (v1.9.0) ----

  AudioPreset _audioPreset = AudioPreset.flat;
  double _audioBoostDb = 0;

  AudioPreset get audioPreset => _audioPreset;
  double get audioBoostDb => _audioBoostDb;
  bool get audioEnhanceActive =>
      AudioEnhancer.isActive(_audioPreset, _audioBoostDb);

  /// Loads persisted defaults (called from _createEngine and settings).
  void loadAudioEnhanceDefaults() {
    _audioPreset = AudioPresetX.fromId(_prefs.audioPresetId);
    _audioBoostDb = _prefs.audioBoostDb;
    _notify();
  }

  /// Applies the current preset + boost to the engine. Never throws.
  Future<void> _applyAudioEnhance() async {
    final platform = _player?.platform;
    if (platform is! NativePlayer) return;
    final af = AudioEnhancer.buildAf(_audioPreset, _audioBoostDb);
    try {
      await platform.setProperty('af', af);
      if (af.isNotEmpty) {
        AppLogger.instance.info('player', 'af applied: $af');
      }
    } catch (e) {
      AppLogger.instance.warning('player', 'af set failed: $e');
    }
  }

  /// Sets a new audio preset and/or boost, persists them and applies the
  /// whole chain live.
  Future<void> setAudioEnhance({AudioPreset? preset, double? boostDb}) async {
    _audioPreset = preset ?? _audioPreset;
    _audioBoostDb =
        (boostDb ?? _audioBoostDb).clamp(0.0, AppConstants.maxAudioBoostDb).toDouble();
    _prefs.audioPresetId = _audioPreset.id;
    _prefs.audioBoostDb = _audioBoostDb;
    await _applyAudioEnhance();
    _notify();
  }

  // ---- subtitle toolkit (v1.10.0) ----

  /// Current subtitle sync delay in seconds (negative = subtitles early).
  double _subDelaySeconds = 0;

  double get subtitleDelay => _subDelaySeconds;

  /// Sets the subtitle sync delay, persists it per media and applies it
  /// live via mpv's `sub-delay`. Works even while the engine is cold:
  /// the value is stored and applied on the next open.
  Future<void> setSubtitleDelay(double seconds) async {
    _subDelaySeconds = seconds.clamp(-60.0, 60.0).toDouble();
    final item = _current;
    if (item != null) {
      unawaited(_prefs.setSubtitleDelayFor(item.id, _subDelaySeconds));
    }
    final platform = _player?.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('sub-delay', _subDelaySeconds.toStringAsFixed(2));
      } catch (e) {
        AppLogger.instance.warning('player', 'sub-delay failed: $e');
      }
    }
    _notify();
  }

  /// Applies the persisted per-media delay after a new file loads.
  Future<void> _applySubtitleDelay() async {
    final item = _current;
    if (item == null) return;
    final stored = _prefs.subtitleDelayFor(item.id) ?? 0.0;
    _subDelaySeconds = stored;
    final platform = _player?.platform;
    if ((platform is NativePlayer) && stored != 0) {
      try {
        await platform.setProperty('sub-delay', stored.toStringAsFixed(2));
      } catch (e) {
        AppLogger.instance.warning('player', 'sub-delay restore failed: $e');
      }
    }
  }

  /// Clears the persisted delay for the current media (reset button).
  Future<void> resetSubtitleDelay() async {
    await setSubtitleDelay(0);
    final item = _current;
    if (item != null) {
      await _prefs.clearSubtitleDelayFor(item.id);
    }
    _notify();
  }

  // ---- audio-only mode (v1.10.0) ----

  /// True while video decoding is disabled (battery/data saver).
  bool _audioOnly = false;

  bool get audioOnly => _audioOnly;

  /// Toggles audio-only playback. `VideoTrack.no()` tells mpv to skip
  /// the video track entirely — the decoder idles, saving battery and
  /// up to the full video bitrate on cellular data. The choice is
  /// remembered as the default for future sessions.
  Future<void> setAudioOnly(bool on) async {
    _audioOnly = on;
    _prefs.audioOnlyDefault = on;
    final player = _player;
    if (player != null) {
      try {
        await player.setVideoTrack(on ? VideoTrack.no() : VideoTrack.auto());
      } catch (e) {
        AppLogger.instance.warning('player', 'audio-only failed: $e');
      }
    }
    _notify();
  }

  /// Re-applies the audio-only default after a new file loads (mpv
  /// resets track selection per file).
  Future<void> _applyAudioOnly() async {
    _audioOnly = _prefs.audioOnlyDefault;
    final player = _player;
    if (player != null && _audioOnly) {
      try {
        await player.setVideoTrack(VideoTrack.no());
      } catch (e) {
        AppLogger.instance.warning('player', 'audio-only re-apply failed: $e');
      }
    }
  }

  // ---- HLS / stream quality (v1.2.x) ----

  int? _hlsBitrateCap;

  /// Currently selected HLS bitrate cap (kbps); null = auto.
  int? get hlsBitrateCap => _hlsBitrateCap;

  /// Video variant tracks exposed by the source (HLS/DASH renditions).
  List<VideoTrack> get videoQualityTracks => _player?.state.tracks.video
          .where((t) => t.id != 'auto' && t.id != 'no')
          .toList() ??
      const <VideoTrack>[];

  Future<void> _applyHlsBitrate(int capKbps) async {
    final platform = _player?.platform;
    if (platform == null) return;
    try {
      if (platform is NativePlayer) {
        await platform.setProperty('hls-bitrate', '$capKbps');
        AppLogger.instance.info('player', 'hls-bitrate capped at $capKbps');
      }
    } catch (e) {
      AppLogger.instance.warning('player', 'hls-bitrate failed: $e');
    }
  }

  /// Sets the HLS bitrate cap (kbps); null restores auto selection.
  Future<void> setHlsBitrate(int? capKbps) async {
    _hlsBitrateCap = capKbps;
    if (_player == null) {
      _notify();
      return;
    }
    try {
      final platform = _player!.platform;
      if (capKbps == null) {
        if (platform is NativePlayer) {
          await platform.setProperty('hls-bitrate', 'no');
        }
      } else {
        await _applyHlsBitrate(capKbps);
      }
    } catch (e) {
      AppLogger.instance.warning('player', 'setHlsBitrate failed: $e');
    }
    _notify();
  }

  // ---- v1.12.0: bookmarks + frame capture + session audio-only ----------

  /// Bookmarks of [itemId], ascending. Empty when none.
  List<VideoBookmark> bookmarksFor(String itemId) {
    final raw = _prefs.bookmarksRawFor(itemId);
    return raw == null ? const [] : BookmarkCodec.decode(raw);
  }

  /// Adds a bookmark at [positionMs] (idempotent at the same second).
  Future<List<VideoBookmark>> addBookmark(String itemId, int positionMs,
      {String? label}) async {
    final list = List.of(bookmarksFor(itemId));
    final ms = positionMs < 0 ? 0 : positionMs;
    if (!list.any((b) => (b.positionMs - ms).abs() < 1000)) {
      list.add(VideoBookmark(positionMs: ms, label: label));
      await _prefs.setBookmarksRawFor(itemId, BookmarkCodec.encode(list));
    }
    _notify();
    return bookmarksFor(itemId);
  }

  /// Removes the bookmark nearest within ±1500 ms of [positionMs].
  Future<List<VideoBookmark>> removeBookmark(String itemId, int positionMs) async {
    final list = List.of(bookmarksFor(itemId));
    VideoBookmark? victim;
    int bestDelta = 1 << 62;
    for (final b in list) {
      final d = (b.positionMs - positionMs).abs();
      if (d < bestDelta) {
        bestDelta = d;
        victim = b;
      }
    }
    if (victim != null && bestDelta <= 1500) {
      list.remove(victim);
      if (list.isEmpty) {
        await _prefs.setBookmarksRawFor(itemId, '');
      } else {
        await _prefs.setBookmarksRawFor(itemId, BookmarkCodec.encode(list));
      }
    }
    _notify();
    return bookmarksFor(itemId);
  }

  /// Marks "intro ends here" for the folder containing [uri]; the next
  /// fresh open in that folder starts past the intro. Returns the marker.
  Future<int> setFolderIntroEnd(String uri, int positionMs) async {
    final ms = positionMs.clamp(1000, 10 * 60 * 1000); // 1s..10min sane band
    await _prefs.setIntroEndFor(IntroSkip.folderKeyOf(uri), ms);
    return ms;
  }

  Future<void> clearFolderIntroEnd(String uri) =>
      _prefs.clearIntroEndFor(IntroSkip.folderKeyOf(uri));

  /// Session-scoped audio-only (battery saver): does NOT touch the
  /// persisted default — the next open re-applies the user's real choice.
  Future<void> applyAudioOnlySession(bool on) async {
    _audioOnly = on;
    final player = _player;
    if (player != null) {
      try {
        await player.setVideoTrack(on ? VideoTrack.no() : VideoTrack.auto());
      } catch (e) {
        AppLogger.instance.warning('player', 'session audio-only failed: $e');
      }
    }
    _notify();
  }

  bool get isAudioOnly => _audioOnly;

  /// Captures the current frame into the app's Pictures directory via
  /// mpv `screenshot-to-file`. Returns the file path, or null on failure.
  Future<String?> captureFrame() async {
    final player = _player;
    if (player == null) return null;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/Pictures');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/frame_$ts.jpg';
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.command(['screenshot-to-file', path]);
      } else {
        return null;
      }
      if (!File(path).existsSync()) return null;
      AppLogger.instance.info('player', 'frame captured: $path');
      return path;
    } catch (e, s) {
      AppLogger.instance.error('player', 'captureFrame failed', e, s);
      return null;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _posSub?.cancel();
    sleepTimer.removeListener(_onSleepTimerTick);
    sleepTimer.dispose();
    _player?.dispose();
    super.dispose();
  }

  // =========================================================================
  // v1.13.0: picture calibration + rotation + pinch zoom/pan + rate boost
  // + bookmark navigation + subtitle translation glue.
  // =========================================================================

  // ---- picture calibration (mpv eq properties, persisted) ---------------

  VideoEq _videoEq = const VideoEq();

  VideoEq get videoEq => _videoEq;

  /// Sets one or all eq channels, persists them and applies live. Works
  /// while the engine is cold: the value is stored and re-applied per open
  /// (mpv resets eq per file just like af/sub-delay).
  Future<void> setVideoEq({String? channel, double? value}) async {
    if (channel != null && value != null) {
      _videoEq = _videoEq.withChannel(channel, value);
    } else if (channel == null && value == null) {
      _videoEq = const VideoEq(); // full reset
    }
    await _prefs.setVideoEq(_videoEq.encode());
    await _applyVideoEq();
    _notify();
  }

  Future<void> _applyVideoEq() async {
    // Reload from prefs (setVideoEq persists immediately, so the stored
    // value always mirrors the live one).
    final raw = _prefs.videoEqRaw;
    _videoEq = raw == null ? const VideoEq() : VideoEq.decode(raw);
    final platform = _player?.platform;
    if (platform is! NativePlayer) return;
    final eq = _videoEq;
    final props = <String, double>{
      'brightness': eq.brightness,
      'contrast': eq.contrast,
      'saturation': eq.saturation,
      'gamma': eq.gamma,
      'hue': eq.hue,
    };
    for (final entry in props.entries) {
      if (entry.value == 0) continue;
      try {
        await platform.setProperty(entry.key, entry.value.toStringAsFixed(1));
      } catch (e) {
        AppLogger.instance.warning('player', '${entry.key} failed: $e');
      }
    }
  }

  Future<void> resetVideoEq() async {
    _videoEq = const VideoEq();
    await _prefs.setVideoEq(_videoEq.encode());
    final platform = _player?.platform;
    if (platform is NativePlayer) {
      for (final k in VideoEq.mpvProperty.keys) {
        try {
          await platform.setProperty(k, '0');
        } catch (_) {}
      }
    }
    _notify();
  }

  // ---- rotation (persisted) ---------------------------------------------

  int _videoRotate = 0;

  int get videoRotate => _videoRotate;

  /// Rotates the video by [deg] (0/90/180/270) via mpv `video-rotate` and
  /// persists the choice.
  Future<void> setVideoRotate(int deg) async {
    _videoRotate = RotationCycle.clamp(deg);
    await _prefs.setVideoRotate(_videoRotate);
    final platform = _player?.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('video-rotate', '$_videoRotate');
      } catch (e) {
        AppLogger.instance.warning('player', 'video-rotate failed: $e');
      }
    }
    _notify();
  }

  Future<void> _applyVideoRotate() async {
    _videoRotate = _prefs.videoRotate;
    final platform = _player?.platform;
    if ((platform is NativePlayer) && _videoRotate != 0) {
      try {
        await platform.setProperty('video-rotate', '$_videoRotate');
      } catch (e) {
        AppLogger.instance.warning('player', 'video-rotate restore failed: $e');
      }
    }
  }

  /// Cycles 0 → 90 → 180 → 270 → 0.
  Future<void> cycleVideoRotate() => setVideoRotate(RotationCycle.next(_videoRotate));

  // ---- pinch zoom / pan (session-scoped, gesture-driven) ----------------

  double _videoZoom = 0;
  double _videoPanX = 0;
  double _videoPanY = 0;

  ({double zoom, double panX, double panY}) get videoZoomPan =>
      (zoom: _videoZoom, panX: _videoPanX, panY: _videoPanY);

  /// Applies clamped zoom/pan from the pinch gesture (log-zoom units).
  /// Session-scoped on purpose: zoom never persists across sessions.
  Future<void> setVideoZoomPan({double? zoom, double? panX, double? panY}) async {
    final next = ZoomPanMath.clampAll(
      zoom: zoom ?? _videoZoom,
      panX: panX ?? _videoPanX,
      panY: panY ?? _videoPanY,
    );
    _videoZoom = next.zoom;
    _videoPanX = next.panX;
    _videoPanY = next.panY;
    final platform = _player?.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('video-zoom', next.zoom.toStringAsFixed(3));
        await platform.setProperty('video-pan-x', next.panX.toStringAsFixed(4));
        await platform.setProperty('video-pan-y', next.panY.toStringAsFixed(4));
      } catch (e) {
        AppLogger.instance.warning('player', 'zoom/pan failed: $e');
      }
    }
    _notify();
  }

  Future<void> resetVideoZoomPan() => setVideoZoomPan(zoom: 0, panX: 0, panY: 0);

  // ---- long-press 2x rate boost (YouTube-style) ---------------------------

  final LongPressBoost _boost = LongPressBoost();
  double? _preBoostRate;

  bool get rateBoostActive => _boost.isEngaged;

  /// Called when the user starts holding; polls the engage delay. Returns
  /// true exactly when the boost engages (UI badge + rate change).
  bool beginRateBoost() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_boost.isHolding) _boost.start(now);
    if (_boost.tick(now)) {
      _preBoostRate = rate;
      _applyBoostRate(longPressBoostRate);
      return true;
    }
    return false;
  }

  /// Releases the hold; restores the previous rate when the boost was
  /// actually engaged.
  Future<void> endRateBoost() async {
    if (_boost.end() && _preBoostRate != null) {
      await _applyBoostRate(_preBoostRate!);
    }
    _preBoostRate = null;
    _notify();
  }

  Future<void> _applyBoostRate(double r) async {
    final player = _player;
    if (player == null) return;
    try {
      await player.setRate(r.clamp(0.25, 4.0));
    } catch (e) {
      AppLogger.instance.warning('player', 'boost rate failed: $e');
    }
  }

  // ---- bookmark navigation ----------------------------------------------

  /// Jumps to the nearest next (or previous) bookmark of the current
  /// media. Returns the target position, null when none exists.
  Future<int?> jumpToBookmark({required bool next}) async {
    final item = _current;
    if (item == null) return null;
    final marks = bookmarksFor(item.id).map((b) => b.positionMs).toList();
    final posMs = position.inMilliseconds;
    final target = next
        ? BookmarkNav.next(marks, posMs)
        : BookmarkNav.previous(marks, posMs);
    if (target == null) return null;
    await seekTo(Duration(milliseconds: target));
    return target;
  }

  // ---- subtitle translation glue -----------------------------------------

  SubtitleTranslator? _translator;
  String? _currentSubtitlePath;

  /// File backing the current external subtitle track (null = none or an
  /// embedded track).
  String? get currentSubtitlePath => _currentSubtitlePath;

  /// Translates the current external subtitle into [targetLang] and swaps
  /// the player track to the translated file. Progress is reported 0..1.
  /// Returns a record describing the outcome for honest UI feedback.
  Future<TranslationOutcome> translateCurrentSubtitle({
    required String targetLang,
    void Function(double progress)? onProgress,
  }) async {
    final path = _currentSubtitlePath;
    if (path == null || path.isEmpty) {
      return const TranslationOutcome.none();
    }
    final translator = _translator ??= SubtitleTranslator();
    try {
      // Cached? Same text + target → instant swap, zero network.
      final bytes = await File(path).readAsBytes();
      final text = SubtitleCharset.decode(bytes);
      final cached = await translator.cachedTranslation(text, targetLang);
      if (cached != null) {
        await _swapSubtitle(cached, translated: true);
        return const TranslationOutcome(
            done: true, cached: true, partial: false);
      }
      final out = await translator.translateFile(
        path,
        targetLang: targetLang,
        onProgress: onProgress,
      );
      if (out == null) return const TranslationOutcome.none();
      if (out.alreadyTarget) {
        return const TranslationOutcome(
            done: false, cached: false, partial: false, alreadyTarget: true);
      }
      await _swapSubtitle(out.srtPath!, translated: true);
      return TranslationOutcome(
        done: true,
        cached: false,
        partial: out.partial,
      );
    } catch (e, s) {
      AppLogger.instance.error('player', 'translateCurrentSubtitle failed', e, s);
      return const TranslationOutcome(
          done: false, cached: false, partial: false, error: 'exception');
    }
  }

  Future<void> _swapSubtitle(String path, {required bool translated}) async {
    if (_player == null) return;
    await _engine.setSubtitleTrack(
      SubtitleTrack.uri(path, title: translated ? 'DRS · TR' : 'DRS'),
    );
    _currentSubtitlePath = path;
    _notify();
  }

  /// Silent background translation of the just-attached auto subtitle.
  /// Never surfaces errors: translation is a bonus layer, not a critical
  /// path. Abandons silently when the user moved to another media.
  Future<void> _backgroundAutoTranslate(String itemId) async {
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_current?.id != itemId) return;
      if (_currentSubtitlePath == null) return;
      await translateCurrentSubtitle(targetLang: _prefs.translateTargetLang);
    } catch (e) {
      AppLogger.instance.warning('player', 'auto-translate failed: $e');
    }
  }
}

/// The long-press speed boost rate.
const double longPressBoostRate = 2.0;

/// Honest outcome of [PlayerService.translateCurrentSubtitle].
class TranslationOutcome {
  const TranslationOutcome({
    required this.done,
    required this.cached,
    required this.partial,
    this.alreadyTarget = false,
    this.error,
  });

  const TranslationOutcome.none()
      : done = false,
        cached = false,
        partial = false,
        alreadyTarget = false,
        error = null;

  final bool done;
  final bool cached;
  final bool partial;
  final bool alreadyTarget;
  final String? error;
}
