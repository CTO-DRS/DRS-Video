import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/media_item.dart';
import '../../l10n/app_localizations.dart';
import '../../state/local_media_controller.dart';
import '../../widgets/common/empty_state.dart';
import '../local_media/local_files_screen.dart';

/// One folder and its aggregate content info.
class MediaFolder {
  MediaFolder({required this.path, required this.videos});

  final String path;
  final List<MediaItem> videos;

  String get name => p.basename(path).isEmpty ? path : p.basename(path);

  int get totalBytes =>
      videos.fold(0, (sum, v) => sum + (v.sizeBytes ?? 0));
}

/// v1.1.0 folder view: groups on-device videos (MediaStore) by their
/// real parent directory, with counters and sizes — pure local data.
class FoldersView extends StatefulWidget {
  const FoldersView({super.key});

  @override
  State<FoldersView> createState() => _FoldersViewState();
}

class _FoldersViewState extends State<FoldersView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LocalMediaController>().load();
    });
  }

  /// Groups by parent path. Files without a usable path are bucketed
  /// under a synthetic root so nothing silently disappears.
  List<MediaFolder> _group(List<MediaItem> videos) {
    final map = <String, List<MediaItem>>{};
    for (final v in videos) {
      final uri = v.uri;
      final dir = uri.contains('/')
          ? uri.substring(0, uri.lastIndexOf('/'))
          : '/';
      map.putIfAbsent(dir, () => []).add(v);
    }
    final folders =
        map.entries.map((e) => MediaFolder(path: e.key, videos: e.value)).toList()
          ..sort((a, b) => b.videos.length.compareTo(a.videos.length));
    return folders;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocalMediaController>();
    final l = AppLocalizations.of(context)!;

    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.permissionNeeded) {
      return EmptyState(
        icon: Icons.folder_off_outlined,
        title: l.localFilesPermissionNeeded,
        actionLabel: l.localFilesGrant,
        onAction: controller.requestPermissionAndLoad,
      );
    }
    final folders = _group(controller.videos);
    if (folders.isEmpty) {
      return EmptyState(
        icon: Icons.folder_open_outlined,
        title: l.foldersEmptyTitle,
        body: l.foldersEmptyBody,
      );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: folders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final folder = folders[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                l.folderVideosCount(folder.videos.length) +
                    (folder.totalBytes > 0
                        ? ' · ${Formatters.bytes(folder.totalBytes)}'
                        : ''),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openFolder(context, folder),
            ),
          );
        },
      ),
    );
  }

  void _openFolder(BuildContext context, MediaFolder folder) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FolderDetailScreen(folder: folder),
      ),
    );
  }
}

class _FolderDetailScreen extends StatelessWidget {
  const _FolderDetailScreen({required this.folder});

  final MediaFolder folder;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(folder.name),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.78,
        ),
        itemCount: folder.videos.length,
        itemBuilder: (context, i) => VideoGridTile(item: folder.videos[i]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            l.folderVideosCount(folder.videos.length) +
                ' · ' +
                Formatters.bytes(folder.totalBytes),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
