import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/player/player_service.dart';

/// Bottom sheet listing the bookmarks of the current video (v1.1.0):
/// tap to seek, long-press to delete.
Future<void> showBookmarksSheet(BuildContext context) async {
  final player = context.read<PlayerService>();
  final bookmarks = await player.bookmarksForCurrent();
  if (!context.mounted) return;
  final l = AppLocalizations.of(context)!;
  final theme = Theme.of(context);

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l.playerBookmarks,
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (bookmarks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l.bookmarkEmpty,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: bookmarks.length,
                itemBuilder: (context, i) {
                  final b = bookmarks[i];
                  return ListTile(
                    leading: const Icon(Icons.bookmark_outlined),
                    title: Text(b.label ?? Formatters.duration(b.positionMs)),
                    subtitle:
                        b.label != null ? Text(Formatters.duration(b.positionMs)) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final repo = player;
                        await repo.deleteBookmark(b.id!);
                        Navigator.of(sheet).pop();
                        if (context.mounted) await showBookmarksSheet(context);
                      },
                    ),
                    onTap: () {
                      player.seekTo(Duration(milliseconds: b.positionMs));
                      Navigator.of(sheet).pop();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}
