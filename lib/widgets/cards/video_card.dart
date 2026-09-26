import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/media_item.dart';
import '../../l10n/app_localizations.dart';

/// Thumbnail widget with a clean fallback (no fake placeholders).
class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, required this.item, this.width, this.height, this.radius = 14});

  final MediaItem item;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: theme.colorScheme.surfaceContainerHighest,
              child: item.thumbPath != null && item.thumbPath!.isNotEmpty
                  ? Image.file(
                      File(item.thumbPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _Fallback(),
                    )
                  : const _Fallback(),
            ),
            if (item.durationMs != null && item.durationMs! > 0)
              Positioned.directional(
                textDirection: Directionality.of(context),
                end: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    Formatters.duration(item.durationMs!),
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.movie_outlined,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// A video card used in horizontal rows and vertical lists.
class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.progress,
    this.width = 160,
    this.compact = false,
    this.trailing,
    this.selected = false,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double? progress; // 0..1
  final double width;
  final bool compact;
  final Widget? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  MediaThumb(item: item, width: double.infinity, height: compact ? 72 : 90, radius: 0),
                  if (selected)
                    Positioned.fill(
                      child: ColoredBox(
                        color: theme.colorScheme.primary.withValues(alpha: 0.35),
                        child: const Icon(Icons.check_circle, color: Colors.white),
                      ),
                    ),
                  if (trailing != null)
                    Positioned.directional(
                      textDirection: Directionality.of(context),
                      top: 4,
                      end: 4,
                      child: trailing!,
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(l),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (progress != null && progress! > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0.0, 1.0),
                      minHeight: 4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(AppLocalizations l) {
    final parts = <String>[];
    if (item.sizeBytes != null) parts.add(Formatters.bytes(item.sizeBytes!));
    parts.add(switch (item.type) {
      MediaItemType.local => l.typeLocal,
      MediaItemType.network => l.typeNetwork,
      MediaItemType.download => l.typeDownload,
    });
    return parts.join(' · ');
  }
}

/// Horizontal section with header + "see all".
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
