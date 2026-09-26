import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/player/player_service.dart' as ps;
import '../../services/sharing/share_service.dart';
import '../../state/playlists_controller.dart';
import '../../widgets/common/empty_state.dart';
import '../player/play_helpers.dart';

/// Playlist detail: ordered videos, drag reorder, play/shuffle/repeat,
/// add/remove videos, rename, delete, export.
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlaylistsController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaylistsController>();
    final player = context.watch<ps.PlayerService>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final plOrNull = controller.playlists
        .where((p) => p.playlist.id == widget.playlistId)
        .firstOrNull;
    final pl = plOrNull;

    if (pl == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
            icon: Icons.playlist_remove,
            title: l.emptyPlaylistsTitle,
            body: l.emptyPlaylistsBody),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(pl.playlist.name),
        actions: [
          IconButton(
            tooltip: l.rename,
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: () => _rename(context, controller),
          ),
          IconButton(
            tooltip: l.actionExport,
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              final share = context.read<ShareService>();
              final json = share.exportPlaylistJson(pl);
              await share.shareLink(json);
            },
          ),
          IconButton(
            tooltip: l.delete,
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: Text(l.deleteConfirmTitle),
                  content: Text(l.sourcesDeleteWarn),
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
              if (confirmed == true && context.mounted) {
                await controller.delete(pl.playlist.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: pl.items.isEmpty
          ? EmptyState(
              icon: Icons.playlist_add,
              title: l.emptyPlaylistsTitle,
              body: l.playlistPickVideos,
              actionLabel: l.playlistPickVideos,
              onAction: () => _addVideos(context, controller),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              openPlayerFromLibrary(context, pl.items.first, pl.items),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l.playlistPlayAll),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: l.playlistShuffle,
                        onPressed: () async {
                          if (!player.shuffle) player.toggleShuffle();
                          if (!context.mounted) return;
                          await openPlayerFromLibrary(
                              context, pl.items.first, List<MediaItem>.of(pl.items));
                        },
                        icon: const Icon(Icons.shuffle),
                      ),
                      IconButton.filledTonal(
                        tooltip: l.playlistRepeat,
                        onPressed: () {
                          final next = switch (player.repeat) {
                            ps.RepeatMode.off => ps.RepeatMode.all,
                            ps.RepeatMode.all => ps.RepeatMode.one,
                            ps.RepeatMode.one => ps.RepeatMode.off,
                          };
                          player.setRepeat(next);
                        },
                        icon: Icon(
                          switch (player.repeat) {
                            ps.RepeatMode.off => Icons.repeat,
                            ps.RepeatMode.all => Icons.repeat,
                            ps.RepeatMode.one => Icons.repeat_one,
                          },
                          color: player.repeat == ps.RepeatMode.off
                              ? null
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.drag_indicator,
                          size: 16, color: theme.colorScheme.outline),
                      const SizedBox(width: 6),
                      Text(l.playlistReorderHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: true,
                    itemCount: pl.items.length,
                    onReorder: (oldIndex, newIndex) async {
                      final items = List<MediaItem>.of(pl.items);
                      if (newIndex > oldIndex) newIndex -= 1;
                      final moved = items.removeAt(oldIndex);
                      items.insert(newIndex, moved);
                      await controller.reorder(pl.playlist.id, items);
                    },
                    itemBuilder: (context, i) {
                      final item = pl.items[i];
                      return ListTile(
                        key: ValueKey(item.id),
                        leading: Icon(
                          Icons.movie_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(item.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${i + 1}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: l.actionRemoveFromPlaylist,
                          onPressed: () => controller
                              .removeVideo(pl.playlist.id, item.id),
                        ),
                        onTap: () =>
                            openPlayerFromLibrary(context, item, pl.items),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addVideos(context, controller),
        icon: const Icon(Icons.add),
        label: Text(l.add),
      ),
    );
  }

  Future<void> _rename(
      BuildContext context, PlaylistsController controller) async {
    final l = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l.renameTitle),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(hintText: l.playlistNameHint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(dialog).pop(nameController.text),
              child: Text(l.save)),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await controller.rename(widget.playlistId, name);
  }

  Future<void> _addVideos(
      BuildContext context, PlaylistsController controller) async {
    final l = AppLocalizations.of(context)!;
    final library = context.read<LibraryRepository>();
    final items = await library.query(const LibraryQuery(sort: SortBy.name));
    if (!context.mounted) return;
    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l.playlistPickVideos),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: items.isEmpty
                ? Center(child: Text(l.emptyLibraryBody))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final checked = selected.contains(item.id);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(item.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selected.add(item.id);
                          } else {
                            selected.remove(item.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: Text(l.cancel)),
            FilledButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: Text(l.add)),
          ],
        ),
      ),
    );
    if (confirmed == true && selected.isNotEmpty) {
      await controller.addVideos(widget.playlistId, selected.toList());
    }
  }
}

extension FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
