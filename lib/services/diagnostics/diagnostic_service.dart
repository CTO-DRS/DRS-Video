import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/storage/cache_manager.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/preferences_service.dart';
import '../../core/utils/crash_store.dart';
import '../../core/utils/logger.dart';
import '../../services/notifications/notification_service.dart';
import '../../services/platform/native_channel.dart';

/// Error detection & diagnostics engine (v1.0.3).
///
/// Runs deterministic health checks over every critical service, collects
/// device facts, and builds a shareable report. Everything is local —
/// nothing leaves the device unless the user copies/shares the report.
enum DiagnosticStatus { pass, degraded, fail }

class DiagnosticCheck {
  const DiagnosticCheck({
    required this.id,
    required this.status,
    required this.detail,
    this.elapsedMs,
  });

  final String id;
  final DiagnosticStatus status;
  final String detail;
  final int? elapsedMs;

  String get timing => elapsedMs == null ? '' : ' (${elapsedMs}ms)';
}

class DeviceFacts {
  const DeviceFacts({
    required this.model,
    required this.manufacturer,
    required this.androidVersion,
    required this.sdkInt,
    required this.abis,
    required this.appVersion,
    required this.appName,
    required this.freeBytes,
    required this.totalBytes,
  });

  final String model;
  final String manufacturer;
  final String androidVersion;
  final int sdkInt;
  final List<String> abis;
  final String appVersion;
  final String appName;
  final int freeBytes;
  final int totalBytes;

  bool get is64Bit =>
      abis.any((a) => a.startsWith('arm64') || a.startsWith('x86_64'));
}

class DiagnosticService {
  const DiagnosticService();

  Future<DeviceFacts> collectFacts(String storageProbePath) async {
    var model = 'unknown';
    var manufacturer = 'unknown';
    var androidVersion = 'unknown';
    var sdkInt = 0;
    var abis = const <String>[];
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      model = info.model;
      manufacturer = info.manufacturer;
      androidVersion = info.version.release;
      sdkInt = info.version.sdkInt;
      abis = List<String>.from(info.supportedAbis);
    } catch (e) {
      AppLogger.instance.warning('diag', 'device info failed: $e');
    }

    var appVersion = 'unknown';
    var appName = 'DRS Video';
    try {
      final p = await PackageInfo.fromPlatform();
      appVersion = '${p.version} (${p.buildNumber})';
      appName = p.appName;
    } catch (e) {
      AppLogger.instance.warning('diag', 'package info failed: $e');
    }

    final free = await NativeChannel.instance.freeSpaceBytes(storageProbePath);
    final total =
        await NativeChannel.instance.totalSpaceBytes(storageProbePath);

