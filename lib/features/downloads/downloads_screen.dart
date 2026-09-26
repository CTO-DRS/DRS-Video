import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/utils/formatters.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/download_task.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/downloader/download_service.dart';
import '../../services/sharing/share_service.dart';
import '../../state/downloads_controller.dart';
import '../../widgets/common/empty_state.dart';
import '../player/play_helpers.dart';

/// Download manager UI: active, queued, completed, failed with full controls.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DownloadsController>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadsController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Native download engine failed to initialize: honest degraded state
    // with a real retry action (the rest of the app keeps working).
    final engine = context.watch<DownloadService>();
    if (engine.degraded) {
      return Scaffold(
        appBar: AppBar(title: Text(l.navDownloads)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 52, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text(l.dlDegradedTitle,
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center),
                if (engine.initError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    engine.initError!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontFamily: 'monospace', fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => engine.retryInit(),
                  icon: const Icon(Icons.refresh),
                  label: Text(l.dlDegradedRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (controller.tasks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l.navDownloads)),
        body: EmptyState(
          icon: Icons.download_outlined,
          title: l.emptyDownloadsTitle,
          body: l.emptyDownloadsBody,
        ),
      );
    }

    final active = controller.tasks
        .where((t) => t.status == DownloadStatus.running || t.status == DownloadStatus.paused)
        .toList();
    final queued = controller.tasks.where((t) => t.status == DownloadStatus.queued).toList();
    final completed = controller.tasks.where((t) => t.status == DownloadStatus.completed).toList();
    final failed = controller.tasks.where((t) => t.status == DownloadStatus.failed).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navDownloads),
        actions: [
          IconButton(
            tooltip: l.downloadsPauseAll,
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: active.isEmpty ? null : controller.pauseAll,
          ),
          IconButton(
            tooltip: l.downloadsResumeAll,
            icon: const Icon(Icons.play_circle_outline),
            onPressed: controller.resumeAll,
          ),
          // v1.8.0: one-tap recovery for every failed download.
          IconButton(
            tooltip: l.downloadsRetryAll,
            icon: const Icon(Icons.refresh),
            onPressed: failed.isEmpty ? null : controller.retryAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          FutureBuilder<int>(
            future: controller.freeSpace(),
            builder: (context, snap) {
              if (!snap.hasData || snap.data! < 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  l.downloadsFreeSpace(Formatters.bytes(snap.data!)),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            },
          ),
          if (controller.waitingForWifi)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.wifi_off),
                  title: Text(l.downloadsWifiOnlyWarning,
                      style: theme.textTheme.bodySmall),
                  dense: true,
                ),
              ),
            ),
          if (queued.isNotEmpty) _sectionHeader(context, l.downloadsQueued),
          for (final t in queued) _QueuedTile(task: t),
          if (active.isNotEmpty) _sectionHeader(context, l.downloadsActive),
          for (final t in active) _ActiveTile(task: t),
          if (completed.isNotEmpty) _sectionHeader(context, l.downloadsCompleted),
          for (final t in completed) _CompletedTile(task: t),
          if (failed.isNotEmpty) _sectionHeader(context, l.downloadsFailed),
          for (final t in failed) _FailedTile(task: t),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(title,
          style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary)),
    );
  }
}

class _QueuedTile extends StatelessWidget {
  const _QueuedTile({required this.task});

