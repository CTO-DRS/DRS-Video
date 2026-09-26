import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/smart/analytics_export.dart';
import '../../services/smart/watch_stats_engine.dart';

/// "نشاطي الذكي" — fully local viewing-statistics dashboard:
/// watch time, day streaks, peak hour, weekday distribution, 14-day trend
/// and top interest keywords. All numbers come from [WatchStatsEngine].
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  WatchStats? _stats;
  String? _error;
  bool _loading = true;

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
      final library = context.read<LibraryRepository>();
      final history = context.read<HistoryRepository>();

      final pool = await library.query(const LibraryQuery(limit: 5000));
      final progress = await history.progressMap();
      final progressByItem = <String, WatchProgress?>{
        for (final item in pool) item.id: progress[item.id],
      };

      final stats = WatchStatsEngine().compute(
        library: pool,
        progressByItem: progressByItem,
      );
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- v1.8.0: analytics export ---------------------------------------

  /// Bottom sheet with the two export flavours: full CSV inventory or a
  /// shareable text summary of the dashboard.
  Future<void> _exportSheet() async {
    final l = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(l.analyticsExportCsv),
              subtitle: Text(l.analyticsExportCsvDesc),
              onTap: () {
                Navigator.of(sheet).pop();
                _exportCsv();
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: Text(l.analyticsExportSummary),
              subtitle: Text(l.analyticsExportSummaryDesc),
              onTap: () {
                Navigator.of(sheet).pop();
                _shareSummary();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    try {
      final library = context.read<LibraryRepository>();
      final history = context.read<HistoryRepository>();
      final pool = await library.query(const LibraryQuery(limit: 100000));
      final progress = await history.progressMap();
      final csv = AnalyticsExport.buildHistoryCsv(pool, progress);
      final base = await getTemporaryDirectory();
      final stamp = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final file = File(
          '${base.path}/drs-video-analytics-${stamp.year}${two(stamp.month)}${two(stamp.day)}-${two(stamp.hour)}${two(stamp.minute)}.csv');
      await file.writeAsString(csv, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'DRS Video analytics',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.backupFailed(e.toString()))));
    }
  }

  Future<void> _shareSummary() async {
    final l = AppLocalizations.of(context)!;
    final s = _stats;
    if (s == null) return;

    final text = [
      '${l.activityTitle} — DRS Video',
      '━━━━━━━━━━━━━━━━',
      '${l.statWatchTime}: ${Formatters.duration(s.totalWatchMs)}',
      '${l.statWatched}: ${s.watchedCount}',
      '${l.statCompleted}: ${s.completedCount}',
      '${l.statStreak}: ${s.currentStreakDays} ${l.daysUnit} (${l.bestStreak(s.bestStreakDays)})',
      if (s.peakHour != null) l.peakHourLabel(s.peakHour!),
      if (s.topInterests.isNotEmpty)
        '${l.topInterestsTitle}: ${s.topInterests.join(' · ')}',
    ].join('\n');
    await Share.share(text, subject: 'DRS Video — ${l.activityTitle}');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.activityTitle),
        actions: [
          // v1.8.0: export full inventory CSV + share text summary.
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l.analyticsExport,
            onPressed: _loading ? null : _exportSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView(theme, l)
              : _stats == null || _stats!.watchedCount == 0
                  ? EmptyActivityView(theme: theme, title: l.activityEmptyTitle, body: l.activityEmptyBody)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _summaryGrid(theme, l),
                          const SizedBox(height: 12),
                          _StreakCard(stats: _stats!, l: l),
                          const SizedBox(height: 12),
                          _TrendCard(stats: _stats!, l: l, theme: theme),
                          const SizedBox(height: 12),
                          _PatternsCard(stats: _stats!, l: l, theme: theme),
                          const SizedBox(height: 12),
                          if (_stats!.topInterests.isNotEmpty)
                            _InterestsCard(stats: _stats!, l: l, theme: theme),
                        ],
                      ),
                    ),
    );
  }

  Widget _errorView(ThemeData theme, AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(l.activityFailed, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: _load, child: Text(l.retry)),
        ],
      ),
    );
  }

  Widget _summaryGrid(ThemeData theme, AppLocalizations l) {
    final s = _stats!;
    final hours = s.totalWatchMs / 3600000.0;
    final minutes = (s.totalWatchMs % 3600000) / 60000.0;
    final watchTime = hours >= 1
        ? '${hours.toStringAsFixed(1)} ${l.hoursUnit}'
        : '${minutes.round()} ${l.minutesUnit}';

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        _StatTile(icon: Icons.schedule, label: l.statWatchTime, value: watchTime, theme: theme),
        _StatTile(icon: Icons.movie_outlined, label: l.statWatched, value: '${s.watchedCount}', theme: theme),
        _StatTile(icon: Icons.done_all, label: l.statCompleted, value: '${s.completedCount}', theme: theme),
        _StatTile(
            icon: Icons.local_fire_department,
            label: l.statStreak,
            value: '${s.currentStreakDays} ${l.daysUnit}',
            theme: theme),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value, required this.theme});

  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const Spacer(),
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.stats, required this.l});

  final WatchStats stats;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peak = stats.peakHour;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined, color: theme.colorScheme.primary, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.bestStreak(stats.bestStreakDays),
                    style: theme.textTheme.titleMedium,
                  ),
                  if (peak != null)
                    Text(l.peakHourLabel(peak), style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 14-day watched-time trend as simple proportional bars.
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.stats, required this.l, required this.theme});

  final WatchStats stats;
  final AppLocalizations l;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final maxMs = stats.dayBuckets.fold<int>(1, (a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.trend14Title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final ms in stats.dayBuckets)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FractionallySizedBox(
                          alignment: Alignment.bottomCenter,
                          heightFactor: ms == 0 ? 0.02 : ms / maxMs,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: ms == 0
                                  ? theme.colorScheme.surfaceContainerHighest
                                  : theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(l.trend14Caption, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PatternsCard extends StatelessWidget {
  const _PatternsCard({required this.stats, required this.l, required this.theme});

  final WatchStats stats;
  final AppLocalizations l;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final maxWeek = stats.activityByWeekday.fold<int>(1, (a, b) => a > b ? a : b);
    final dayNames = [
      l.weekdayMon, l.weekdayTue, l.weekdayWed, l.weekdayThu,
      l.weekdayFri, l.weekdaySat, l.weekdaySun,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.weekdayPatternTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            for (var d = 0; d < 7; d++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 40, child: Text(dayNames[d], style: theme.textTheme.bodySmall)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: stats.activityByWeekday[d] / maxWeek,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text('${stats.activityByWeekday[d]}',
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.end),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InterestsCard extends StatelessWidget {
  const _InterestsCard({required this.stats, required this.l, required this.theme});

  final WatchStats stats;
  final AppLocalizations l;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.topInterestsTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kw in stats.topInterests)
                  Chip(
                    label: Text(kw),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyActivityView extends StatelessWidget {
  const EmptyActivityView({
    super.key,
    required this.theme,
    required this.title,
    required this.body,
  });

  final ThemeData theme;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
