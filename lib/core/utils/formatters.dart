/// Pure formatting helpers used across the app.
library;

class Formatters {
  Formatters._();

  /// Formats bytes into a human readable size, e.g. 1.4 GB.
  static String bytes(num bytes, {int decimals = 1}) {
    if (bytes < 0) return '-';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final d = value >= 100 || unit == 0 ? 0 : decimals;
    return '${value.toStringAsFixed(d)} ${units[unit]}';
  }

  /// Formats a speed in bytes/second, e.g. 2.3 MB/s.
  static String speed(num bytesPerSecond) =>
      bytesPerSecond <= 0 ? '-' : '${bytes(bytesPerSecond)}/s';

  /// Formats milliseconds as h:mm:ss or m:ss.
  static String duration(int ms) {
    if (ms < 0) ms = 0;
    final totalSeconds = ms ~/ 1000;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  /// Formats remaining time given remaining bytes and speed.
  static String eta(int remainingBytes, num bytesPerSecond) {
    if (bytesPerSecond <= 0) return '-';
    final seconds = (remainingBytes / bytesPerSecond).round();
    if (seconds > 3600 * 24) return '-';
    return duration(seconds * 1000);
  }

  /// Formats a percentage 0-100, clamped.
  static String percent(num pct) =>
      '${pct.clamp(0, 100).toStringAsFixed(pct % 1 == 0 ? 0 : 1)}%';

  /// Short date: yyyy-mm-dd hh:mm (locale-neutral, deterministic).
  static String dateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $hh:$mi';
  }

  /// Day bucket (midnight epoch ms) used for grouping history.
  static int dayBucket(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
}
