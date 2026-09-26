/// Parses SRT / VTT subtitle files into cues. Used to validate external
/// subtitle files (so users get real feedback) and to expose cue counts.
class SubtitleParser {
  SubtitleParser._();

  static final RegExp _timeSrt = RegExp(
    r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})',
  );
  static final RegExp _timeVtt = RegExp(
    r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[.,](\d{1,3})\s*-->\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[.,](\d{1,3})',
  );

  /// Returns cues, or throws [FormatException] on invalid content.
  static List<SubtitleCue> parse(String content) {
    final cues = <SubtitleCue>[];
    if (content.trim().isEmpty) throw const FormatException('empty subtitle');

    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n{2,}'));

    for (final block in blocks) {
      final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final timeLineIdx = lines.indexWhere((l) => l.contains('-->'));
      if (timeLineIdx < 0 || timeLineIdx + 1 >= lines.length) continue;

      final timings = _parseTimings(lines[timeLineIdx]);
      if (timings == null) continue;
      final text = lines.sublist(timeLineIdx + 1).join('\n').trim();
      if (text.isEmpty) continue;
      cues.add(SubtitleCue(startMs: timings.$1, endMs: timings.$2, text: text));
    }
    if (cues.isEmpty) throw const FormatException('no cues found');
    return cues;
  }

  static (int, int)? _parseTimings(String line) {
    final m = _timeSrt.firstMatch(line) ?? _timeVtt.firstMatch(line);
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i) ?? '0');

    if (m.pattern == _timeSrt) {
      // h m s ms -> h m s ms
      final start = _toMs(g(1), g(2), g(3), g(4));
      final end = _toMs(g(5), g(6), g(7), g(8));
      return (start, end);
    }
    // VTT: hours optional
    final start = _toMs(m.group(1) == null ? 0 : g(1), g(2), g(3), g(4));
    final end = _toMs(m.group(5) == null ? 0 : g(5), g(6), g(7), g(8));
    return (start, end);
  }

  static int _toMs(int h, int m, int s, int ms) => ((h * 3600 + m * 60 + s) * 1000) + ms;
}

class SubtitleCue {
  const SubtitleCue({required this.startMs, required this.endMs, required this.text});

  final int startMs;
  final int endMs;
  final String text;
}
