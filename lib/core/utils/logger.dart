/// Lightweight in-memory logger (ring buffer) for diagnostics.
///
/// Logs stay on-device and can be exported by the user from Settings > Privacy.
library;

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  const LogEntry(this.time, this.level, this.tag, this.message);

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  String format() {
    final l = switch (level) {
      LogLevel.debug => 'D',
      LogLevel.info => 'I',
      LogLevel.warning => 'W',
      LogLevel.error => 'E',
    };
    return '${time.toIso8601String()} $l/$tag: $message';
  }
}

class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _maxEntries = 600;
  final List<LogEntry> _entries = <LogEntry>[];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void debug(String tag, String message) => _add(LogLevel.debug, tag, message);
  void info(String tag, String message) => _add(LogLevel.info, tag, message);
  void warning(String tag, String message) => _add(LogLevel.warning, tag, message);
  void error(String tag, String message, [Object? error, StackTrace? stack]) {
    var m = message;
    if (error != null) m = '$message | $error';
    if (stack != null && kDebugMode) m = '$m\n$stack';
    _add(LogLevel.error, tag, m);
  }

  void _add(LogLevel level, String tag, String message) {
    _entries.add(LogEntry(DateTime.now(), level, tag, message));
    if (_entries.length > _maxEntries) _entries.removeRange(0, _entries.length - _maxEntries);
    if (kDebugMode) debugPrint('[$tag] $message');
  }

  String export() => _entries.map((e) => e.format()).join('\n');

  void clear() => _entries.clear();
}
