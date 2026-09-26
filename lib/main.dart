import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/utils/crash_store.dart';
import 'core/utils/logger.dart';

/// Startup contract (post fix for the critical startup failure):
///
/// 1. [runApp] MUST be called immediately — the user must always reach a
///    real, visible UI (branded boot screen) even if a native service
///    hangs or fails. Previously the entire service bootstrap ran BEFORE
///    runApp, so any failure left the app stuck on the OS launch screen
///    with no error message at all.
/// 2. All unhandled errors (framework, platform, zone) are recorded into
///    the in-memory logger AND the persistent [CrashStore], so the NEXT
///    launch can show the actual reason on the boot screen — no adb or
///    developer tools required.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Friendly error surface for widget build/paint errors: instead of the
  // grey/red developer screen, the user sees a real localized-style card.
  // The cause is still recorded (memory + persistent store).
  ErrorWidget.builder = (details) {
    AppLogger.instance.error(
      'widget',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
    CrashStore.instance
        .record('widget', details.exception, details.stack ?? StackTrace.empty);
    return _FriendlyErrorView(details: details);
  };

  // Framework errors (widget build/layout/paint exceptions).
  FlutterError.onError = (details) {
    AppLogger.instance.error(
      'flutter',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
    CrashStore.instance
        .record('flutter', details.exception, details.stack ?? StackTrace.empty);
  };

  // Unhandled errors escaping async futures (platform dispatcher level).
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.instance.error('platform', 'unhandled platform error', error, stack);
    CrashStore.instance.record('platform', error, stack);
    return true; // handled: keep the app alive, never kill the process.
  };

  await runZonedGuarded<Future<void>>(
    () async {
      // Boot UI is shown immediately; services initialize inside the
      // widget tree with visible stages, retry and safe-mode fallback.
      runApp(const DrsApp());
    },
    (error, stack) {
      AppLogger.instance.error('crash', 'uncaught zone error', error, stack);
      CrashStore.instance.record('crash', error, stack);
      if (kDebugMode) debugPrint('$error\n$stack');
    },
  );
}

/// Replaces the default grey error screen: quiet, branded, bilingual
/// (no localization dependency — may render before MaterialApp exists).
class _FriendlyErrorView extends StatelessWidget {
  const _FriendlyErrorView({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF14182A),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFFFFB4AB)),
              const SizedBox(height: 12),
              const Text(
                'حدث خطأ غير متوقع\nAn unexpected error occurred',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white, fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 10),
              Text(
                'أغلق الشاشة وحاول مرة أخرى — إذا تكرر الأمر، انسخ التفاصيل من: الإعدادات ← التشخيص والأخطاء\n'
                'Close this screen and try again — if it repeats, copy the details from: Settings ← Diagnostics & errors',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.75), fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 12),
              Text(
                details.exceptionAsString(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
