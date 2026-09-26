import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/services/player/subtitle_parser.dart';

void main() {
  group('SubtitleParser (SRT)', () {
    test('parses valid SRT with multiple cues', () {
      const srt = '''
1
00:00:01,000 --> 00:00:03,500
Hello world

2
00:00:04,000 --> 00:00:06,000
Second line
continues here
''';
      final cues = SubtitleParser.parse(srt);
      expect(cues.length, 2);
      expect(cues[0].startMs, 1000);
      expect(cues[0].endMs, 3500);
      expect(cues[0].text, 'Hello world');
      expect(cues[1].text, 'Second line\ncontinues here');
    });

    test('parses VTT with optional hours', () {
      const vtt = '''
WEBVTT

00:05.000 --> 00:08.000
No hours here

01:02:03.000 --> 01:02:04.500
With hours
''';
      final cues = SubtitleParser.parse(vtt);
      expect(cues.length, 2);
      expect(cues[0].startMs, 5000);
      expect(cues[1].startMs, 3723000);
    });

    test('throws on empty content', () {
      expect(() => SubtitleParser.parse('   '), throwsFormatException);
    });

    test('throws when no cues found', () {
      expect(() => SubtitleParser.parse('random text no timings'),
          throwsFormatException);
    });
  });
}
