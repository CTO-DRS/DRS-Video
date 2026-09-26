import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/smart/duplicate_detector.dart';
import '../../widgets/common/empty_state.dart';
import '../player/play_helpers.dart';

/// "التنظيف الذكي" — scans the library with [DuplicateDetector], groups
/// near-identical videos (normalized Arabic titles + duration/size checks)
/// and lets the user remove the weaker copies. The suggested survivor is
/// highlighted; deletion removes only library rows (never files on disk).
class SmartCleanupScreen extends StatefulWidget {
  const SmartCleanupScreen({super.key});

  @override
  State<SmartCleanupScreen> createState() => _SmartCleanupScreenState();
}

class _SmartCleanupScreenState extends State<SmartCleanupScreen> {
  late final DuplicateDetector _detector;
  List<DuplicateCluster> _clusters = [];
  final Set<String> _selectedForDelete = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detector = DuplicateDetector();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedForDelete.clear();
    });
    try {
      final library = context.read<LibraryRepository>();
      final pool = await library.query(const LibraryQuery(limit: 5000));
      if (!mounted) return;
      setState(() {
        _clusters = _detector.detect(pool);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _selectedCount => _selectedForDelete.length;

  Future<void> _deleteSelected() async {
    final l = AppLocalizations.of(context)!;
    if (_selectedCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cleanupConfirmTitle),
        content: Text(l.cleanupConfirmBody(_selectedCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final library = context.read<LibraryRepository>();
      await library.deleteMany(_selectedForDelete.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.cleanupDeleted(_selectedCount))),
      );
      await _scan();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l.cleanupFailed}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.cleanupTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _scan,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 12),
                      Text('${l.cleanupFailed}: $_error', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.tonal(onPressed: _scan, child: Text(l.retry)),
                    ],
                  ),
                )
              : _clusters.isEmpty
                  ? EmptyState(
                      icon: Icons.verified_outlined,
                      title: l.cleanupNoDuplicates,
                      body: l.cleanupNoDuplicatesBody,
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.cleanupFoundClusters(_clusters.length),
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _selectedCount == 0 ? null : _deleteSelected,
                                icon: const Icon(Icons.delete_sweep),
                                label: Text(l.cleanupDeleteSelected(_selectedCount)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: _clusters.length,
                            itemBuilder: (context, i) =>
                                _clusterCard(context, _clusters[i], theme, l),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _clusterCard(
      BuildContext context, DuplicateCluster cluster, ThemeData theme, AppLocalizations l) {
    final keep = cluster.keep;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.content_copy, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    keep?.title ?? cluster.keepId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // The suggested survivor first — no checkbox (never deletable here).
            if (keep != null)
              _memberTile(context, keep, theme, l, isKeep: true),
            for (final dup in cluster.duplicates)
              _memberTile(context, dup, theme, l, isKeep: false),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(
    BuildContext context,
    MediaItem item,
    ThemeData theme,
    AppLocalizations l, {
    required bool isKeep,
  }) {
    final selected = _selectedForDelete.contains(item.id);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: isKeep
          ? Icon(Icons.star, color: theme.colorScheme.primary)
          : Checkbox(
              value: selected,
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selectedForDelete.add(item.id);
                } else {
                  _selectedForDelete.remove(item.id);
                }
              }),
            ),
      title: Text(
        isKeep ? l.cleanupKeepSuggestion : item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isKeep ? FontWeight.bold : FontWeight.normal,
          color: isKeep ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        _describe(item, l),
        style: theme.textTheme.bodySmall,
      ),
      onTap: isKeep
          ? null
          : () => setState(() {
                selected
                    ? _selectedForDelete.remove(item.id)
                    : _selectedForDelete.add(item.id);
              }),
      trailing: isKeep
          ? null
          : IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: l.play,
              onPressed: () => openPlayerFromLibrary(context, item, [item]),
            ),
    );
  }

  String _describe(MediaItem item, AppLocalizations l) {
    final parts = <String>[];
    if (item.type == MediaItemType.download) {
      parts.add(l.typeDownload);
    } else if (item.type == MediaItemType.local) {
      parts.add(l.typeLocal);
    } else {
      parts.add(l.typeNetwork);
    }
    final d = item.durationMs;
    if (d != null && d > 0) {
      final m = (d / 60000).round();
      parts.add('$m ${l.minutesUnit}');
    }
    final s = item.sizeBytes;
    if (s != null && s > 0) {
      parts.add('${(s / (1024 * 1024)).toStringAsFixed(1)} MB');
    }
    return parts.join(' • ');
  }
}
