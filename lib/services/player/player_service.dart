import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/storage/preferences_service.dart';
import '../../core/utils/logger.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../recommendations/playback_optimizer.dart';
import 'audio_handler.dart';
import 'sleep_timer.dart';

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
  }) async {
    _lastError = null;
    _current = item;
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
      final cap = _hlsBitrateCap;
      if (cap != null) {
        await _applyHlsBitrate(cap);
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
    if (p == null || p.completed || p.positionMs < AppConstants.minResumablePositionMs) {
      return null;
    }
    final total = p.durationMs ?? 0;
    if (total > 0 && p.positionMs >= total * 0.95) return null;
    _pendingResume = Duration(milliseconds: p.positionMs);
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
  Future<bool> addExternalSubtitle(String path, String title) async {
    try {
      final isUrl = path.startsWith('http://') || path.startsWith('https://');
      if (!isUrl) {
        final file = File(path);
        final content = await file.readAsString();
        // Validation only (mpv renders the real track).
        if (content.trim().isEmpty) return false;
      }
      if (_player == null) return false;
      await _engine.setSubtitleTrack(SubtitleTrack.uri(path, title: title));
      _notify();
      return true;
    } catch (e) {
      AppLogger.instance.warning('player', 'external subtitle failed: $e');
      return false;
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

  @override
  void dispose() {
    _saveTimer?.cancel();
    _posSub?.cancel();
    sleepTimer.removeListener(_onSleepTimerTick);
    sleepTimer.dispose();
    _player?.dispose();
    super.dispose();
  }
}
