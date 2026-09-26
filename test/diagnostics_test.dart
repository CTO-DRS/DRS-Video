import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/services/diagnostics/diagnostic_service.dart';
import 'package:drs_video/core/storage/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

/// Error detection system (v1.0.3) regression tests.
///
/// Contract: every check is isolated and deterministic — a failing probe
/// degrades to a FAIL check with its error text, never throws; the report
/// builder always produces copyable text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Connectivity: wifi (existing services rely on it).
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  Future<List<DiagnosticCheck>> runAll() async {
    final prefs = PreferencesService(await SharedPreferences.getInstance());
    return const DiagnosticService().runChecks(
      prefs: prefs,
      // In tests there is no native mpv: pretend the engine came up, so
      // the player probe exercises the PASS path; a dedicated test below
      // covers the FAIL path.
      ensurePlayer: () async {},
      playerReady: () => true,
      playerError: () => null,
      ensureDownloader: () async {},
      downloaderDegraded: false,
    );
  }

  testWidgets('health checks run end to end and never throw', (tester) async {
    List<DiagnosticCheck>? checks;
    Object? thrown;
    await tester.runAsync(() async {
      try {
        checks = await runAll();
      } catch (e) {
        thrown = e;
      }
    });
    expect(thrown, isNull, reason: 'runChecks must never propagate');
    expect(checks, isNotNull);

    final byId = {for (final c in checks!) c.id: c};
    for (final id in ['prefs', 'database', 'player', 'downloader']) {
      expect(byId[id], isNotNull, reason: 'check $id must always run');
      expect(byId[id]!.status, DiagnosticStatus.pass,
          reason: '$id should pass in test env: ${byId[id]?.detail}');
    }
    // Notification plugin has no native side in tests -> degraded, not fail.
    expect(byId['notifications']!.status, anyOf(
      DiagnosticStatus.degraded,
      DiagnosticStatus.pass,
    ));
  });

  testWidgets('failing probes degrade to FAIL with the error text',
      (tester) async {
    final prefs = PreferencesService(await SharedPreferences.getInstance());
    final checks = (await tester.runAsync(
      () => const DiagnosticService().runChecks(
        prefs: prefs,
        // Engine unavailable on this device -> honest FAIL result.
        ensurePlayer: () async {
          throw StateError('libmpv failed to load');
        },
        playerReady: () => false,
        playerError: () => 'libmpv failed to load',
        ensureDownloader: () async {},
        downloaderDegraded: true,
        downloaderError: 'WorkManager init error',
      ),
    ))!;

    final player = checks.firstWhere((c) => c.id == 'player');
    expect(player.status, DiagnosticStatus.fail);
    expect(player.detail, contains('libmpv failed to load'));

    final downloader = checks.firstWhere((c) => c.id == 'downloader');
    expect(downloader.status, DiagnosticStatus.degraded);
    expect(downloader.detail, contains('WorkManager init error'));
  });

  test('report builder produces shareable text', () {
    const facts = DeviceFacts(
      model: 'SM-A700F',
      manufacturer: 'Samsung',
      androidVersion: '7.0',
      sdkInt: 24,
      abis: ['armeabi-v7a'],
      appVersion: '1.0.3 (4)',
      appName: 'DRS Video',
      freeBytes: 1000 * 1024 * 1024,
      totalBytes: 8000 * 1024 * 1024,
    );
    final report = DiagnosticService.buildReport(
      facts: facts,
      checks: const [
        DiagnosticCheck(
            id: 'database',
            status: DiagnosticStatus.pass,
            detail: 'ok',
            elapsedMs: 12),
        DiagnosticCheck(
            id: 'player', status: DiagnosticStatus.fail, detail: 'boom'),
      ],
      crashLogs: 'Dart log:\nsomething broke',
    );

    expect(report, contains('DRS Video 1.0.3 (4)'));
    expect(report, contains('Android 7.0 (SDK 24)'));
    expect(report, contains('armeabi-v7a'));
    expect(report, contains('database (12ms): ok'));
    expect(report, contains('PASS'));
    expect(report, contains('FAIL'));
    expect(report, contains('player: boom'));
    expect(report, contains('Dart log:'));
  });
}
