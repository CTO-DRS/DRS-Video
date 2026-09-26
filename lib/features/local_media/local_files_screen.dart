import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/media_item.dart';
import '../../l10n/app_localizations.dart';
import '../../services/files/file_manager_service.dart';
import '../../services/sharing/share_service.dart';
import '../../state/local_media_controller.dart';
import '../../widgets/common/empty_state.dart';
import '../player/play_helpers.dart';

/// On-device video browser (MediaStore) with thumbnails, sorting and
/// file operations (share / delete / info).
class LocalFilesScreen extends StatefulWidget {
  const LocalFilesScreen({super.key});

  @override
  State<LocalFilesScreen> createState() => _LocalFilesScreenState();
}

enum _SortMode { dateDesc, nameAsc, sizeDesc, durationDesc }

class _LocalFilesScreenState extends State<LocalFilesScreen> {
  _SortMode _sort = _SortMode.dateDesc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LocalMediaController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocalMediaController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.homeLocalFiles),
        actions: [
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort),
            onSelected: (m) => setState(() => _sort = m),
            itemBuilder: (_) => [
              PopupMenuItem(value: _SortMode.dateDesc, child: Text(l.sortDateAdded)),
              PopupMenuItem(value: _SortMode.nameAsc, child: Text(l.sortName)),
              PopupMenuItem(value: _SortMode.sizeDesc, child: Text(l.sortSize)),
              PopupMenuItem(value: _SortMode.durationDesc, child: Text(l.sortDuration)),
            ],
          ),
          IconButton(
            tooltip: l.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: controller.load,
          ),
        ],
      ),
      body: controller.loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(l.localFilesScanning, style: theme.textTheme.bodySmall),
                ],
              ),
            )
          : controller.permissionNeeded
              ? EmptyState(
                  icon: Icons.folder_off_outlined,
                  title: l.localFilesPermissionNeeded,
                  actionLabel: l.localFilesGrant,
                  onAction: controller.requestPermissionAndLoad,
                )
              : controller.videos.isEmpty
                  ? EmptyState(
                      icon: Icons.smart_display_outlined,
                      title: l.emptyLocalFilesTitle,
                      body: l.emptyLocalFilesBody,
                    )
                  : RefreshIndicator(
                      onRefresh: controller.load,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: controller.videos.length,
                        itemBuilder: (context, i) {
                          final videos = _sorted(controller.videos);
                          final item = videos[i];
                          return VideoGridTile(item: item);
                        },
                      ),
                    ),
    );
  }

  List<MediaItem> _sorted(List<MediaItem> videos) {
    final list = List.of(videos);
    switch (_sort) {
      case _SortMode.dateDesc:
        return list;
      case _SortMode.nameAsc:
        list.sort((a, b) => a.title.compareTo(b.title));
      case _SortMode.sizeDesc:
        list.sort((a, b) => (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0));
      case _SortMode.durationDesc:
        list.sort((a, b) => (b.durationMs ?? 0).compareTo(a.durationMs ?? 0));
    }
    return list;
  }
}

class VideoGridTile extends StatelessWidget {
  const VideoGridTile({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.read<LocalMediaController>();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final registered = await controller.registerForPlayback(item);
          if (!context.mounted || registered == null) return;
          await openPlayerFromLibrary(context, registered, [registered]);
        },
        onLongPress: () => _showFileMenu(context, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.thumbPath != null && item.thumbPath!.isNotEmpty)
                    Image.file(
                      File(item.thumbPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _Placeholder(),
                    )
                  else
                    const _Placeholder(),
                  if (item.durationMs != null && item.durationMs! > 0)
                    Positioned.directional(
                      textDirection: Directionality.of(context),
                      end: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          Formatters.duration(item.durationMs!),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (item.sizeBytes != null)
                    Text(
                      Formatters.bytes(item.sizeBytes!),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFileMenu(BuildContext context, MediaItem item) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(l.play),
              onTap: () async {
                Navigator.of(sheet).pop();
                final controller = context.read<LocalMediaController>();
                final registered = await controller.registerForPlayback(item);
                if (!context.mounted || registered == null) return;
                await openPlayerFromLibrary(context, registered, [registered]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(l.share),
              onTap: () {
                Navigator.of(sheet).pop();
                context.read<ShareService>().shareFile(item.uri);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l.actionFileInfo),
              onTap: () {
                Navigator.of(sheet).pop();
                showDialog<void>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: Text(l.fileInfoTitle),
                    content: Text(
                      '${l.fileInfoPath}: ${item.uri}\n'
                      '${item.sizeBytes != null ? '${l.fileInfoSize}: ${Formatters.bytes(item.sizeBytes!)}\n' : ''}'
                      '${item.durationMs != null ? '${l.fileInfoDuration}: ${Formatters.duration(item.durationMs!)}\n' : ''}',
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(dialog).pop(),
                          child: Text(l.ok)),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: Text(l.delete,
                  style: TextStyle(color: theme.colorScheme.error)),
              onTap: () async {
                Navigator.of(sheet).pop();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: Text(l.deleteConfirmTitle),
                    content: Text(l.deleteItemsMessage(1)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(dialog).pop(false),
                          child: Text(l.cancel)),
                      FilledButton(
                          onPressed: () => Navigator.of(dialog).pop(true),
                          child: Text(l.delete)),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                final fm = context.read<FileManagerService>();
                await fm.delete(item.uri);
                if (!context.mounted) return;
                await context.read<LocalMediaController>().load();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0x33808080),
        child: Center(child: Icon(Icons.movie_outlined)),
      );
}
