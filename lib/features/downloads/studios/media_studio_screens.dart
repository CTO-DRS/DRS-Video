import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/smart/intel_v4.dart';
import '../../../state/media_studio_controller.dart';
import '../../../widgets/common/empty_state.dart';
import 'studio_actions.dart';

/// Video studio: every video file the app can see (downloads + public
/// folders), with real play/rename/share/delete/info actions.
class VideoStudioScreen extends StatelessWidget {
  const VideoStudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MediaStudioController>();
    final l = AppLocalizations.of(context)!;
    final files = ctrl.filesOf(MediaBucket.video);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.studioVideo),
        actions: [
          IconButton(
            tooltip: l.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.loading ? null : ctrl.load,
          ),
        ],
      ),
      body: _StudioBody(files: files, bucket: MediaBucket.video, grid: true),
    );
  }
}

/// Audio studio: list view + real playback through the app player.
class AudioStudioScreen extends StatelessWidget {
  const AudioStudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MediaStudioController>();
    final l = AppLocalizations.of(context)!;
    final files = ctrl.filesOf(MediaBucket.audio);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.studioAudio),
        actions: [
          IconButton(
            tooltip: l.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.loading ? null : ctrl.load,
          ),
        ],
      ),
      body: _StudioBody(files: files, bucket: MediaBucket.audio, grid: false),
    );
  }
}

class _StudioBody extends StatelessWidget {
  const _StudioBody({
    required this.files,
    required this.bucket,
    required this.grid,
  });

  final List<StudioFile> files;
  final MediaBucket bucket;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MediaStudioController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (ctrl.loading && files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.error != null && files.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(ctrl.error!, textAlign: TextAlign.center)));
    }
    if (files.isEmpty) {
      return EmptyState(
        icon: bucket == MediaBucket.video
            ? Icons.movie_filter_outlined
            : Icons.library_music_outlined,
        title: bucket == MediaBucket.video ? l.studioEmptyVideo : l.studioEmptyAudio,
        body: bucket == MediaBucket.video ? l.studioEmptyVideoBody : l.studioEmptyAudioBody,
      );
    }

    if (grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10,
            childAspectRatio: 1.6),
        itemCount: files.length,
        itemBuilder: (context, i) => _VideoCard(file: files[i]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: files.length,
      itemBuilder: (context, i) {
        final f = files[i];
        return ListTile(
          leading: Icon(Icons.audiotrack, color: theme.colorScheme.primary),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${Formatters.bytes(f.sizeBytes)} · ${Formatters.dateTime(f.modified)}',
              style: theme.textTheme.bodySmall),
          trailing: _StudioMenu(file: f),
          onTap: () => StudioActions.play(context, f),
        );
      },
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.file});

  final StudioFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => StudioActions.play(context, file),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Icon(Icons.play_circle_fill,
                  size: 40, color: theme.colorScheme.primary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(file.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(Formatters.bytes(file.sizeBytes),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ]),
              ),
              _StudioMenu(file: file, dense: true),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StudioMenu extends StatelessWidget {
  const _StudioMenu({required this.file, this.dense = false});

  final StudioFile file;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      onSelected: (a) => switch (a) {
        'play' => StudioActions.play(context, file),
        'rename' => StudioActions.rename(context, file),
        'share' => StudioActions.share(context, file),
        'open' => StudioActions.openWith(context, file),
        'info' => StudioActions.showInfo(context, file),
        'delete' => StudioActions.confirmDelete(context, file),
        _ => Future.value(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'play', child: Text(l.play)),
        PopupMenuItem(value: 'rename', child: Text(l.studioRename)),
        PopupMenuItem(value: 'share', child: Text(l.share)),
        PopupMenuItem(value: 'open', child: Text(l.actionOpenWith)),
        PopupMenuItem(value: 'info', child: Text(l.actionInfo)),
        PopupMenuItem(value: 'delete', child: Text(l.delete)),
      ],
    );
  }
}
