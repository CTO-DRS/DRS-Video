import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/errors/app_exception.dart';
import '../../data/models/media_item.dart';
import '../../l10n/app_localizations.dart';
import '../../services/sharing/share_service.dart';
import '../../state/downloads_controller.dart';
import '../../state/library_controller.dart';
import '../../state/playlists_controller.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_view.dart';
import '../player/play_helpers.dart';

/// Context menu with every per-item action (play, favorite, playlist,
/// share, download, rename, info, delete).
Future<void> showMediaItemMenu(BuildContext context, MediaItem item) async {
  final l = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(l.play),
            onTap: () {
              Navigator.of(sheet).pop();
              openPlayerFromLibrary(context, item, [item]);
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(item.isFavorite ? l.actionUnfavorite : l.actionFavorite),
            onTap: () {
              Navigator.of(sheet).pop();
              context.read<LibraryController>().toggleFavorite(item.id);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: Text(l.actionAddToPlaylist),
            onTap: () {
              Navigator.of(sheet).pop();
              _addToPlaylist(context, item);
            },
          ),
          if (item.type == MediaItemType.network) ...[
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(l.actionDownload),
              onTap: () async {
                Navigator.of(sheet).pop();
                try {
                  await context.read<DownloadsController>().startForItem(item);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.downloadStarted)));
                } on AppException catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ErrorView.messageFor(context, e.type))));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(l.actionShareLink),
              onTap: () {
                Navigator.of(sheet).pop();
                context.read<ShareService>().shareLink(item.uri);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(l.actionCopyLink),
              onTap: () async {
                Navigator.of(sheet).pop();
                await context.read<ShareService>().copyLink(item.uri);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l.copied)));
              },
            ),
          ],
          if (item.type != MediaItemType.network) ...[
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(l.actionShareFile),
              onTap: () {
                Navigator.of(sheet).pop();
                context.read<ShareService>().shareFile(item.uri);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(l.actionOpenWith),
              onTap: () {
                Navigator.of(sheet).pop();
                context.read<ShareService>().openWith(item.uri);
              },
            ),
          ],
          if (item.type != MediaItemType.network) ...[
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(l.rename),
              onTap: () {
                Navigator.of(sheet).pop();
                _rename(context, item);
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l.actionFileInfo),
            onTap: () {
              Navigator.of(sheet).pop();
              _showInfo(context, item);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text(l.delete,
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: () {
              Navigator.of(sheet).pop();
              _confirmDelete(context, [item]);
            },
          ),
        ],
      ),
    ),
  );
}

void _addToPlaylist(BuildContext context, MediaItem item) async {
  final l = AppLocalizations.of(context)!;
  final controller = context.read<PlaylistsController>();
  if (controller.playlists.isEmpty) {
    await _createAndAdd(context, controller, [item.id]);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l.actionNewPlaylist),
            onTap: () {
              Navigator.of(sheet).pop();
              _createAndAdd(context, controller, [item.id]);
            },
          ),
          for (final pl in controller.playlists)
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: Text(pl.playlist.name),
              subtitle: Text(l.playlistsCount(pl.items.length)),
              onTap: () async {
                Navigator.of(sheet).pop();
                await controller.addVideos(pl.playlist.id, [item.id]);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.actionAddToPlaylist)));
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> _createAndAdd(BuildContext context,
    PlaylistsController controller, List<String> itemIds) async {
  final l = AppLocalizations.of(context)!;
  final nameController = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.actionNewPlaylist),
      content: TextField(
        controller: nameController,
        autofocus: true,
        decoration: InputDecoration(hintText: l.playlistNameHint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(l.cancel)),
        FilledButton(
            onPressed: () => Navigator.of(dialog).pop(nameController.text),
            child: Text(l.save)),
      ],
    ),
  );
  if (name == null || name.trim().isEmpty) return;
  final pl = await controller.create(name);
  await controller.addVideos(pl.id, itemIds);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(l.actionAddToPlaylist)));
}

Future<void> _rename(BuildContext context, MediaItem item) async {
  final l = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: item.title);
  final title = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.renameTitle),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(l.cancel)),
        FilledButton(
            onPressed: () => Navigator.of(dialog).pop(controller.text),
            child: Text(l.save)),
      ],
    ),
  );
  if (title == null || title.trim().isEmpty || title == item.title) return;
  await context.read<LibraryController>().rename(item.id, title.trim());
}

void _showInfo(BuildContext context, MediaItem item) {
  final l = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.fileInfoTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow(theme, l.fileInfoPath, item.uri),
          if (item.sizeBytes != null)
            _infoRow(theme, l.fileInfoSize, _bytes(item.sizeBytes!)),
          if (item.durationMs != null)
            _infoRow(theme, l.fileInfoDuration, _dur(item.durationMs!)),
          _infoRow(theme, l.fileInfoAdded, _date(item.addedAt)),
          if (item.lastPlayedAt != null)
            _infoRow(theme, l.fileInfoLastPlayed, _date(item.lastPlayedAt!)),
          _infoRow(theme, l.fileInfoTimesPlayed, '${item.playCount}'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(l.ok)),
      ],
    ),
  );
}

String _bytes(int b) => _fmtBytes(b);
String _dur(int ms) => _fmtDur(ms);
String _date(DateTime d) => d.toIso8601String().substring(0, 16).replaceAll('T', ' ');

// Tiny local formatters to avoid extra imports in this file.
String _fmtBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(v >= 100 || u == 0 ? 0 : 1)} ${units[u]}';
}

String _fmtDur(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final two = (int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

Widget _infoRow(ThemeData theme, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.bodySmall),
      ],
    ),
  );
}

Future<void> _confirmDelete(BuildContext context, List<MediaItem> items) async {
  final l = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.deleteConfirmTitle),
      content: Text(l.deleteItemsMessage(items.length)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(l.cancel)),
        FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l.delete)),
      ],
    ),
  );
  if (confirmed != true) return;
  await context.read<LibraryController>().deleteSelected();
}

/// Empty library view factory shared by tabs.
Widget libraryEmptyView(BuildContext context, LibraryTab tab) {
  final l = AppLocalizations.of(context)!;
  return switch (tab) {
    LibraryTab.favorites => EmptyState(
        icon: Icons.favorite_outline,
        title: l.emptyFavoritesTitle,
        body: l.emptyFavoritesBody),
    LibraryTab.downloads => EmptyState(
        icon: Icons.download_outlined,
        title: l.emptyDownloadsTitle,
        body: l.emptyDownloadsBody),
    LibraryTab.continueWatching => EmptyState(
        icon: Icons.timelapse,
        title: l.emptyContinueTitle,
        body: l.emptyContinueBody),
    LibraryTab.history => EmptyState(
        icon: Icons.history,
        title: l.emptyHistoryTitle,
        body: l.emptyHistoryBody),
    LibraryTab.local => EmptyState(
        icon: Icons.smart_display_outlined,
        title: l.emptyLocalFilesTitle,
        body: l.emptyLocalFilesBody),
    _ => EmptyState(
        icon: Icons.video_library_outlined,
        title: l.emptyLibraryTitle,
        body: l.emptyLibraryBody),
  };
}
