import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import '../../services/player/player_service.dart';
import '../../state/floating_player_controller.dart';
import 'mini_player.dart';

/// The in-app floating video window (v1.3.0) — YouTube/TikTok style.
///
/// Rendered inside the root shell above the tab content, below pushed
/// routes: dragging repositions it, tapping the video re-opens the full
/// player, the close button stops playback.
///
/// The live video texture comes from the app-level [PlayerService], so
/// the same playback instance simply re-attaches here after the player
/// screen is popped — there is exactly one mpv engine at any time.
class FloatingVideoWindow extends StatefulWidget {
  const FloatingVideoWindow({super.key});

  @override
  State<FloatingVideoWindow> createState() => _FloatingVideoWindowState();
}

class _FloatingVideoWindowState extends State<FloatingVideoWindow> {
  static const _barHeight = 44.0;

  void _ensureAnchor(FloatingPlayerController floating, Size screen) {
    if (floating.anchorInitialized) return;
    final size = _windowSize(screen.width);
    // Default: bottom-start corner, above the nav bar area.
    floating.setOffset(Offset(
      AppConstants.floatingWindowEdgeMargin + 4,
      screen.height - size.videoHeight - _barHeight - 148,
    ));
  }

  ({double width, double videoHeight}) _windowSize(double screenWidth) {
    final width = (screenWidth * AppConstants.floatingWindowWidthFraction)
        .clamp(
            AppConstants.floatingWindowMinWidth,
            AppConstants.floatingWindowMaxWidth)
        .toDouble();
    return (width: width, videoHeight: width * 9 / 16);
  }

  Offset _clamp(Offset o, Size screen, double width, double totalH) {
    final maxX = screen.width - width - AppConstants.floatingWindowEdgeMargin;
    final maxY = screen.height - totalH - AppConstants.floatingWindowEdgeMargin;
    return Offset(
      o.dx.clamp(AppConstants.floatingWindowEdgeMargin, maxX.clamp(
          AppConstants.floatingWindowEdgeMargin, double.infinity)),
      o.dy.clamp(AppConstants.floatingWindowEdgeMargin, maxY.clamp(
          AppConstants.floatingWindowEdgeMargin, double.infinity)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final floating = context.watch<FloatingPlayerController>();
    final player = context.watch<PlayerService>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final screen = MediaQuery.of(context).size;

    if (!floating.visible || !player.hasMedia) {
      return const SizedBox.shrink();
    }
    _ensureAnchor(floating, screen);

    final size = _windowSize(screen.width);
    final width = size.width;
    final totalH = size.videoHeight + _barHeight;
    final pos = _clamp(floating.offset, screen, width, totalH);
    final item = player.current!;
    final isLive = item.liveHint;

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(16),
        color: Colors.black,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: totalH,
          child: Column(
            children: [
              // Video area: drag to move, tap to expand.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => floating.dragTo(pos + d.delta),
                onPanEnd: (_) => floating.setOffset(pos),
                onTap: () => _expand(context, floating),
                child: SizedBox(
                  width: width,
                  height: size.videoHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (player.videoController != null)
                        Video(
                          controller: player.videoController!,
                          controls: NoVideoControls,
                          fit: BoxFit.contain,
                        )
                      else
                        const ColoredBox(
                            color: Colors.black12,
                            child: Icon(Icons.videocam_off,
                                color: Colors.white38)),
                      if (player.isBuffering)
                        const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                        ),
                      if (isLive)
                        PositionedDirectional(
                          top: 6,
                          start: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l.liveBadge,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: Colors.white, fontSize: 9),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Control bar.
              SizedBox(
                height: _barHeight,
                child: Container(
                  color: theme.colorScheme.surfaceContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: player.isPlaying ? l.pause : l.play,
                        onPressed: player.toggle,
                        icon: Icon(
                          player.isPlaying
                              ? Icons.pause_circle
                              : Icons.play_circle,
                          size: 26,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: l.stop,
                        onPressed: player.stop,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isLive)
                LinearProgressIndicator(
                  minHeight: 2,
                  value: player.duration != null
                      ? (player.position.inMilliseconds /
                              player.duration!.inMilliseconds)
                          .clamp(0.0, 1.0)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _expand(
      BuildContext context, FloatingPlayerController floating) async {
    floating.hide();
    openPlayerScreen(context);
  }
}
