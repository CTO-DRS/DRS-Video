import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/core/utils/validators.dart';

void main() {
  group('isValidVideoUrl', () {
    test('accepts standard https video urls', () {
      expect(Validators.isValidVideoUrl('https://example.com/video.mp4'), isTrue);
      expect(
          Validators.isValidVideoUrl('https://cdn.example.org:8443/path/file.m3u8?token=abc'),
          isTrue);
    });

    test('rejects non-http schemes', () {
      expect(Validators.isValidVideoUrl('ftp://example.com/a.mp4'), isFalse);
      expect(Validators.isValidVideoUrl('file:///sdcard/a.mp4'), isFalse);
      expect(Validators.isValidVideoUrl('javascript:alert(1)'), isFalse);
    });

    test('rejects localhost and private IPs', () {
      expect(Validators.isValidVideoUrl('http://localhost/a.mp4'), isFalse);
      expect(Validators.isValidVideoUrl('http://192.168.1.5/a.mp4'), isFalse);
      expect(Validators.isValidVideoUrl('http://10.0.0.1/a.mp4'), isFalse);
    });

    test('rejects credentials and malformed input', () {
      expect(Validators.isValidVideoUrl('http://user:pass@example.com/a.mp4'), isFalse);
      expect(Validators.isValidVideoUrl('not a url'), isFalse);
      expect(Validators.isValidVideoUrl(''), isFalse);
    });
  });

  group('sanitizeFileName', () {
    test('strips path separators and illegal characters', () {
      expect(Validators.sanitizeFileName('a/b\\c:d*e?f"g<h>i|j'),
          'a_b_c_d_e_f_g_h_i_j');
    });

    test('blocks path traversal', () {
      final result = Validators.sanitizeFileName('../../etc/passwd');
      expect(result.contains('..'), isFalse);
    });

    test('falls back when empty and clamps length', () {
      expect(Validators.sanitizeFileName(''), 'video');
      final long = Validators.sanitizeFileName('x' * 300);
      expect(long.length, lessThanOrEqualTo(120));
    });
  });

  group('extension helpers', () {
    test('extensionOf handles urls with query strings', () {
      expect(Validators.extensionOf('https://a.com/v.mp4?sig=1'), 'mp4');
      expect(Validators.extensionOf('https://a.com/manifest.m3u8'), 'm3u8');
      expect(Validators.extensionOf('https://a.com/noext'), '');
    });

    test('video and subtitle detection', () {
      expect(Validators.isVideoFile('/a/b.MKV'), isTrue);
      expect(Validators.isVideoFile('/a/b.srt'), isFalse);
      expect(Validators.isSubtitleFile('/a/b.vtt'), isTrue);
    });

    test('titleFromUrl decodes and cleans', () {
      expect(Validators.titleFromUrl('https://a.com/videos/My_Cool%20Video.mp4'),
          'My Cool Video');
      expect(Validators.titleFromUrl('https://a.com/'), 'a.com');
    });
  });
}
