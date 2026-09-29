import '../../data/models/media_item.dart';

/// Deterministic CSV export of the whole watch inventory + progress.
///
/// One row per library item, progress columns blank when the item was
/// never played. Built as a pure function so it is fully unit-testable;
/// the UI only writes the returned string to a file and shares it.
class AnalyticsExport {
  AnalyticsExport._();

  /// RFC-4180 field escaping: quotes doubled, field wrapped when it
  /// contains separator/quote/newline.
  static String csvEscape(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static const List<String> header = [
    'title',
    'uri',
    'type',
    'duration_ms',
    'size_bytes',
    'width',
    'height',
    'play_count',
    'is_favorite',
    'added_at',
    'last_played_at',
    'position_ms',
    'completed',
    'progress_updated_at',
  ];

  /// Builds the full CSV (header + one row per item). Rows are ordered as
  /// the input list (callers pass a sorted query result).
  static String buildHistoryCsv(
    List<MediaItem> items,
    Map<String, WatchProgress> progressByItemId,
  ) {
    final buf = StringBuffer();
    buf.writeln(header.join(','));
    for (final m in items) {
      final w = progressByItemId[m.id];
      buf.writeln([
        csvEscape(m.title),
        csvEscape(m.uri),
        csvEscape(m.type.name),
        m.durationMs ?? '',
        m.sizeBytes ?? '',
        m.width ?? '',
        m.height ?? '',
        m.playCount,
        m.isFavorite ? 1 : 0,
        m.addedAt.millisecondsSinceEpoch,
        m.lastPlayedAt?.millisecondsSinceEpoch ?? '',
        w?.positionMs ?? '',
        w == null ? '' : (w.completed ? 1 : 0),
        w?.updatedAt.millisecondsSinceEpoch ?? '',
      ].join(','));
    }
    return buf.toString();
  }
}
