import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/stat_tile.dart';

/// v1.1.0 watch statistics: total watch time, 14-day activity chart,
/// most-watched titles and the current streak. All values come from the
/// real local database (watch_daily + play_count) — nothing invented.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _loading = true;
  Object? _error;
  int _totalMs = 0;
  int _streak = 0;
  List<WatchDayStat> _days = [];
  List<MediaItem> _top = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = context.read<HistoryRepository>();
      final library = context.read<LibraryRepository>();
      final results = await Future.wait([
        history.totalWatchedMs(),
        history.watchDaily(days: 14),
        history.currentStreakDays(),
        library.topPlayed(limit: 5),
      ]);
      if (!mounted) return;
      setState(() {
        _totalMs = results[0] as int;
        _days = results[1] as List<WatchDayStat>;
        _streak = results[2] as int;
        _top = results[3] as List<MediaItem>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _clearStats() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l.statsClear),
        content: Text(l.statsClearConfirm),
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
    if (confirmed != true || !mounted) return;
    await context.read<HistoryRepository>().clearWatchStats();
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.statsTitle),
        actions: [
          IconButton(
            tooltip: l.statsClear,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _totalMs == 0 && _days.isEmpty ? null : _clearStats,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: l.statsTitle,
                  body: '$_error',
                  actionLabel: l.retry,
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              icon: Icons.schedule_rounded,
                              label: l.statsTotalWatch,
                              value: Formatters.duration(_totalMs),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StatTile(
                              icon: Icons.local_fire_department_rounded,
                              label: l.statsStreak,
                              value: '$_streak',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(l.statsDaily14, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      _DailyChart(days: _days),
                      const SizedBox(height: 24),
                      Text(l.statsTopWatched, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      if (_top.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            l.statsNoData,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                      else
                        ..._top.asMap().entries.map((entry) {
                          final i = entry.key + 1;
                          final item = entry.value;
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text('$i'),
                            ),
                            title: Text(item.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Text(l.statsPlays(item.playCount)),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.days});

  final List<WatchDayStat> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxMs = days.fold<int>(1, (m, d) => d.watchedMs > m ? d.watchedMs : m);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Tooltip(
                message:
                    '${day.day}\n${Formatters.duration(day.watchedMs)}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FractionallySizedBox(
                    heightFactor: (day.watchedMs / maxMs).clamp(0.02, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