  final DownloadTaskModel task;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<DownloadsController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ListTile(
      leading: const Icon(Icons.hourglass_top),
      title: Text(task.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${l.downloadsPriority}: ${_priorityLabel(l, task.priority)}'
        ' · ${task.expectedSize != null ? Formatters.bytes(task.expectedSize!) : "?"}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          switch (action) {
            case 'high':
              controller.setPriority(task.id, DownloadPriority.high);
            case 'normal':
              controller.setPriority(task.id, DownloadPriority.normal);
            case 'low':
              controller.setPriority(task.id, DownloadPriority.low);
            case 'start':
              controller.resume(task.id);
            case 'cancel':
              controller.cancel(task.id);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'high', child: Text(l.downloadsPriorityHigh)),
          PopupMenuItem(value: 'normal', child: Text(l.downloadsPriorityNormal)),
          PopupMenuItem(value: 'low', child: Text(l.downloadsPriorityLow)),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'start', child: Text(l.resumeAction)),
          PopupMenuItem(value: 'cancel', child: Text(l.cancel)),
        ],
      ),
    );
  }

  static String _priorityLabel(AppLocalizations l, DownloadPriority p) =>
      switch (p) {
        DownloadPriority.high => l.downloadsPriorityHigh,
        DownloadPriority.normal => l.downloadsPriorityNormal,
        DownloadPriority.low => l.downloadsPriorityLow,
      };
}

class _ActiveTile extends StatelessWidget {
  const _ActiveTile({required this.task});

  final DownloadTaskModel task;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DownloadsController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final speed = controller.speedOf(task.id) ?? 0;
    final remaining = task.expectedSize != null
        ? task.expectedSize! * (100 - task.progress) ~/ 100
        : 0;
    final isPaused = task.status == DownloadStatus.paused;

    return ListTile(
      leading: Icon(isPaused ? Icons.pause_circle : Icons.downloading),
      title: Text(task.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: task.progress / 100, minHeight: 6),
          ),
          const SizedBox(height: 4),
          Text(
            '${Formatters.percent(task.progress.toDouble())}'
            ' · ${Formatters.speed(speed)}'
            ' · ${Formatters.eta(remaining, speed)}'
            '${task.expectedSize != null ? ' · ${Formatters.bytes(task.expectedSize!)}' : ''}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: isPaused ? l.resumeAction : l.pause,
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
            onPressed: () =>
                isPaused ? controller.resume(task.id) : controller.pause(task.id),
          ),
          IconButton(
            tooltip: l.cancel,
            icon: const Icon(Icons.close),
            onPressed: () => controller.cancel(task.id),
          ),
        ],
      ),
    );
  }
}

class _CompletedTile extends StatelessWidget {
  const _CompletedTile({required this.task});

  final DownloadTaskModel task;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<DownloadsController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ListTile(
      leading: const Icon(Icons.download_done, color: Colors.green),
      title: Text(task.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${task.expectedSize != null ? Formatters.bytes(task.expectedSize!) : '-'}'
        '${task.completedAt != null ? ' · ${Formatters.dateTime(task.completedAt!)}' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l.play,
            icon: const Icon(Icons.play_circle),
            onPressed: () => _play(context),
          ),
          IconButton(
            tooltip: l.share,
            icon: const Icon(Icons.share),
            onPressed: () =>
                context.read<ShareService>().shareFile(task.filePath),
          ),
          PopupMenuButton<String>(
            onSelected: (a) {
              if (a == 'delete') {
                controller.remove(task.id, deleteFile: true);
              } else if (a == 'open') {
                context.read<ShareService>().openWith(task.filePath);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'open', child: Text(l.actionOpenWith)),
              PopupMenuItem(value: 'delete', child: Text(l.delete)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _play(BuildContext context) async {
    final library = context.read<LibraryRepository>();
    var item = await library.byUri(task.filePath);
    item ??= MediaItem(
      id: 'md_${task.id}',
      title: task.fileName,
      uri: task.filePath,
      type: MediaItemType.download,
      sizeBytes: task.expectedSize,
    );
    if (!context.mounted) return;
    await openPlayerFromLibrary(context, item, [item]);
  }
}

class _FailedTile extends StatelessWidget {
  const _FailedTile({required this.task});

  final DownloadTaskModel task;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<DownloadsController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
      title: Text(task.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        task.error ?? l.downloadsCorruptedFile,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.error),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.retry(task.id),
          ),
          IconButton(
            tooltip: l.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => controller.remove(task.id, deleteFile: true),
          ),
        ],
      ),
    );
  }
}
