import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/storage/cache_manager.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/storage/storage_analyzer.dart';
import '../../state/settings_controller.dart';
import '../../widgets/common/empty_state.dart';

/// Storage management: cache stats, clear actions, analyzer
/// (largest files / oldest unplayed) — all computed locally.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  CacheStats? _stats;
  StorageReport? _report;
  bool _analyzing = true;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() => _analyzing = true);
    try {
      final stats = await CacheManager.instance.stats();
      final dir = context.read<SettingsController>().downloadDir;
      StorageReport? report;
      if (dir != null) {
        final library = context.read<LibraryRepository>();
        final downloads = await library
            .query(const LibraryQuery(type: MediaItemType.download, limit: 300));
        report = await context.read<StorageAnalyzer>().analyze(
              downloadDir: dir,
              downloadedItems: [
                for (final d in downloads) (d.uri, d.lastPlayedAt),
              ],
            );
      }
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _report = report;
        _analyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.storageAnalyzer),
        actions: [
          IconButton(
            tooltip: l.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _analyze,
          ),
        ],
      ),
      body: _analyzing
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _analyze,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_stats != null) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.image_outlined),
                        title: Text(l.storageThumbnails),
                        trailing: Text(Formatters.bytes(_stats!.thumbnailsBytes)),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.dns),
                        title: Text(l.storageClearCache),
                        trailing: Text(Formatters.bytes(_stats!.tempBytes)),
                        onTap: () async {
                          await CacheManager.instance.clearThumbnails();
                          await CacheManager.instance.clearTemp();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.storageCleared)));
                          _analyze();
                        },
                      ),
                    ),
                  ],
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(l.setDownloadFolder),
                      subtitle: Text(settings.downloadDir ?? '-'),
                    ),
                  ),
                  if (_report != null) ...[
                    const SizedBox(height: 16),
                    Text(l.storageLargestFiles, style: theme.textTheme.titleSmall),
                    for (final f in _report!.largestFiles)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.movie_outlined, size: 20),
                        title: Text(
                          fileNameOf(f.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(Formatters.bytes(f.sizeBytes)),
                      ),
                    const SizedBox(height: 16),
                    Text(l.storageOldestUnplayed, style: theme.textTheme.titleSmall),
                    if (_report!.oldestUnplayed.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(l.emptyGenericTitle,
                            style: theme.textTheme.bodySmall),
                      ),
                    for (final f in _report!.oldestUnplayed)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.schedule, size: 20),
                        title: Text(
                          fileNameOf(f.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(Formatters.dateTime(f.modified)),
                        trailing: Text(Formatters.bytes(f.sizeBytes)),
                      ),
                  ],
                  if (_report == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: EmptyState(
                        icon: Icons.storage,
                        title: 'No download folder set yet',
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

String fileNameOf(String path) {
  final parts = path.split('/');
  return parts.isEmpty ? path : parts.last;
}
