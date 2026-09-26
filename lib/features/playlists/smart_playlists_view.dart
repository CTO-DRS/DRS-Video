import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/media_item.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/smart/smart_playlists.dart';
import '../../state/playlists_controller.dart';
import '../player/play_helpers.dart';

/// Loads the smart playlists once from the repositories. Kept separate from
/// the generator so tests can call the pure generator directly.
Future<List<SmartPlaylist>> loadSmartPlaylists({
  required LibraryRepository library,
  required HistoryRepository history,
}) async {
  final pool = await library.query(const LibraryQuery(limit: 5000));
  final progress = await history.progressMap();
  final progressByItem = <String, WatchProgress?>{
    for (final item in pool) item.id: progress[item.id],
  };
  return SmartPlaylistGenerator()
      .generate(library: pool, progressByItem: progressByItem);
}

IconData smartPlaylistIcon(SmartPlaylistKind kind) => switch (kind) {
      SmartPlaylistKind.continueWatching => Icons.play_circle_outline,
      SmartPlaylistKind.unwatched => Icons.auto_awesome_outlined,
      SmartPlaylistKind.mostPlayed => Icons.local_fire_department_outlined,
      SmartPlaylistKind.recentlyPlayed => Icons.history,
      SmartPlaylistKind.favorites => Icons.favorite_outline,
      SmartPlaylistKind.becauseYouWatched => Icons.recommend_outlined,
    };

String smartPlaylistTitle(AppLocalizations l, SmartPlaylist p) =>
    switch (p.kind) {
      SmartPlaylistKind.continueWatching => l.smartContinueWatching,
      SmartPlaylistKind.unwatched => l.smartUnwatched,
      SmartPlaylistKind.mostPlayed => l.smartMostPlayed,
      SmartPlaylistKind.recentlyPlayed => l.smartRecentlyPlayed,
      SmartPlaylistKind.favorites => l.smartFavorites,
      SmartPlaylistKind.becauseYouWatched =>
        l.smartBecauseYouWatched(p.anchorTitle ?? ''),
    };

/// Horizontal "القوائم الذكية" section shown above the user's playlists.
class SmartPlaylistsSection extends StatelessWidget {
  const SmartPlaylistsSection({
    super.key,
    required this.playlists,
    required this.onOpen,
  });

  final List<SmartPlaylist> playlists;

  /// Called with the tapped playlist.
  final void Function(SmartPlaylist) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (playlists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(l.smartPlaylistsTitle, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length,
            itemBuilder: (context, i) {
              final p = playlists[i];
              return _SmartCard(
                playlist: p,
                onTap: () => onOpen(p),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SmartCard extends StatelessWidget {
  const _SmartCard({required this.playlist, required this.onTap});

  final SmartPlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsetsDirectional.only(end: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(smartPlaylistIcon(playlist.kind),
                      size: 20, color: theme.colorScheme.primary),
                  const Spacer(),
                  Text('${playlist.items.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              const Spacer(),
              Text(
                smartPlaylistTitle(l, playlist),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail view of one generated playlist: plays like a normal queue and can
/// be frozen into a real (editable) playlist with one tap.
class SmartPlaylistDetailScreen extends StatelessWidget {
  const SmartPlaylistDetailScreen({super.key, required this.playlist});

  final SmartPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(smartPlaylistTitle(l, playlist), maxLines: 1,
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l.smartSaveAsPlaylist,
            icon: const Icon(Icons.playlist_add),
            onPressed: () => _saveAsRealPlaylist(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(smartPlaylistIcon(playlist.kind),
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(l.playlistsCount(playlist.items.length),
                    style: theme.textTheme.bodyMedium),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => openPlayerFromLibrary(context,
                      playlist.items.first, playlist.items),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l.smartPlayAll),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: playlist.items.length,
              itemBuilder: (context, i) {
                final item = playlist.items[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    child: Text('${i + 1}',
                        style: theme.textTheme.labelMedium),
                  ),
                  title: Text(item.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(switch (item.type) {
                    MediaItemType.local => l.typeLocal,
                    MediaItemType.network => l.typeNetwork,
                    MediaItemType.download => l.typeDownload,
                  }),
                  onTap: () => openPlayerFromLibrary(
                      context, item, playlist.items),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAsRealPlaylist(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final controller = context.read<PlaylistsController>();
    final scaffold = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final defaultName = smartPlaylistTitle(l, playlist);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) {
        final nameCtrl = TextEditingController(text: defaultName);
        return AlertDialog(
          title: Text(l.smartSaveAsPlaylist),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration:
                InputDecoration(hintText: l.playlistNameHint),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialog).pop(),
                child: Text(l.cancel)),
            FilledButton(
                onPressed: () => Navigator.of(dialog).pop(nameCtrl.text),
                child: Text(l.save)),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;

    await controller.load();
    final pl = await controller.create(name.trim());
    await controller.addVideos(
        pl.id, playlist.items.map((m) => m.id).toList());
    scaffold.showSnackBar(SnackBar(content: Text(l.smartPlaylistSaved)));
    navigator.pop();
  }
}
