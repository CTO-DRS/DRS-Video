import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/player/player_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../services/player/player_service.dart';
import '../cards/video_card.dart';

/// Persistent mini player above the navigation bar.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final item = player.current;
    if (item == null) return const SizedBox.shrink();

    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: MediaThumb(item: item, radius: 10),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => openPlayerScreen(context),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        player.isBuffering
                            ? l.playerBuffering
                            : l.appName,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: player.isPlaying ? l.pause : l.play,
                onPressed: player.toggle,
                icon: Icon(player.isPlaying ? Icons.pause_circle : Icons.play_circle),
              ),
              IconButton(
                tooltip: l.stop,
                onPressed: player.stop,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Central navigation to the full player screen.
void openPlayerScreen(BuildContext context) {
  final player = context.read<PlayerService>();
  final item = player.current;
  if (item == null) return;
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PlayerScreen(item: item),
  ));
}
