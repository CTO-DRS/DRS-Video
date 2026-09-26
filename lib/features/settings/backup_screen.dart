import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exception.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../services/backup/backup_service.dart';
import '../../widgets/common/error_view.dart';
import 'cloud_backup_screen.dart';

/// Backup & restore: one-tap export of the whole user dataset (library,
/// playlists, watch progress, searches and settings) into a shareable JSON
/// file, and a merge-import that never deletes anything.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupSummary? _summary;
  bool _working = false;
  String? _lastExportPath;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final svc = _service();
    final s = await svc.summarize();
    if (!mounted) return;
    setState(() => _summary = s);
  }

  BackupService _service() {
    final services = context.read<AppServices>();
    return BackupService(
      library: services.library,
      playlists: services.playlists,
      history: services.history,
      prefs: services.prefs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final s = _summary;

    return Scaffold(
      appBar: AppBar(title: Text(l.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- what is included -------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.inventory_2_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(l.backupIncludesTitle,
                        style: theme.textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 12),
                  if (s == null)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _row(theme, Icons.video_library_outlined,
                        l.backupItemsCount(s.items)),
                    _row(theme, Icons.playlist_play,
                        l.backupPlaylistsCount(s.playlists)),
                    _row(theme, Icons.history,
                        l.backupProgressCount(s.progressEntries)),
                    _row(theme, Icons.search,
                        l.backupSearchesCount(s.searches)),
                    _row(theme, Icons.settings_outlined, l.backupSettingsRow),
                  ],
                  const SizedBox(height: 8),
                  Text(l.backupNeverDeletes,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ---- export -------------------------------------------------
          FilledButton.icon(
            onPressed: _working ? null : _export,
            icon: const Icon(Icons.ios_share),
            label: Text(l.backupExport),
          ),
          if (_lastExportPath != null) ...[
            const SizedBox(height: 8),
            Text(l.backupExportedTo(_lastExportPath!),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          // ---- import -------------------------------------------------
          OutlinedButton.icon(
            onPressed: _working ? null : _import,
            icon: const Icon(Icons.restore),
            label: Text(l.backupImport),
          ),
          const SizedBox(height: 16),
          // ---- cloud backup (v1.8.0) ----------------------------------
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const CloudBackupScreen()));
            },
            icon: const Icon(Icons.cloud_sync_outlined),
            label: Text(l.cloudBackupTitle),
          ),
          const SizedBox(height: 12),
          Text(l.backupMergeNote,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ]),
      );

  // ---- actions ---------------------------------------------------------

  Future<void> _export() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _working = true);
    try {
      final svc = _service();
      final path = await svc.buildBackupFile();
      await svc.shareBackupFile(path);
      if (!mounted) return;
      setState(() => _lastExportPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.backupExportDone)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.backupFailed(e.toString()))));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _working = true);
    try {
      final svc = _service();
      final raw = await svc.pickBackupFile();
      if (!mounted) return;
      if (raw == null) {
        setState(() => _working = false);
        return;
      }
      final parsed = svc.parseBackup(raw); // throws BackupFormatException
      final confirmed = await _confirm(parsed.appVersion, parsed.exportedAt);
      if (!mounted) return;
      if (!confirmed) {
        setState(() => _working = false);
        return;
      }
      final result = await svc.mergeInto(parsed.payload);
      await _refresh();
      if (!mounted) return;
      setState(() => _working = false);
      await showDialog<void>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: Text(l.backupImportDoneTitle),
          content: Text(l.backupImportDone(
            result.addedItems,
            result.skippedItems,
            result.addedPlaylists,
            result.mergedPlaylists,
            result.restoredProgress,
            result.restoredSearches,
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: Text(l.ok),
            ),
          ],
        ),
      );
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorView.messageFor(context, _reasonToError(e)))));
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.backupFailed(e.toString()))));
    }
  }

  AppErrorType _reasonToError(BackupFormatException e) => switch (e.reason) {
        'empty' || 'json' || 'structure' => AppErrorType.invalidInput,
        'checksum' || 'format' || 'schema' => AppErrorType.unsupported,
        _ => AppErrorType.unknown,
      };

  Future<bool> _confirm(String appVersion, DateTime exportedAt) async {
    final l = AppLocalizations.of(context)!;
    final local = exportedAt.toLocal();
    final stamp =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final res = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l.backupConfirmTitle),
        content: Text(l.backupConfirmBody(appVersion, stamp)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: Text(l.backupConfirmRestore),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}
