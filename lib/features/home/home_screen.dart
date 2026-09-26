import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/sharing/share_service.dart';
import '../../state/home_controller.dart';
import '../../state/library_controller.dart';
import '../library/library_screen.dart';
import '../activity/activity_screen.dart';
import '../../state/media_actions.dart';
import '../../widgets/cards/video_card.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/stat_tile.dart';
import '../local_media/local_files_screen.dart';
import '../player/play_helpers.dart';
import '../player/player_screen.dart';
import '../search/search_screen.dart';
import '../sources/sources_screen.dart';
import 'widgets/open_url_sheet.dart';

/// Home dashboard: search, continue watching, recent, favorites,
/// recommendations, downloads, playlists, sources and local files.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: GestureDetector(
          onTap: () => _openSearch(context),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(23),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Text(
                  l.homeSearchHint,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: l.activityTitle,
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActivityScreen())),
          ),
          IconButton(
            tooltip: l.homeOpenUrl,
            icon: const Icon(Icons.link),
            onPressed: () => showOpenUrlSheet(context),
          ),
          IconButton(
            tooltip: l.homeOpenFile,
            icon: const Icon(Icons.folder_open),
            onPressed: () => _openLocalFile(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _QuickActions(onOpenSources: () => _openSources(context))),
            _section(
              context: context,
              title: l.homeContinueWatching,
              state: controller.continueWatching,
              onSeeAll: () => _seeAll(context, LibraryTab.continueWatching),
            ),
            _section(
              context: context,
              title: l.homeRecommended,
              state: controller.recommended,
              onSeeAll: () => _seeAll(context, LibraryTab.all),
            ),
            _section(
              context: context,
              title: l.homeRecent,
              state: controller.recent,
              onSeeAll: () => _seeAll(context, LibraryTab.recent),
            ),
            _section(
              context: context,
              title: l.homeFavorites,
              state: controller.favorites,
              onSeeAll: () => _seeAll(context, LibraryTab.favorites),
            ),
            SliverToBoxAdapter(
              child: _TilesRow(
                playlistCount: controller.playlistCount,
                activeDownloads: controller.activeDownloads,
                localVideos: controller.localVideos,
                sourceCount: controller.sourceCount,
                onOpenSources: () => _openSources(context),
                onOpenLocal: () => _openLocalFiles(context),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _section({
    required BuildContext context,
    required String title,
    required HomeSectionState state,
    required VoidCallback onSeeAll,
  }) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Widget child;
    if (state.loading) {
      child = const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (state.error != null) {
      child = SizedBox(
        height: 150,
        child: ErrorView(error: state.error, compact: true, onRetry: () => context.read<HomeController>().load()),
      );
    } else if (state.items.isEmpty) {
      child = const SizedBox.shrink();
    } else {
      child = SizedBox(
        height: 172,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: state.items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final item = state.items[i];
            return VideoCard(
              item: item,
              onTap: () => openPlayerFromLibrary(context, item, state.items),
            );
          },
        ),
      );
    }

    if (state.items.isEmpty && !state.loading && state.error == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                TextButton(onPressed: onSeeAll, child: Text(l.homeSeeAll)),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SearchScreen(),
    ));
  }

  void _openSources(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SourcesScreen(),
    ));
  }

  void _openLocalFiles(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const LocalFilesScreen(),
    ));
  }

  void _seeAll(BuildContext context, LibraryTab tab) {
    context.read<LibraryController>().setTab(tab);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const LibraryScreen(),
    ));
  }

  Future<void> _openLocalFile(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final share = context.read<ShareService>();
    final path = await share.pickVideo();
    if (path == null || !context.mounted) return;
    final actions = context.read<MediaActions>();
    final item = await actions.openLocalFile(path);
    if (!context.mounted) return;
    if (item == null) {
      final err = actions.lastError;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err == null
            ? l.playerErrorUnknown
            : ErrorView.messageFor(context, err.type)),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlayerScreen(item: item),
    ));
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onOpenSources});

  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.link,
              label: l.homeOpenUrl,
              onTap: () => showOpenUrlSheet(context),
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionTile(
              icon: Icons.settings_input_antenna,
              label: l.homeSources,
              onTap: onOpenSources,
              color: theme.colorScheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TilesRow extends StatelessWidget {
  const _TilesRow({
    required this.playlistCount,
    required this.activeDownloads,
    required this.localVideos,
    required this.sourceCount,
    required this.onOpenSources,
    required this.onOpenLocal,
  });

  final int playlistCount;
  final int activeDownloads;
  final int localVideos;
  final int sourceCount;
  final VoidCallback onOpenSources;
  final VoidCallback onOpenLocal;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
              icon: Icons.playlist_play,
              label: l.homePlaylists,
              value: '$playlistCount',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              icon: Icons.downloading,
              label: l.navDownloads,
              value: '$activeDownloads',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              icon: Icons.smart_display_outlined,
              label: l.homeLocalFiles,
              value: '$localVideos',
              onTap: onOpenLocal,
            ),
          ),
        ],
      ),
    );
  }
}
