import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/library_controller.dart';
import '../../state/playlists_controller.dart';
import '../../widgets/common/error_view.dart';
import '../platforms/platforms_view.dart';
import '../player/play_helpers.dart';
import '../search/search_screen.dart';
import 'media_item_menu.dart';

/// Library with tabs, filters, sorting and multi-select bulk operations.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LibraryController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LibraryController>();
    final l = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 8,
      initialIndex: LibraryTab.values.indexOf(controller.tab),
      child: Scaffold(
        appBar: controller.selecting ? _selectionBar(context, controller, l) : _mainBar(context, controller, l),
        body: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              onTap: (i) => controller.setTab(LibraryTab.values[i]),
              tabs: [
                Tab(text: l.libraryAll),
                Tab(text: l.libraryFavorites),
                Tab(text: l.libraryDownloads),
                Tab(text: l.libraryRecent),
                Tab(text: l.libraryContinue),
                Tab(text: l.libraryLocal),
                Tab(text: l.libraryHistory),
                Tab(text: l.libraryPlatforms),
              ],
            ),
            Expanded(
              child: controller.loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _tabContent(context, controller, l, LibraryTab.all),
                        _tabContent(context, controller, l, LibraryTab.favorites),
                        _tabContent(context, controller, l, LibraryTab.downloads),
                        _tabContent(context, controller, l, LibraryTab.recent),
                        _tabContent(context, controller, l, LibraryTab.continueWatching),
                        _tabContent(context, controller, l, LibraryTab.local),
                        _tabContent(context, controller, l, LibraryTab.history),
                        const PlatformsView(),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: controller.tab == LibraryTab.platforms
            ? null
            : FloatingActionButton(
                tooltip: l.filter,
                onPressed: () => _showFilterSheet(context, controller),
                child: const Icon(Icons.tune),
              ),
      ),
    );
  }

  Widget _tabContent(BuildContext context, LibraryController controller,
      AppLocalizations l, LibraryTab tab) {
    if (controller.error != null) {
      return ErrorView(error: controller.error, onRetry: controller.load);
    }
    if (controller.items.isEmpty) {
      return libraryEmptyView(context, controller.tab);
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.builder(
        itemCount: controller.items.length,
        itemBuilder: (context, i) {
          final item = controller.items[i];
          final progress = controller.progressById[item.id];
          return _LibraryTile(
            item: item,
            progress:
                progress == null || progress.completed ? null : progress.ratio(),
            selected: controller.selected.contains(item.id),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _mainBar(BuildContext context,
      LibraryController controller, AppLocalizations l) {
    return AppBar(
      title: Text(l.navLibrary),
      actions: [
        IconButton(
          tooltip: l.addLinkTitle,
          icon: const Icon(Icons.add_link),
          onPressed: () => showAddLinkDialog(context),
        ),
        IconButton(
          tooltip: l.search,
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen())),
        ),
        IconButton(
          tooltip: l.sort,
          icon: const Icon(Icons.sort),
          onPressed: () => _showSortSheet(context, controller),
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar(BuildContext context,
      LibraryController controller, AppLocalizations l) {
    final theme = Theme.of(context);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: controller.clearSelection,
      ),
      title: Text(l.itemsSelected(controller.selected.length)),
      actions: [
        IconButton(
          tooltip: l.selectAll,
          icon: const Icon(Icons.select_all),
          onPressed: controller.selectAll,
        ),
        IconButton(
          tooltip: controller.items.every((m) => m.isFavorite)
              ? l.actionUnfavorite
              : l.actionFavorite,
          icon: const Icon(Icons.favorite),
          onPressed: controller.toggleFavoriteSelected,
        ),
        IconButton(
          tooltip: l.actionAddToPlaylist,
          icon: const Icon(Icons.playlist_add),
          onPressed: () => _addSelectionToPlaylist(context, controller),
        ),
        IconButton(
          tooltip: l.delete,
          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: Text(l.deleteConfirmTitle),
                content: Text(l.deleteItemsMessage(controller.selected.length)),
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
            if (confirmed == true) await controller.deleteSelected();
          },
        ),
      ],
    );
  }

  Future<void> _addSelectionToPlaylist(
      BuildContext context, LibraryController controller) async {
    final l = AppLocalizations.of(context)!;
    final playlists = context.read<PlaylistsController>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final pl in playlists.playlists)
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(pl.playlist.name),
                subtitle: Text(l.playlistsCount(pl.items.length)),
                onTap: () async {
                  Navigator.of(sheet).pop();
                  await playlists
                      .addVideos(pl.playlist.id, controller.selected.toList());
                  controller.clearSelection();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.actionAddToPlaylist)));
                },
              ),
            if (playlists.playlists.isEmpty)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l.emptyPlaylistsBody),
              ),
          ],
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context, LibraryController controller) {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sort),
              title: Text(l.librarySortBy),
              titleTextStyle: Theme.of(sheet).textTheme.titleMedium,
            ),
            for (final sort in SortBy.values)
              RadioListTile<SortBy>(
                value: sort,
                groupValue: controller.sort,
                title: Text(switch (sort) {
                  SortBy.name => l.sortName,
                  SortBy.dateAdded => l.sortDateAdded,
                  SortBy.recentlyPlayed => l.sortRecentlyPlayed,
                  SortBy.duration => l.sortDuration,
                  SortBy.size => l.sortSize,
                }),
                onChanged: (v) {
                  if (v != null) controller.setSort(v);
                  Navigator.of(sheet).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, LibraryController controller) {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(l.filter),
                titleTextStyle: Theme.of(sheet).textTheme.titleMedium,
              ),
              ListTile(title: Text(l.filterType)),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in [null, ...MediaItemType.values])
                    FilterChip(
                      selected: controller.typeFilter == t,
                      label: Text(switch (t) {
                        null => l.typeAll,
                        MediaItemType.local => l.typeLocal,
                        MediaItemType.network => l.typeNetwork,
                        MediaItemType.download => l.typeDownload,
                      }),
                      onSelected: (_) {
                        controller.setTypeFilter(t);
                        setSheetState(() {});
                      },
                    ),
                ],
              ),
              ListTile(title: Text(l.filterDuration)),
              Wrap(
                spacing: 8,
                children: [
                  for (final d in DurationFilter.values)
                    FilterChip(
                      selected: controller.durationFilter == d,
                      label: Text(switch (d) {
                        DurationFilter.any => l.typeAll,
                        DurationFilter.short => l.durationShort,
                        DurationFilter.medium => l.durationMedium,
                        DurationFilter.long => l.durationLong,
                        DurationFilter.veryLong => l.durationVeryLong,
                      }),
                      onSelected: (_) {
                        controller.setDurationFilter(d);
                        setSheetState(() {});
                      },
                    ),
                ],
              ),
              SwitchListTile(
                title: Text(l.filterFavoritesOnly),
                value: controller.tab == LibraryTab.favorites,
                onChanged: (v) {
                  controller.setTab(v ? LibraryTab.favorites : LibraryTab.all);
                  setSheetState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.item,
    required this.selected,
    this.progress,
  });

  final MediaItem item;
  final bool selected;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.read<LibraryController>();
    final isSelecting = context.select<LibraryController, bool>((c) => c.selecting);

    return ListTile(
      onTap: () {
        if (isSelecting) {
          controller.toggleSelect(item.id);
        } else {
          openPlayerFromLibrary(context, item, controller.items);
        }
      },
      onLongPress: () {
        if (isSelecting) {
          showMediaItemMenu(context, item);
        } else {
          controller.toggleSelect(item.id);
        }
      },
      leading: SizedBox(
        width: 72,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 72,
                height: 46,
                child: item.thumbPath != null && item.thumbPath!.isNotEmpty
                    ? Image.file(
                        File(item.thumbPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: Color(0x33808080)),
                      )
                    : const ColoredBox(color: Color(0x33808080)),
              ),
            ),
            if (selected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 20),
                ),
              ),
          ],
        ),
      ),
      title: Text(item.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: progress != null
          ? LinearProgressIndicator(value: progress, minHeight: 3)
          : null,
      trailing: isSelecting
          ? Checkbox(
              value: selected,
              onChanged: (_) => controller.toggleSelect(item.id),
            )
          : IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => showMediaItemMenu(context, item),
            ),
    );
  }
}
