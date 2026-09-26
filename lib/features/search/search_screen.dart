import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/media_item.dart';
import '../../l10n/app_localizations.dart';
import '../../data/repositories/library_repository.dart';
import '../../state/search_controller.dart';
import '../../widgets/common/empty_state.dart';
import '../library/media_item_menu.dart';
import '../player/play_helpers.dart';

/// Library-wide search with suggestions, recent queries and filters.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final LibrarySearchController _controller;
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = context.read<LibrarySearchController>();
    _controller.init();
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LibrarySearchController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsetsDirectional.only(end: 12),
          child: TextField(
            controller: _field,
            focusNode: _focus,
            autofocus: true,
            onChanged: controller.onQueryChanged,
            onSubmitted: (_) => controller.submit(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l.searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _field.clear();
                        controller.onQueryChanged('');
                      },
                    ),
            ),
          ),
        ),
      ),
      body: !controller.submitted
          ? _buildSuggestions(controller, theme, l)
          : controller.searching
              ? const Center(child: CircularProgressIndicator())
              : controller.results.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off,
                      title: l.emptySearchTitle,
                      body: l.emptySearchBody,
                    )
                  : Column(
                      children: [
                        _filterRow(context, controller, l),
                        Expanded(
                          child: ListView.builder(
                            itemCount: controller.results.length,
                            itemBuilder: (context, i) {
                              final item = controller.results[i];
                              return ListTile(
                                leading: const Icon(Icons.movie_outlined),
                                title: Text(item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(switch (item.type) {
                                  MediaItemType.local => l.typeLocal,
                                  MediaItemType.network => l.typeNetwork,
                                  MediaItemType.download => l.typeDownload,
                                }),
                                onTap: () => openPlayerFromLibrary(
                                    context, item, controller.results),
                                onLongPress: () =>
                                    showMediaItemMenu(context, item),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _filterRow(
      BuildContext context, LibrarySearchController controller, AppLocalizations l) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          for (final t in [null, ...MediaItemType.values])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilterChip(
                selected: controller.typeFilter == t,
                label: Text(switch (t) {
                  null => l.typeAll,
                  MediaItemType.local => l.typeLocal,
                  MediaItemType.network => l.typeNetwork,
                  MediaItemType.download => l.typeDownload,
                }),
                onSelected: (_) => controller.setTypeFilter(t),
              ),
            ),
          for (final d in [
            DurationFilter.any,
            DurationFilter.short,
            DurationFilter.medium,
            DurationFilter.long,
            DurationFilter.veryLong,
          ])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilterChip(
                selected: controller.durationFilter == d,
                label: Text(switch (d) {
                  DurationFilter.any => l.typeAll,
                  DurationFilter.short => l.durationShort,
                  DurationFilter.medium => l.durationMedium,
                  DurationFilter.long => l.durationLong,
                  DurationFilter.veryLong => l.durationVeryLong,
                }),
                onSelected: (_) => controller.setDurationFilter(d),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(
      LibrarySearchController controller, ThemeData theme, AppLocalizations l) {
    return ListView(
      children: [
        if (controller.recentSearches.isNotEmpty) ...[
          ListTile(
            title: Text(l.searchRecentQueries, style: theme.textTheme.titleSmall),
            trailing: TextButton(
              onPressed: controller.clearRecent,
              child: Text(l.searchClearHistory),
            ),
          ),
          for (final q in controller.recentSearches)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(q),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => controller.removeRecent(q),
              ),
              onTap: () {
                _field.text = q;
                controller.submit(q);
              },
            ),
        ],
        if (controller.suggestions.isNotEmpty) ...[
          ListTile(
            title: Text(l.searchSuggestions, style: theme.textTheme.titleSmall),
          ),
          for (final s in controller.suggestions
              .where((s) => !controller.recentSearches.contains(s)))
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(s),
              onTap: () {
                _field.text = s;
                controller.submit(s);
              },
            ),
        ],
        if (controller.recentSearches.isEmpty && controller.suggestions.isEmpty)
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l.emptyHistoryBody),
          ),
      ],
    );
  }
}
