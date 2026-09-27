import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/sharing/share_service.dart';
import '../../../services/smart/intel_v4.dart';
import '../../../state/media_studio_controller.dart';
import '../../../data/models/media_item.dart';
import '../../player/play_helpers.dart';

/// Shared file actions for the four studios: play, rename, share, delete,
/// info. All backed by real services (no fake menu entries).
class StudioActions {
  StudioActions._();

  static Future<void> share(BuildContext context, StudioFile f) =>
      context.read<ShareService>().shareFile(f.path);

  static Future<void> openWith(BuildContext context, StudioFile f) =>
      context.read<ShareService>().openWith(f.path);

  static Future<void> confirmDelete(BuildContext context, StudioFile f) async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.studioDeleteConfirm(f.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await context.read<MediaStudioController>().delete(f);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.dlAddStorage)));
        }
      }
    }
  }

  static Future<void> rename(BuildContext context, StudioFile f) async {
    final l = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: f.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.studioRename),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: l.dlAddName),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(l.save)),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty || !context.mounted) return;
    try {
      await context.read<MediaStudioController>().rename(f, newName.trim());
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.studioRenameFailed)));
      }
    }
  }

  static Future<void> showInfo(BuildContext context, StudioFile f) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(f.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall)),
            ]),
            const SizedBox(height: 12),
            _row(l.studioInfoSize, Formatters.bytes(f.sizeBytes)),
            _row(l.studioInfoDate, Formatters.dateTime(f.modified)),
            _row(l.studioInfoPath, f.path),
          ]),
        ),
      ),
    );
  }

  static Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 92,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ]),
      );

  /// Plays a video/audio file through the real player pipeline.
  static Future<void> play(BuildContext context, StudioFile f) async {
    final item = MediaItem(
      id: 'studio_${f.path.hashCode}',
      title: f.name,
      uri: f.path,
      type: MediaItemType.local,
      sizeBytes: f.sizeBytes,
    );
    await openPlayerFromLibrary(context, item, [item]);
  }
}
