import 'dart:async';
import 'dart:io';
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
import '../../services/player/player_service.dart';
import '../../services/security/secure_flag.dart';
import '../../services/smart/intel_v2.dart';
import '../../state/floating_player_controller.dart';
import '../../state/media_actions.dart';
import '../../widgets/common/error_view.dart';
import '../sites/platform_browser_screen.dart';
import 'widgets/ab_sheet.dart';
import 'widgets/audio_sheet.dart';
import 'widgets/track_sheets.dart';

/// True when [url] is an HTML *page* rather than direct media — playback
/// failures on page links get a "open in built-in browser" escape hatch.
bool _isPageLink(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  const mediaExt = {
    '.mp4', '.mkv', '.webm', '.mov', '.avi', '.ts', '.flv', '.m4v',
    '.m3u8', '.m3u', '.mpd', '.mp3', '.aac', '.m4a', '.flac', '.ogg',
  };
  final path = uri.path.toLowerCase();
  for (final ext in mediaExt) {
    if (path.endsWith(ext)) return false;
  }
  return true;
}

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = context.read<PlayerService>();
    _scheduleHide();
    _applyOrientation();
    _setupAutoPip();
    _setupSecureFlag();
  }

  /// Private vault (v1.10.0): while a vaulted item is on screen the
  /// window carries FLAG_SECURE — no screenshots, no recording, no
  /// recents thumbnail. Held via the ref-counted keeper so popping back
  /// to the vault grid keeps the protection alive.
  Future<void> _setupSecureFlag() async {
    if (!widget.item.isHidden) return;
    await SecureFlagKeeper.acquire(SecureFlagKeys.player(widget.item.id));
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
    unawaited(SecureFlagKeeper.release(
        SecureFlagKeys.player(widget.item.id)));
    _player.saveProgress();
    super.dispose();
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
        // Back NEVER kills playback: when the floating window feature is
        // on and something is playing, back minimizes to the floating
        // window (YouTube/TikTok behavior). Otherwise it pops normally.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            _player.saveProgress();
            return;
          }
          _handleBack();
        },
        child: _buildBody(context),
      ),
    );
  }

  Future<void> _handleBack() async {
    final prefs = context.read<PreferencesService>();
    final floating = context.read<FloatingPlayerController>();
    final navigator = Navigator.of(context);
    await _player.saveProgress();
    if (prefs.enableFloatingPlayer && _player.hasMedia && mounted) {
      floating.show();
    }
    if (mounted) navigator.pop();
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
      return ErrorView(
        error: error,
        onRetry: () => _retry(),
        onOpenInBrowser: _canOpenInBrowser() ? _openInBrowser : null,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _player.videoController!,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        ),
        // Audio-only mode (v1.10.0): video decoding is off; show a real
        // "now playing" face instead of a frozen/black frame.
        if (player.audioOnly) _buildAudioOnlyFace(context, player, l),
        if (player.isBuffering)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        if (error != null)
          ColoredBox(
            color: Colors.black87,
            child: ErrorView(
              error: error,
              onRetry: () => _retry(),
              onOpenInBrowser: _canOpenInBrowser() ? _openInBrowser : null,
            ),
          ),
        if (!_locked) _buildGestureLayer(context),
        if (_locked) _buildLockOverlay(context),
        if (!_locked) ...[
          _buildTopBar(context, player, l),
          _buildBottomBar(context, player, l),
        ],
      ],
    );
  }

  Future<void> _retry() async {
    final actions = context.read<MediaActions>();
    await actions.playItem(widget.item);
  }

  /// Audio-only "now playing" face (v1.10.0): replaces the frozen video
  /// surface while mpv skips the video track. Artwork + title + a restore
  /// button keep the state obvious — never a silent black screen.
  Widget _buildAudioOnlyFace(
      BuildContext context, PlayerService player, AppLocalizations l) {
    final theme = Theme.of(context);
    final item = widget.item;
    final thumb = item.thumbPath;
    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: thumb != null && File(thumb).existsSync()
                  ? Image.file(File(thumb), fit: BoxFit.cover)
                  : Icon(Icons.music_note,
                      size: 72, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                l.audioOnlyActive,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => player.setAudioOnly(false),
              icon: const Icon(Icons.videocam),
              label: Text(l.audioOnlyRestoreVideo),
            ),
          ],
        ),
      ),
    );
  }

  // ---- built-in browser fallback (v1.4.1) ----

  /// Offered only for page links (TikTok/YouTube/social HTML pages) that
  /// the extractor could not turn into direct media.
  bool _canOpenInBrowser() => _isPageLink(widget.item.uri);

  void _openInBrowser() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlatformBrowserScreen(
        initialUrl: widget.item.uri,
        title: widget.item.title,
      ),
    ));
  }

  // ---- gesture layer ----

  Widget _buildGestureLayer(BuildContext context) {
    return GestureDetector(
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
    );
  }

  void _onDoubleTap(BuildContext context, Offset pos) {
    final width = MediaQuery.of(context).size.width;
    // v1.12.0 adaptive step: long videos get bigger jumps.
    final step = AdaptiveSeek.stepMs(
        _player.duration?.inMilliseconds ?? 0);
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
                if (widget.item.liveHint)
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l.liveBadge,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
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
                    icon: const Icon(Icons.picture_in_picture, color: Colors.white),
                  ),
                if (context.read<PreferencesService>().enableFloatingPlayer)
                  IconButton(
                    tooltip: l.playerFloat,
                    onPressed: () => _minimizeToFloating(player),
                    icon: const Icon(Icons.picture_in_picture_alt,
                        color: Colors.white),
                  ),
                AnimatedBuilder(
                  animation: _player.sleepTimer,
                  builder: (context, _) {
                    final t = _player.sleepTimer;
                    if (!t.isActive) return const SizedBox.shrink();
                    final d = t.remaining!;
                    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
                    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bedtime,
                                size: 14, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text('$mm:$ss',
                                style: const TextStyle(
                                    color: Colors.amber, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // v1.12.0: video bookmarks (timestamp markers).
                IconButton(
                  tooltip: l.playerBookmarks,
                  onPressed: () => _showBookmarksSheet(context),
                  icon: AnimatedBuilder(
                    animation: _player,
                    builder: (context, _) => Icon(
                      Icons.bookmarks_outlined,
                      color: _player.bookmarksFor(widget.item.id).isNotEmpty
                          ? Colors.amber
                          : Colors.white,
                    ),
                  ),
                ),
                // v1.12.0: capture the current frame as a JPG.
                IconButton(
                  tooltip: l.playerCapture,
                  onPressed: () async {
                    final path = await _player.captureFrame();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(path == null
                          ? l.playerCaptureFail
                          : l.playerCaptureOk),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                  icon: const Icon(Icons.photo_camera_outlined,
                      color: Colors.white),
                ),
                IconButton(
                  tooltip: l.playerSleepTimer,
                  onPressed: () => showSleepSheet(context),
                  icon: Icon(
                    Icons.bedtime,
                    color: _player.sleepTimer.isActive ? Colors.amber : Colors.white,
                  ),
                ),
                // A-B loop status chip (v1.9.0) — visible while active.
                AnimatedBuilder(
                  animation: _player,
                  builder: (context, _) {
                    if (!_player.abActive) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.repeat,
                                size: 14, color: Colors.tealAccent),
                            SizedBox(width: 4),
                            Text('A-B',
                                style: TextStyle(
                                    color: Colors.tealAccent, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: l.playerAbRepeat,
                  onPressed: () => showAbRepeatSheet(context),
                  icon: AnimatedBuilder(
                    animation: _player,
                    builder: (context, _) => Icon(
                      Icons.repeat,
                      color: _player.abActive ? Colors.tealAccent : Colors.white,
                    ),
                  ),
                ),
                // v1.12.0: mark "intro ends here" for this folder — the
                // next episode in the same folder starts past the intro.
                IconButton(
                  tooltip: l.playerIntroEnd,
                  onPressed: () async {
                    final ms = await _player.setFolderIntroEnd(
                      widget.item.uri,
                      _player.position.inMilliseconds,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(l.playerIntroEndSet(ms ~/ 1000)),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                  icon: const Icon(Icons.skip_next_outlined,
                      color: Colors.white),
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

  /// v1.12.0: bookmark manager — jump to / delete / add-at-position.
  void _showBookmarksSheet(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final marks = _player.bookmarksFor(widget.item.id);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.playerBookmarks,
                      style: Theme.of(sheet).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (marks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l.playerBookmarkEmpty,
                          style: Theme.of(sheet).textTheme.bodySmall),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: marks.length,
                        itemBuilder: (_, i) {
                          final b = marks[i];
                          final secs = b.positionMs ~/ 1000;
                          final stamp =
                              '${(secs ~/ 3600).toString().padLeft(2, '0')}:'
                              '${((secs % 3600) ~/ 60).toString().padLeft(2, '0')}:'
                              '${(secs % 60).toString().padLeft(2, '0')}';
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.bookmark,
                                color: Colors.amber),
                            title: Text(stamp),
                            subtitle: b.label == null || b.label!.isEmpty
                                ? null
                                : Text(b.label!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            onTap: () {
                              Navigator.of(sheet).pop();
                              _player.seekTo(Duration(milliseconds: b.positionMs));
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () async {
                                await _player.removeBookmark(
                                    widget.item.id, b.positionMs);
                                setSheetState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await _player.addBookmark(
                          widget.item.id, _player.position.inMilliseconds);
                      setSheetState(() {});
                    },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(l.playerBookmarkAdd),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _enterPip(PlayerService player) async {
    final w = widget.item.width ?? 16;
    final h = widget.item.height ?? 9;
    await NativeChannel.instance.enterPip(width: w, height: h == 0 ? 9 : h);
  }

  /// Closes the full player and keeps the video running in the in-app
  /// floating window (same engine instance, no re-buffering).
  Future<void> _minimizeToFloating(PlayerService player) async {
    final floating = context.read<FloatingPlayerController>();
    final navigator = Navigator.of(context);
    await _player.saveProgress();
    floating.show();
    navigator.pop();
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
                // Bottom actions — labels auto-hide on narrow screens to
                // guarantee no overflow in portrait (adaptive density).
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: LayoutBuilder(builder: (context, box) {
                    final wide = box.maxWidth >= 520;
                    Widget action({
                      required IconData icon,
                      required String tooltip,
                      required VoidCallback onPressed,
                      Color? iconColor,
                      String? label,
                      bool animated = false,
                    }) {
                      final effectiveIcon = () {
                        if (animated) {
                          return AnimatedBuilder(
                            animation: _player,
                            builder: (context, _) => Icon(
                              icon,
                              color: iconColor ?? Colors.white,
                              size: 18,
                            ),
                          );
                        }
                        return Icon(icon, color: iconColor ?? Colors.white, size: 18);
                      }();
                      if (!wide || label == null) {
                        return IconButton(
                          tooltip: tooltip,
                          onPressed: onPressed,
                          icon: effectiveIcon,
                        );
                      }
                      return TextButton.icon(
                        onPressed: onPressed,
                        icon: effectiveIcon,
                        label: Text(label,
                            style: const TextStyle(color: Colors.white)),
                      );
                    }

                    return Row(
                      children: [
                        action(
                          icon: Icons.speed,
                          tooltip: l.playerSpeed,
                          label: '${player.rate}x',
                          onPressed: () => showSpeedSheet(context),
                        ),
                        action(
                          icon: Icons.subtitles_outlined,
                          tooltip: l.playerSubtitleTrack,
                          label: l.playerSubtitleTrack,
                          onPressed: () => showTracksSheet(context),
                        ),
                        action(
                          icon: Icons.equalizer,
                          tooltip: l.playerAudio,
                          label: l.playerAudio,
                          animated: true,
                          iconColor: _player.audioEnhanceActive
                              ? Colors.tealAccent
                              : Colors.white,
                          onPressed: () => showAudioSheet(context),
                        ),
                        action(
                          icon: Icons.high_quality_outlined,
                          tooltip: l.playerQuality,
                          label: l.playerQuality,
                          onPressed: () => showQualitySheet(context),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: l.playerFrameStepHint,
                          color: Colors.white,
                          onPressed: () => _player.frameStep(1),
                          icon: const Icon(Icons.skip_next, size: 18),
                        ),
                        IconButton(
                          tooltip: l.playerFullscreen,
                          color: Colors.white,
                          onPressed: _toggleOrientation,
                          icon: const Icon(Icons.fullscreen),
                        ),
                      ],
                    );
                  }),
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
