import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/crash_store.dart';
import '../../core/utils/logger.dart';
import '../../l10n/app_localizations.dart';
import '../../services/diagnostics/diagnostic_service.dart';
import '../../services/platform/native_channel.dart';
import '../../state/app_providers.dart';

/// Diagnostics & errors screen: deterministic service health checks,
/// device facts, crash records and session log — copyable/shareable.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<DiagnosticCheck>? _checks;
  DeviceFacts? _facts;
  String? _crashLogs;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  Future<void> _runAll() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final services = context.read<AppServices>();
      final service = const DiagnosticService();
      final probePath = services.prefs.downloadDir ?? '/';

      final facts = await service.collectFacts(probePath);
      final checks = await service.runChecks(
        prefs: services.prefs,
        ensurePlayer: () => services.player.ensureEngine(),
        playerReady: () => services.player.engineReady,
        playerError: () => services.player.engineError,
        ensureDownloader: () => services.downloader.init(),
        downloaderDegraded: services.downloader.degraded,
        downloaderError: services.downloader.initError,
      );
      final crashes = await _loadCrashLogs();
      if (!mounted) return;
      setState(() {
        _facts = facts;
        _checks = checks;
        _crashLogs = crashes;
      });
    } catch (e, s) {
      AppLogger.instance.error('diag', 'runAll failed', e, s);
      if (!mounted) return;
      setState(() => _checks = const []);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<String?> _loadCrashLogs() async {
    final dart = await CrashStore.instance.readPrevious();
    final native = await NativeChannel.instance.nativeCrashLog();
    final parts = <String>[
      if (dart != null && dart.isNotEmpty) 'Dart log:\n$dart',
      if (native != null && native.isNotEmpty) 'Native log:\n$native',
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  Future<String?> _loadSessionLog() async {
    final log = AppLogger.instance.export();
    if (log.isEmpty) return null;
    final lines = log.split('\n');
    return lines.length > 120 ? lines.sublist(lines.length - 120).join('\n') : log;
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.diagReportCopied)));
  }

  Future<void> _shareReport() async {
    final facts = _facts;
    final checks = _checks;
    if (facts == null || checks == null) return;
    final session = await _loadSessionLog();
    final report = DiagnosticService.buildReport(
      facts: facts,
      checks: checks,
      crashLogs: _crashLogs,
      sessionLog: session,
    );
    await _copy(report);
    await Share.share(report);
  }

  Future<void> _clearCrashRecords() async {
    await CrashStore.instance.clear();
    await NativeChannel.instance.clearNativeCrashLog();
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.diagLogsCleared)));
    setState(() => _crashLogs = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final checks = _checks;

    return Scaffold(
      appBar: AppBar(title: Text(l.setDiagnostics)),
      body: RefreshIndicator(
        onRefresh: _runAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (_facts != null) _FactsCard(facts: _facts!),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(l.diagChecksSection,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _running ? null : _runAll,
                  icon: _running
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.radar, size: 18),
                  label: Text(l.diagRunChecks),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (checks == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final c in checks) _CheckTile(check: c),
            const SizedBox(height: 16),
            _CrashSection(
              crashLogs: _crashLogs,
              onCopy: () => _copy(_crashLogs ?? ''),
              onClear: _clearCrashRecords,
            ),
            const SizedBox(height: 12),
            _SessionLogSection(
              onCopy: () async {
                final s = await _loadSessionLog();
                if (s != null) await _copy(s);
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _shareReport,
              icon: const Icon(Icons.ios_share),
              label: Text(l.diagShareReport),
            ),
            const SizedBox(height: 8),
            Text(
              l.diagLocalNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts});

  final DeviceFacts facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    String mb(int v) => '${(v / 1024 / 1024).round()}MB';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.diagDeviceSection,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _factRow(l.diagFactsApp, '${facts.appName} ${facts.appVersion}'),
            _factRow(l.diagFactsDevice,
                '${facts.manufacturer} ${facts.model}'),
            _factRow(l.diagFactsAndroid,
                '${facts.androidVersion} (SDK ${facts.sdkInt})'),
            _factRow(l.diagFactsAbi,
                '${facts.abis.join(", ")} — ${facts.is64Bit ? '64-bit' : '32-bit'}'),
            _factRow(l.diagFactsStorage, '${mb(facts.freeBytes)} / ${mb(facts.totalBytes)}'),
          ],
        ),
      ),
    );
  }

  Widget _factRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});

  final DiagnosticCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final (icon, color, label) = switch (check.status) {
      DiagnosticStatus.pass => (
          Icons.check_circle_outline,
          const Color(0xFF2E9E5B),
          l.diagStatusPass
        ),
      DiagnosticStatus.degraded => (
          Icons.warning_amber_outlined,
          const Color(0xFFB8860B),
          l.diagStatusDegraded
        ),
      DiagnosticStatus.fail => (
          Icons.error_outline,
          theme.colorScheme.error,
          l.diagStatusFail
        ),
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(checkLabel(l, check.id)),
        subtitle: Text('${check.detail}${check.timing}',
            style: theme.textTheme.bodySmall),
        dense: true,
      ),
    );
  }

  String checkLabel(AppLocalizations l, String id) => switch (id) {
        'prefs' => l.diagCheckPrefs,
        'database' => l.diagCheckDatabase,
        'storage' => l.diagCheckStorage,
        'player' => l.diagCheckPlayer,
        'downloader' => l.diagCheckDownloader,
        'notifications' => l.diagCheckNotifications,
        'native_channel' => l.diagCheckNative,
        'cache' => l.diagCheckCache,
        'crash_store' => l.diagCheckCrashes,
        _ => id,
      };
}

class _CrashSection extends StatelessWidget {
  const _CrashSection({
    required this.crashLogs,
    required this.onCopy,
    required this.onClear,
  });

  final String? crashLogs;
  final Future<void> Function() onCopy;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final has = crashLogs != null && crashLogs!.trim().isNotEmpty;

    return Card(
      color: has ? theme.colorScheme.errorContainer.withOpacity(0.25) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(has ? Icons.bug_report : Icons.verified_outlined,
                    size: 20,
                    color: has ? theme.colorScheme.error : const Color(0xFF2E9E5B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.diagCrashesSection,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (has) ...[
                  IconButton(
                    tooltip: l.diagCopyReport,
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                  IconButton(
                    tooltip: l.diagClearLogs,
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            if (!has)
              Text(l.diagNoCrashes, style: theme.textTheme.bodySmall)
            else
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(l.diagPrevCrashDetails, style: theme.textTheme.bodySmall),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      crashLogs!,
                      maxLines: 30,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace', fontSize: 10),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionLogSection extends StatelessWidget {
  const _SessionLogSection({required this.onCopy});

  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(l.diagSessionLog),
        subtitle: Text(l.diagSessionLogBody),
        trailing: IconButton(
          tooltip: l.diagCopyReport,
          onPressed: onCopy,
          icon: const Icon(Icons.copy, size: 18),
        ),
        dense: true,
      ),
    );
  }
}
