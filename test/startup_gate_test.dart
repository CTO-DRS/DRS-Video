import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/app.dart';
import 'package:drs_video/features/splash/splash_screen.dart';
import 'package:drs_video/state/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

/// Critical Startup Failure regression tests.
///
/// Contract: the user must ALWAYS reach a real UI:
///  - success -> splash -> onboarding (first run) / shell
///  - any bootstrap failure -> visible error screen with retry + safe mode
///  - retry / safe mode must start a new attempt (stale attempts ignored)
///
/// sqflite_ffi talks to a real background isolate over several sequential
/// round-trips, so boot progress only advances when alternating real-async
/// time ([WidgetTester.runAsync]) with frame pumps. [_flushUntilResolved]
/// does that until the boot gate resolves into splash (success) or error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    // Mock connectivity channels: no real platform in widget tests.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  DrsApp appWith({bool Function(String step)? failStep}) {
    return DrsApp(
      runBootstrap: ({
        bool minimal = false,
        void Function(String stage)? onStage,
        bool Function(String step)? failStepForTest,
      }) {
        return bootstrap(
          minimal: minimal,
          onStage: onStage,
          failStepForTest: failStep ?? failStepForTest,
        );
      },
    );
  }

  bool _bootResolved(WidgetTester tester) =>
      find.byType(SplashScreen).evaluate().isNotEmpty;

  /// Alternates real async + pumps until bootstrap resolves (or timeout).
  Future<void> _flushUntilResolved(WidgetTester tester,
      {int maxMs = 12000}) async {
    for (var waited = 0; waited < maxMs; waited += 250) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();
      if (_bootResolved(tester)) return;
    }
  }

  /// Pumps the app and waits for boot to resolve.
  Future<void> pumpBoot(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await _flushUntilResolved(tester);
  }

  /// Plays through the 1.1s splash into the next gate (onboarding/shell).
  Future<void> pumpPastSplash(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('boot success reaches onboarding on first run', (tester) async {
    await pumpBoot(tester, appWith());
    expect(_bootResolved(tester), isTrue, reason: 'bootstrap must complete');
    await pumpPastSplash(tester);

    expect(find.text('Skip'), findsOneWidget,
        reason: 'first run must land on onboarding');
  });

  testWidgets('bootstrap failure shows real error screen, retry recovers',
      (tester) async {
    var failCritical = true;
    await tester.pumpWidget(appWith(
      failStep: (s) => failCritical && s == 'prefs',
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Error screen with retry + safe mode is visible (never a dead splash).
    expect(find.byKey(const Key('boot_retry')), findsOneWidget);
    expect(find.byKey(const Key('boot_safe_mode')), findsOneWidget);

    // Retry with the failure cleared -> same tree relaunches boot.
    failCritical = false;
    await tester.tap(find.byKey(const Key('boot_retry')));
    await _flushUntilResolved(tester);
    await pumpPastSplash(tester);

    expect(find.text('Skip'), findsOneWidget,
        reason: 'retry must reach the app UI after a failed boot');
  });

  testWidgets('safe mode boots with optional services skipped',
      (tester) async {
    var failOptional = true;
    await tester.pumpWidget(appWith(
      failStep: (s) =>
          failOptional && (s == 'notifications' || s == 'downloads'),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('boot_safe_mode')), findsOneWidget);

    // Safe mode skips optional steps -> boot succeeds even while the
    // failure condition stays active.
    await tester.tap(find.byKey(const Key('boot_safe_mode')));
    await _flushUntilResolved(tester);
    await pumpPastSplash(tester);

    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('boot failure error screen shows the actual cause',
      (tester) async {
    await tester.pumpWidget(appWith(
      failStep: (s) => s == 'database',
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // The raw cause must be visible to the user (diagnosability).
    expect(
      find.textContaining('simulated bootstrap failure'),
      findsOneWidget,
    );
  });
}
