import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/smart/intel_v4.dart';
import 'edit_studio_screen.dart';
import 'images_studio_screen.dart';
import 'media_studio_screens.dart';

/// Studios hub: real entry cards for the four media studios. Each card shows
/// the live file count from the controller when available.
class StudiosHubScreen extends StatelessWidget {
  const StudiosHubScreen({super.key, this.counts = const {}});

  /// Live per-bucket counts (video/audio/image) from MediaStudioController.
  final Map<MediaBucket, List<StudioFile>> counts;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final videoCount = counts[MediaBucket.video]?.length ?? 0;
    final audioCount = counts[MediaBucket.audio]?.length ?? 0;
    final imageCount = counts[MediaBucket.image]?.length ?? 0;

    final items = [
      (
        icon: Icons.movie_creation_outlined,
        color: Colors.indigo,
        title: l.studioVideo,
        sub: l.studioVideoSub(videoCount),
        open: (BuildContext c) => Navigator.of(c).push(MaterialPageRoute(
            builder: (_) => const VideoStudioScreen())),
      ),
      (
        icon: Icons.audiotrack,
        color: Colors.teal,
        title: l.studioAudio,
        sub: l.studioAudioSub(audioCount),
        open: (BuildContext c) => Navigator.of(c).push(MaterialPageRoute(
            builder: (_) => const AudioStudioScreen())),
      ),
      (
        icon: Icons.photo_library_outlined,
        color: Colors.deepOrange,
        title: l.studioImages,
        sub: l.studioImagesSub(imageCount),
        open: (BuildContext c) => Navigator.of(c).push(MaterialPageRoute(
            builder: (_) => const ImagesStudioScreen())),
      ),
      (
        icon: Icons.tune,
        color: Colors.purple,
        title: l.studioEdit,
        sub: l.studioEditSub,
        open: (BuildContext c) => Navigator.of(c).push(
            MaterialPageRoute(builder: (_) => const EditStudioScreen())),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.studioTitle)),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: [
          for (final it in items)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => it.open(context),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(it.icon, color: it.color, size: 34),
                      const Spacer(),
                      Text(it.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(it.sub,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
