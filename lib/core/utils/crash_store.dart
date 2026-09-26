import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent crash log (survives process death).
///
/// Every unhandled Dart error is appended here, so if the app ever dies
/// hard, the NEXT launch can show the user (and us) the actual reason —
/// no adb required. The file is cleared automatically once a boot fully
/// succeeds, so it always describes the most recent broken session.
class CrashStore {
  CrashStore._();
  static final CrashStore instance = CrashStore._();

  static const String fileName = 'drs_last_crash.txt';
  static const int _maxBytes = 64 * 1024;

  Future<Directory?>? _supportDir;
  Future<void>? _pending;
  bool _disabled = false;

  Future<Directory?> _dir() {
    if (_disabled) return Future.value(null);
    return _supportDir ??= getApplicationSupportDirectory().catchError((_) {
      // No platform/channel available (tests, early failures) — give up
      // quietly; crash persistence is best-effort by design.
      _disabled = true;
      return Directory.systemTemp;
    });
  }

  File _fileFor(Directory base) => File('${base.path}/$fileName');

  /// Appends one crash/error record. Re-entrant safe: writes are chained.
  void record(String tag, Object? error, [StackTrace? stack]) {
    try {
      final entry = StringBuffer()
        ..writeln('--- ${DateTime.now().toIso8601String()} [$tag] ---')
        ..writeln('$error')
        ..writeln(stack?.toString().split('\n').take(40).join('\n') ?? '');

      _pending = (_pending ?? Future<void>.value()).then((_) async {
        final base = await _dir();
        if (base == null) return;
        final f = _fileFor(base);
        var content = '';
        if (await f.exists()) {
          content = await f.readAsString();
        }
        var next = content.length > _maxBytes ? '' : content; // rotate
        await f.writeAsString('$next$entry', flush: true);
      }).catchError((_) {});
    } catch (_) {
      // Never let diagnostics kill the app.
    }
  }

  /// Previous session's crash records, or null when the last session was
  /// clean (file absent/empty — it is cleared on every successful boot).
  Future<String?> readPrevious() async {
    try {
      final base = await _dir();
      if (base == null) return null;
      final f = _fileFor(base);
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// Called after a boot fully succeeded: the session is healthy, so the
  /// old records are no longer relevant.
  Future<void> clear() async {
    try {
      final base = await _dir();
      if (base == null) return;
      final f = _fileFor(base);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
