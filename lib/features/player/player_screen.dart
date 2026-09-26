import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/storage/preferences_service.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/media_item.dart';
import '../../l10n/app_localizations.dart';
import '../../services/platform/native_channel.dart';
import '../../services/player/ab_loop.dart';
import '../../services/player/player_service.dart';
import '../../state/media_actions.dart';
import '../../widgets/common/error_view.dart';
import 'widgets/player_extras.dart';
import 'widgets/track_sheets.dart';

/// Full-screen professional player with gestures, lock, PiP, tracks,
/// speed, sleep timer, frame stepping and auto-hiding controls.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.item});

  final MediaItem item;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late PlayerService _player;
  bool _controlsVisible = true;
  bool _locked = false;
  Timer? _hideTimer;

  // gesture state
  int? _previewSeekMs;
  double? _indicatorValue; // 0..1 for brightness/volume overlay
  String? _indicatorLabel;
  bool _brightnessMode = false;

  // v1.1.0: two-finger pinch zoom/pan (raw pointer tracking, immune to
  // gesture-arena conflicts with the seek/brightness drags).
  final Map<int, Offset> _pointers = {};
  ViewGestureTracker? _pinchTracker;
  bool _pinching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = context.read<PlayerService>();
    _scheduleHide();
    _applyOrientation();
    _setupAutoPip();
  }

  Future<void> _applyOrientation() async {
    final prefs = context.read<PreferencesService>();
    if (prefs.preferFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _setupAutoPip() async {
    final prefs = context.read<PreferencesService>();
    if (prefs.enablePip) {
      await NativeChannel.instance.setAutoPip(prefs.autoPip);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player.saveProgress();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _player.saveProgress();
    super.dispose();
  }

  // ---- pinch zoom / pan (v1.1.0) ----

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) _beginPinch();
  }

  void _beginPinch() {
    final pts = _pointers.values.toList();
    if (pts.length < 2) return;
    final distance = (pts[0] - pts[1]).distance;
    final mid = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    _pinchTracker = ViewGestureTracker(
      initialZoom: _player.zoom,
      initialPan: _player.pan,
    )..begin(distance: distance, midpoint: mid);
    _pinching = true;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pinching) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length < 2 || _pinchTracker == null) return;
    final pts = _pointers.values.toList();
    final distance = (pts[0] - pts[1]).distance;
    final mid = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    final size = MediaQuery.of(context).size;
    final shortSide = size.shortestSide;
    final result = _pinchTracker!.update(
      distance: distance,
      midpoint: mid,
      viewportShortSide: shortSide,
      maxZoom: AppConstants.maxVideoZoom,
      maxPan: AppConstants.maxVideoPan,
    );
    _player.setView(zoom: result.zoom, pan: result.pan);
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _pinching = false;
      _pinchTracker = null;
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_controlsVisible || _locked) return;
    _hideTimer = Timer(AppConstants.controlsHideDelay, () {
      if (mounted && _controlsVisible) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _player.saveProgress();
        },
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final player = context.watch<PlayerService>();
    final l = AppLocalizations.of(context)!;

    // Playback engine unavailable on this device (degraded mode): show a
    // real error state with an engine retry action — never a dead screen.
    if (player.engineFailed || player.videoController == null) {
      return ErrorView(
        error: AppException(
          AppErrorType.unsupported,
          detail: player.engineError ?? 'Playback engine unavailable',
        ),
        onRetry: () async {
          await player.retryEngine();
          if (player.engineReady) _retry();
        },
      );
    }

    // Error state.
    final error = player.lastError;
    if (error != null && !player.hasMedia) {
      return ErrorView(error: error, onRetry: () => _retry());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _player.videoController!,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        ),
        if (player.isBuffering)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        if (error != null)
          ColoredBox(
            color: Colors.black87,
            child: ErrorView(error: error, onRetry: () => _retry()),
          ),
        if (!_locked) _buildGestureLayer(context),
        if (_locked) _buildLockOverlay(context),
        if (!_locked) ...[
          _buildTopBar(context, player, l),
          _buildBottomBar(context, player, l),
        ],
        if (player.isZoomed && !_locked) _buildZoomResetChip(context, player, l),
        if (player.audioOnly && !_locked) _buildAudioOnlyChip(context, l),
      ],
    );
  }

  Widget _buildZoomResetChip(BuildContext context, PlayerService player, AppLocalizations l) {
    return PositionedDirectional(
      top: 72,
      end: 12,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: ActionChip(
          backgroundColor: Colors.black54,
          avatar: const Icon(Icons.zoom_out_map, color: Colors.white, size: 18),
          label: Text(
            l.playerZoomReset,
            style: const TextStyle(color: Colors.white),
          ),
          onPressed: player.resetView,
        ),
      ),
    );
  }

  Widget _buildAudioOnlyChip(BuildContext context, AppLocalizations l) {
    return PositionedDirectional(
      top: 72,
      start: 12,
      child: Chip(
        backgroundColor: Colors.black54,
        avatar: Icon(
          Icons.headphones,
          color: Theme.of(context).colorScheme.primary,
          size: 18,
        ),
        label: Text(
          l.playerAudioOnlyOn,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    final actions = context.read<MediaActions>();
    await actions.playItem(widget.item);
  }

  // ---- gesture layer ----

  Widget _buildGestureLayer(BuildContext context) {
    // Raw pointer tracking sits OUTSIDE the GestureDetector so two-finger
    // pinch never fights the single-finger seek/brightness recognizers:
    // the Listener sees every event, zoom kicks in only with 2 pointers,
    // and all 1-finger gestures keep their existing arena winners.
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (d) => _onDoubleTap(context, d.localPosition),
        onHorizontalDragStart: _onSeekDragStart,
        onHorizontalDragUpdate: _onSeekDragUpdate,
        onHorizontalDragEnd: _onSeekDragEnd,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: (_) => _clearIndicator(),
        child: Stack(
          children: [
            if (_previewSeekMs != null) _buildSeekPreview(context),
            if (_indicatorValue != null) _buildIndicator(context),
          ],
        ),
      ),
    );
  }

  void _onDoubleTap(BuildContext context, Offset pos) {
    final width = MediaQuery.of(context).size.width;
    final step = AppConstants.seekStepMs;
    if (pos.dx < width / 3) {
      _player.seekBy(-step);
      _flashIndicator(label: '-${step ~/ 1000}s', value: null);
    } else if (pos.dx > width * 2 / 3) {
      _player.seekBy(step);
      _flashIndicator(label: '+${step ~/ 1000}s', value: null);
    } else {
      _player.toggle();
    }
  }

  void _flashIndicator({required String label, double? value}) {
    setState(() {
      _indicatorLabel = label;
      _indicatorValue = value;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _clearIndicator();
    });
  }

  void _clearIndicator() {
    if (!mounted) return;
    setState(() {
      _indicatorValue = null;
      _indicatorLabel = null;
      _previewSeekMs = null;
      _brightnessMode = false;
    });
  }

  int? _dragStartMs;

  void _onSeekDragStart(DragStartDetails d) {
    _dragStartMs = _player.position.inMilliseconds;
  }

  void _onSeekDragUpdate(DragUpdateDetails d) {
    final durationMs = _player.duration?.inMilliseconds ?? 0;
    if (durationMs <= 0) return;
    final width = MediaQuery.of(context).size.width;
    final deltaMs = (d.delta.dx / width * durationMs * 1.5).round();
    final from = _dragStartMs ?? _player.position.inMilliseconds;
    final target = (from + deltaMs).clamp(0, durationMs);
    setState(() => _previewSeekMs = target);
  }

  Future<void> _onSeekDragEnd(DragEndDetails d) async {
    final target = _previewSeekMs;
    _clearIndicator();
    if (target != null) {
      await _player.seekTo(Duration(milliseconds: target));
    }
  }

  double? _verticalStart;

  void _onVerticalDragStart(DragStartDetails d) {
    _verticalStart = d.localPosition.dy;
    _brightnessMode =
        d.localPosition.dx < MediaQuery.of(context).size.width / 2;
    _indicatorValue = _brightnessMode
        ? 0.5
        : _player.volume / 100;
    _indicatorLabel = _brightnessMode
        ? AppLocalizations.of(context)!.playerBrightness
        : AppLocalizations.of(context)!.playerVolume;
  }

  Future<void> _onVerticalDragUpdate(DragUpdateDetails d) async {
    if (_verticalStart == null || _indicatorValue == null) return;
    final delta = -d.delta.dy / 300;
    final next = (_indicatorValue! + delta).clamp(0.0, 1.0);
    setState(() {
      _indicatorValue = next;
      _indicatorLabel = _brightnessMode
          ? AppLocalizations.of(context)!.playerBrightness
          : AppLocalizations.of(context)!.playerVolume;
    });
    if (_brightnessMode) {
      await NativeChannel.instance.setBrightness(next);
    } else {
      await _player.setVolume(next * 100);
    }
  }

  Widget _buildSeekPreview(BuildContext context) {
    final durationMs = _player.duration?.inMilliseconds ?? 1;
    final ratio = (_previewSeekMs! / durationMs).clamp(0.0, 1.0);
    return Align(
      alignment: Alignment(ratio * 2 - 1, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${Formatters.duration(_previewSeekMs!)} / ${Formatters.duration(durationMs)}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildIndicator(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_indicatorLabel ?? '',
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                value: _indicatorValue,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- controls ----

  Widget _buildLockOverlay(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: IconButton.filledTonal(
            tooltip: l.playerUnlock,
            onPressed: () => setState(() => _locked = false),
            icon: const Icon(Icons.lock_open),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, PlayerService player, AppLocalizations l) {
    final theme = Theme.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black54, Colors.transparent],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                BackButton(onPressed: () => Navigator.of(context).maybePop()),
                Expanded(
                  child: Text(
                    widget.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                  ),
                ),
                if (context.read<PreferencesService>().enablePip)
                  IconButton(
                    tooltip: l.playerPiP,
                    onPressed: () => _enterPip(player),
                    icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
                  ),
                IconButton(
                  tooltip: l.playerScreenshot,
                  onPressed: () => _takeScreenshot(context),
                  icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
                ),
                IconButton(
                  tooltip: l.playerAudioOnly,
                  onPressed: () => _player.setAudioOnly(!_player.audioOnly),
                  icon: Icon(
                    Icons.headphones,
                    color: _player.audioOnly
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: l.playerBookmarks,
                  onPressed: () => showBookmarksSheet(context),
                  icon: const Icon(Icons.bookmarks_outlined, color: Colors.white),
                ),
                IconButton(
                  tooltip: l.playerSleepTimer,
                  onPressed: () => showSleepSheet(context),
                  icon: Icon(
                    Icons.bedtime,
                    color: _player.sleepTimer.isActive ? Colors.amber : Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: l.playerLock,
                  onPressed: () => setState(() => _locked = true),
                  icon: const Icon(Icons.lock_outline, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _enterPip(PlayerService player) async {
    final w = widget.item.width ?? 16;
    final h = widget.item.height ?? 9;
    await NativeChannel.instance.enterPip(width: w, height: h == 0 ? 9 : h);
  }

  Future<void> _takeScreenshot(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await _player.captureScreenshot();
    if (!messenger.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(saved != null ? l.screenshotSaved : l.screenshotFailed),
    ));
  }

  Widget _buildBottomBar(BuildContext context, PlayerService player, AppLocalizations l) {
    final posMs = player.position.inMilliseconds;
    final durMs = player.duration?.inMilliseconds ?? 0;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black54, Colors.transparent],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Center controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: l.playerPrevVideo,
                      color: Colors.white,
                      onPressed: player.playPrevious,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: l.previous,
                      color: Colors.white,
                      onPressed: () => _player.seekBy(-AppConstants.seekStepMs),
                      icon: const Icon(Icons.replay_10),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      iconSize: 40,
                      tooltip: player.isPlaying ? l.pause : l.play,
                      color: Colors.black,
                      onPressed: player.toggle,
                      icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: l.next,
                      color: Colors.white,
                      onPressed: () => _player.seekBy(AppConstants.seekStepMs),
                      icon: const Icon(Icons.forward_10),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: l.playerNextVideo,
                      color: Colors.white,
                      onPressed: player.playNext,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
                // Skip intro / outro — only when source provides data.
                if (widget.item.introEndMs != null && posMs < widget.item.introEndMs!)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FilledButton.tonal(
                      onPressed: () => _player
                          .seekTo(Duration(milliseconds: widget.item.introEndMs!)),
                      child: Text(l.playerSkipIntro),
                    ),
                  ),
                if (widget.item.outroStartMs != null &&
                    durMs > 0 &&
                    posMs > widget.item.outroStartMs!)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FilledButton.tonal(
                      onPressed: () => _player.playNext(),
                      child: Text(l.playerSkipOutro),
                    ),
                  ),
                // Progress
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(Formatters.duration(posMs),
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: durMs > 0
                              ? posMs.clamp(0, durMs).toDouble()
                              : 0,
                          max: durMs > 0 ? durMs.toDouble() : 1,
                          onChanged: durMs > 0
                              ? (v) => _player.seekTo(Duration(milliseconds: v.toInt()))
                              : null,
                        ),
                      ),
                      Text(Formatters.duration(durMs),
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
                // Bottom actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => showSpeedSheet(context),
                        icon: const Icon(Icons.speed, color: Colors.white, size: 18),
                        label: Text(
                          '${player.rate}x',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => showTracksSheet(context),
                        icon: const Icon(Icons.subtitles_outlined,
                            color: Colors.white, size: 18),
                        label: Text(
                          l.playerSubtitleTrack,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => showQualitySheet(context),
                        icon: const Icon(Icons.high_quality_outlined,
                            color: Colors.white, size: 18),
                        label: Text(
                          l.playerQuality,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: switch (player.loop.state) {
                          AbLoopState.off => l.playerAbLoop,
                          AbLoopState.aMarked => l.playerLoopMarkB,
                          AbLoopState.active => l.playerLoopActive,
                        },
                        color: player.loop.state == AbLoopState.off
                            ? Colors.white
                            : Colors.amber,
                        onPressed: player.markLoopPoint,
                        icon: Icon(player.loop.state == AbLoopState.active
                            ? Icons.repeat_rounded
                            : Icons.repeat_one_outlined),
                      ),
                      IconButton(
                        tooltip: l.playerBookmarkAdd,
                        color: Colors.white,
                        onPressed: () async {
                          final added = await _player.addBookmarkHere();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(added != null
                                ? l.bookmarkAdded
                                : l.screenshotFailed),
                          ));
                        },
                        icon: const Icon(Icons.bookmark_add_outlined),
                      ),
                      IconButton(
                        tooltip: l.playerFullscreen,
                        color: Colors.white,
                        onPressed: _toggleOrientation,
                        icon: const Icon(Icons.fullscreen),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleOrientation() async {
    final orientation = MediaQuery.of(context).orientation;
    await SystemChrome.setPreferredOrientations([
      orientation == Orientation.portrait
          ? DeviceOrientation.landscapeLeft
          : DeviceOrientation.portraitUp,
    ]);
  }
}
