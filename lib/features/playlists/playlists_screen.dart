import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/sharing/share_service.dart';
import '../../services/smart/smart_playlists.dart';
import '../../state/media_actions.dart';
import '../../state/playlists_controller.dart';
import '../../widgets/common/empty_state.dart';
import 'playlist_detail_screen.dart';
import 'smart_playlists_view.dart';

/// Playlists overview grid with create/import actions.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<SmartPlaylist> _smart = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PlaylistsController>().load();
      _loadSmart();
    });
  }

  Future<void> _loadSmart() async {
    try {
      final library = context.read<LibraryRepository>();
      final history = context.read<HistoryRepository>();
      final smart = await loadSmartPlaylists(library: library, history: history);
      if (!mounted) return;
      setState(() => _smart = smart);
    } catch (_) {
      // Smart section is a bonus — the screen must never fail because of it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaylistsController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navPlaylists),
        actions: [
          IconButton(
            tooltip: l.actionImport,
            icon: const Icon(Icons.upload_file),
            onPressed: () => _importPlaylist(context, controller),
          ),
        ],
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : (controller.playlists.isEmpty && _smart.isEmpty)
              ? EmptyState(
                  icon: Icons.playlist_add,
                  title: l.emptyPlaylistsTitle,
                  body: l.emptyPlaylistsBody,
                  actionLabel: l.actionNewPlaylist,
                  onAction: () => _createPlaylist(context, controller),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await controller.load();
                    await _loadSmart();
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: SmartPlaylistsSection(
                          playlists: _smart,
                          onOpen: (p) => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  SmartPlaylistDetailScreen(playlist: p),
                            ),
                          ),
                        ),
                      ),
                      if (controller.playlists.isNotEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.25,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                final pl = controller.playlists[i];
                                return Card(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  PlaylistDetailScreen(
                                                      playlistId:
                                                          pl.playlist.id)));
                                      if (mounted) controller.load();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.playlist_play,
                                              size: 34,
                                              color:
                                                  theme.colorScheme.primary),
                                          const Spacer(),
                                          Text(
                                            pl.playlist.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            l.playlistsCount(pl.items.length),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: controller.playlists.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createPlaylist(context, controller),
        icon: const Icon(Icons.add),
        label: Text(l.actionNewPlaylist),
      ),
    );
  }

  Future<void> _createPlaylist(
      BuildContext context, PlaylistsController controller) async {
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
    await controller.create(name);
  }

  Future<void> _importPlaylist(
      BuildContext context, PlaylistsController controller) async {
    final l = AppLocalizations.of(context)!;
    final share = context.read<ShareService>();
    final actions = context.read<MediaActions>();
    try {
      final raw = await share.pickPlaylistJson();
      if (raw == null) return;
      final (name, items) = share.importPlaylistJson(raw);
      final pl = await controller.create(name);
      // Register imported URIs into the library (real items).
      for (final entry in items) {
        final item = await actions.registerExternal(
            entry.title, entry.uri, entry.type == 'local');
        if (item != null) {
          await controller.addVideos(pl.id, [item.id]);
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.playlistImported)));
    } on FormatException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.playlistInvalidFile)));
    }
  }
}