    return DeviceFacts(
      model: model,
      manufacturer: manufacturer,
      androidVersion: androidVersion,
      sdkInt: sdkInt,
      abis: abis,
      appVersion: appVersion,
      appName: appName,
      freeBytes: free,
      totalBytes: total,
    );
  }

  /// Runs every check. Each check is isolated: a throwing probe is
  /// reported as [DiagnosticStatus.fail] with its error, never propagated.
  Future<List<DiagnosticCheck>> runChecks({
    required PreferencesService prefs,
    required Future<void> Function() ensurePlayer,
    required bool Function() playerReady,
    required String? Function() playerError,
    required Future<void> Function() ensureDownloader,
    required bool downloaderDegraded,
    String? downloaderError,
  }) async {
    return [
      await _run('prefs', () async {
        final v = prefs.raw.getString('diag_probe');
        return DiagnosticCheck(
            id: 'prefs',
            status: DiagnosticStatus.pass,
            detail: 'shared_preferences readable (${v ?? 'no data'})');
      }),
      await _run('database', () async {
        final db = await DatabaseService.instance.database;
        final r = await db.rawQuery('SELECT 1 AS ok');
        if (r.isEmpty) throw StateError('SELECT 1 returned no rows');
        return const DiagnosticCheck(
            id: 'database',
            status: DiagnosticStatus.pass,
            detail: 'database open and responding');
      }),
      await _run('storage', () async {
        final base = await getApplicationSupportDirectory();
        final f = File(
            '${base.path}/diag_probe_${DateTime.now().millisecondsSinceEpoch}.tmp');
        const payload = 'drs-probe';
        await f.writeAsString(payload, flush: true);
        final readBack = await f.readAsString();
        await f.delete();
        if (readBack != payload) throw StateError('readback mismatch');
        final free = await NativeChannel.instance.freeSpaceBytes(base.path);
        return DiagnosticCheck(
            id: 'storage',
            status: DiagnosticStatus.pass,
            detail: free >= 0
                ? 'app storage writable; free=${(free / 1024 / 1024).round()}MB'
                : 'app storage writable');
      }),
      await _run('player', () async {
        await ensurePlayer();
        if (playerReady()) {
          return const DiagnosticCheck(
              id: 'player',
              status: DiagnosticStatus.pass,
              detail: 'mpv engine ready');
        }
        throw StateError(playerError() ?? 'engine unavailable');
      }),
      await _run('downloader', () async {
        await ensureDownloader();
        if (!downloaderDegraded) {
          return const DiagnosticCheck(
              id: 'downloader',
              status: DiagnosticStatus.pass,
              detail: 'WorkManager download engine initialized');
        }
        return DiagnosticCheck(
          id: 'downloader',
          status: DiagnosticStatus.degraded,
          detail: downloaderError ?? 'degraded',
        );
      }),
      await _run('notifications', () async {
        await NotificationService.instance.init();
        if (NotificationService.instance.isReady) {
          return const DiagnosticCheck(
              id: 'notifications',
              status: DiagnosticStatus.pass,
              detail: 'notification channels ready');
        }
        return const DiagnosticCheck(
          id: 'notifications',
          status: DiagnosticStatus.degraded,
          detail: 'plugin unavailable — notifications disabled',
        );
      }),
      await _run('native_channel', () async {
        final v = await NativeChannel.instance.freeSpaceBytes('/');
        if (v < 0) throw StateError('method channel did not answer');
        return const DiagnosticCheck(
            id: 'native_channel',
            status: DiagnosticStatus.pass,
            detail: 'platform bridge OK');
      }),
      await _run('cache', () async {
        final stats = await CacheManager.instance.stats();
        final totalBytes = stats.thumbnailsBytes + stats.tempBytes;
        return DiagnosticCheck(
            id: 'cache',
            status: DiagnosticStatus.pass,
            detail: 'cache ok: ${stats.files} files, '
                '${(totalBytes / 1024 / 1024).toStringAsFixed(1)}MB');
      }),
      await _run('crash_store', () async {
        final previous = await CrashStore.instance.readPrevious();
        if (previous == null) {
          return const DiagnosticCheck(
              id: 'crash_store',
              status: DiagnosticStatus.pass,
              detail: 'no crash records from previous session');
        }
        return DiagnosticCheck(
          id: 'crash_store',
          status: DiagnosticStatus.degraded,
          detail: 'previous session recorded errors '
              '(${previous.length} chars) — see the crash section below',
        );
      }),
    ];
  }

  Future<DiagnosticCheck> _run(
      String id, Future<DiagnosticCheck> Function() probe) async {
    final sw = Stopwatch()..start();
    try {
      final c = await probe();
      sw.stop();
      return DiagnosticCheck(
        id: id,
        status: c.status,
        detail: c.detail,
        elapsedMs: sw.elapsedMilliseconds,
      );
    } catch (e, s) {
      sw.stop();
      AppLogger.instance.error('diag', 'check $id failed', e, s);
      return DiagnosticCheck(
        id: id,
        status: DiagnosticStatus.fail,
        detail: '$e',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Full plain-text report (localization-free so it stays copyable).
  static String buildReport({
    required DeviceFacts facts,
    required List<DiagnosticCheck> checks,
    String? crashLogs,
    String? sessionLog,
  }) {
    final b = StringBuffer()
      ..writeln('=== DRS Video diagnostics report ===')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln('App: ${facts.appName} ${facts.appVersion}')
      ..writeln(
          'Device: ${facts.manufacturer} ${facts.model} — Android ${facts.androidVersion} (SDK ${facts.sdkInt})')
      ..writeln(
          'ABIs: ${facts.abis.join(", ")} (${facts.is64Bit ? '64-bit' : '32-bit'})')
      ..writeln(
          'Storage: free=${(facts.freeBytes / 1024 / 1024).round()}MB / total=${(facts.totalBytes / 1024 / 1024).round()}MB')
      ..writeln()
      ..writeln('-- Health checks --');
    for (final c in checks) {
      b.writeln('${c.status.name.toUpperCase().padRight(8)} ${c.id}'
          '${c.timing}: ${c.detail}');
    }
    if (crashLogs != null && crashLogs.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('-- Crash records --')
        ..writeln(crashLogs.trim());
    }
    if (sessionLog != null && sessionLog.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('-- Session log (tail) --')
        ..writeln(sessionLog.trim());
    }
    return b.toString();
  }
}
