import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:drs_video/services/smart/intel_v4.dart';
import 'package:drs_video/services/smart/image_render.dart';

/// v1.14.0 — downloads studio + media studios + add-download sheet:
/// pure algorithm pack (intel_v4) and the image render pipeline.
void main() {
  group('DownloadClassifier', () {
    test('classifies by content-type first (authoritative over extension)',
        () {
      expect(
        DownloadClassifier.classify(
            url: 'https://x.com/file.jpg', contentType: 'video/mp4'),
        DownloadKind.video,
      );
      expect(
        DownloadClassifier.classify(
            url: 'https://x.com/movie.mp4', contentType: 'audio/mpeg'),
        DownloadKind.audio,
      );
    });

    test('falls back to URL extension', () {
      expect(DownloadClassifier.classify(url: 'https://x.com/a.mkv?v=1'),
          DownloadKind.video);
      expect(DownloadClassifier.classify(url: 'https://x.com/a.mp3'),
          DownloadKind.audio);
      expect(DownloadClassifier.classify(url: 'https://x.com/a.png'),
          DownloadKind.image);
      expect(DownloadClassifier.classify(url: 'https://x.com/a.apk'),
          DownloadKind.app);
      expect(DownloadClassifier.classify(url: 'https://x.com/a.srt'),
          DownloadKind.document);
      expect(DownloadClassifier.classify(url: 'https://x.com/a.zip'),
          DownloadKind.archive);
    });

    test('unknowns are other — never a wrong promise', () {
      expect(DownloadClassifier.classify(url: 'https://x.com/'),
          DownloadKind.other);
      expect(DownloadClassifier.classify(url: 'https://x.com/noext'),
          DownloadKind.other);
      expect(
        DownloadClassifier.classify(
            url: 'https://x.com/a.cgi', contentType: 'application/octet-stream'),
        DownloadKind.other,
      );
    });

    test('extensionOf ignores query/fragment and long junk', () {
      expect(DownloadClassifier.extensionOf('https://x.com/v.mp4?token=1'),
          'mp4');
      expect(DownloadClassifier.extensionOf('https://x.com/a.b.c/'), '');
      expect(DownloadClassifier.extensionOf('https://x.com/f.1234567'), '');
    });

    test('extensionFor: url ext wins, mime fallback, bin last resort', () {
      expect(
        DownloadClassifier.extensionFor(url: 'https://x.com/a.webm'),
        'webm',
      );
      expect(
        DownloadClassifier.extensionFor(
            url: 'https://x.com/get?id=1', contentType: 'image/jpeg'),
        'jpg',
      );
      expect(DownloadClassifier.extensionFor(url: 'https://x.com/get?id=1'),
          'bin');
    });
  });

  group('ClipboardLinkGate (auto-paste)', () {
    test('accepts plain http/https links', () {
      expect(
        ClipboardLinkGate.decide('https://example.com/video.mp4'),
        ClipboardDecision.accept,
      );
      expect(
        ClipboardLinkGate.decide('  http://example.com/a.png  \n'),
        ClipboardDecision.accept, // trims
      );
    });

    test('rejects non-URL junk and hostile shapes', () {
      expect(ClipboardLinkGate.decide(null), ClipboardDecision.invalid);
      expect(ClipboardLinkGate.decide(''), ClipboardDecision.invalid);
      expect(
          ClipboardLinkGate.decide('hello world'), ClipboardDecision.invalid);
      expect(ClipboardLinkGate.decide('ftp://x.com/a'),
          ClipboardDecision.invalid);
      expect(ClipboardLinkGate.decide('https://'), ClipboardDecision.invalid);
      expect(ClipboardLinkGate.decide('a' * 3000), ClipboardDecision.invalid);
    });

    test('dedup: same link as last accepted or already in field', () {
      const url = 'https://example.com/v.mp4';
      expect(
        ClipboardLinkGate.decide(url, lastAccepted: url),
        ClipboardDecision.duplicate,
      );
      expect(
        ClipboardLinkGate.decide(url, alreadyInField: url),
        ClipboardDecision.duplicate,
      );
      expect(
        ClipboardLinkGate.decide(url, alreadyInField: '  $url '),
        ClipboardDecision.duplicate,
      );
    });

    test('a fresh link after a duplicate is accepted again', () {
      expect(
        ClipboardLinkGate.decide('https://other.com/b.mp4',
            lastAccepted: 'https://example.com/v.mp4'),
        ClipboardDecision.accept,
      );
    });
  });

  group('FileNameSuggester', () {
    test('Content-Disposition wins over URL basename', () {
      final name = FileNameSuggester.suggest(
        url: 'https://x.com/download?id=42',
        contentType: 'video/mp4',
        disposition: 'attachment; filename="My Clip.mp4"',
      );
      expect(name, 'My Clip.mp4');
    });

    test('URL basename used when no disposition', () {
      expect(
        FileNameSuggester.suggest(url: 'https://x.com/episodes/s01e05.mkv'),
        's01e05.mkv',
      );
    });

    test('mime corrects a lying extension', () {
      final name = FileNameSuggester.suggest(
        url: 'https://x.com/photo.dat',
        contentType: 'image/png',
      );
      expect(name, 'photo.png');
    });

    test('fallback title when URL has no name', () {
      expect(
        FileNameSuggester.suggest(url: 'https://x.com/', fallback: 'ملف'),
        'ملف',
      );
    });

    test('sanitize keeps Arabic + spaces, strips traversal/hostile chars', () {
      expect(FileNameSuggester.sanitize('../../etc/passwd'),
          '.. .. etc passwd');
      // Each hostile char becomes a space, then runs collapse.
      expect(FileNameSuggester.sanitize('a<b>:c"d'), 'a b c d');
      final ar = FileNameSuggester.sanitize('  فيلم   رائع.mp4 ');
      expect(ar, 'فيلم رائع.mp4');
    });
  });

  group('MediaCataloguer', () {
    test('buckets by extension', () {
      expect(MediaCataloguer.of('/a/x.mp4'), MediaBucket.video);
      expect(MediaCataloguer.of('/a/x.MKV'), MediaBucket.video);
      expect(MediaCataloguer.of('/a/x.mp3'), MediaBucket.audio);
      expect(MediaCataloguer.of('/a/x.JPG'), MediaBucket.image);
      expect(MediaCataloguer.of('/a/x.txt'), MediaBucket.other);
      expect(MediaCataloguer.of('noext'), MediaBucket.other);
    });

    test('bucket() groups and sorts newest-first deterministically', () {
      final t0 = DateTime(2024, 1, 1);
      final files = [
        StudioFile(
            path: '/a/old.mp4',
            name: 'old.mp4',
            sizeBytes: 1,
            modified: t0),
        StudioFile(
            path: '/a/new.mp4',
            name: 'new.mp4',
            sizeBytes: 2,
            modified: t0.add(const Duration(days: 1))),
        StudioFile(
            path: '/a/song.mp3',
            name: 'song.mp3',
            sizeBytes: 3,
            modified: t0),
        StudioFile(
            path: '/a/pic.jpg',
            name: 'pic.jpg',
            sizeBytes: 4,
            modified: t0),
      ];
      final buckets = MediaCataloguer.bucket(files);
      expect(buckets[MediaBucket.video]!.length, 2);
      expect(buckets[MediaBucket.video]!.first.name, 'new.mp4');
      expect(buckets[MediaBucket.audio]!.length, 1);
      expect(buckets[MediaBucket.image]!.length, 1);
      expect(buckets[MediaBucket.other], isEmpty);
    });
  });

  group('ImageAdjustments LUT', () {
    test('neutral params give an identity table', () {
      final lut = ImageAdjustments.lut(const ImageAdjustments());
      for (int i = 0; i < 256; i++) {
        expect(lut[i], i, reason: 'identity violated at $i');
      }
    });

    test('brightness shifts and clamps at both ends', () {
      final lut = ImageAdjustments.lut(const ImageAdjustments(brightness: 50));
      expect(lut[0], 50);
      expect(lut[205], 255);
      expect(lut[255], 255);
      final dark = ImageAdjustments.lut(const ImageAdjustments(brightness: -50));
      expect(dark[0], 0);
      expect(dark[60], 10);
    });

    test('contrast scales around the midpoint', () {
      final lut = ImageAdjustments.lut(const ImageAdjustments(contrast: 2.0));
      // (127-127.5)*2+127.5 = 126.5 → rounds to 127.
      expect(lut[127], 127);
      expect(lut[0], 0);
      expect(lut[255], 255);
    });

    test('gamma keeps monotonic non-decreasing table', () {
      for (final g in [0.1, 0.5, 2.0, 3.0]) {
        final lut = ImageAdjustments.lut(ImageAdjustments(gamma: g));
        for (int i = 1; i < 256; i++) {
          expect(lut[i] >= lut[i - 1], isTrue,
              reason: 'gamma $g not monotonic at $i');
        }
      }
    });

    test('invert flips and composes', () {
      final lut = ImageAdjustments.lut(const ImageAdjustments(invert: true));
      expect(lut[0], 255);
      expect(lut[255], 0);
      // brightness +255 then invert: 0 → 255 → inverted → 0.
      final both =
          ImageAdjustments.lut(const ImageAdjustments(brightness: 255, invert: true));
      expect(both[0], 0);
      expect(both[255], 0); // 255+255 clamps to 255 → invert → 0
    });

    test('luma uses BT.601 weights', () {
      expect(ImageAdjustments.luma(255, 255, 255).round(), 255);
      expect(ImageAdjustments.luma(0, 0, 0), 0);
      final y = ImageAdjustments.luma(255, 0, 0);
      expect(y > 70 && y < 80, isTrue); // 76.245
    });
  });

  group('OrientationMatrix', () {
    test('identity maps every pixel to itself', () {
      const m = OrientationMatrix();
      expect(m.isIdentity, isTrue);
      final (w, h) = m.outputSize(4, 3);
      expect((w, h), (4, 3));
      expect(m.sourceOf(2, 1, 4, 3), (2, 1));
    });

    test('90° CW swaps axes and samples the right source pixels', () {
      // Source 4x3 (labels):      CW90 output 3x4:
      //   A B C D                   I E A
      //   E F G H                   J F B
      //   I J K L                   K G C
      //                             L H D
      const m = OrientationMatrix(quarterTurns: 1);
      final (w, h) = m.outputSize(4, 3);
      expect((w, h), (3, 4));
      expect(m.sourceOf(0, 0, 4, 3), (0, 2)); // I
      expect(m.sourceOf(2, 0, 4, 3), (0, 0)); // A
      expect(m.sourceOf(0, 3, 4, 3), (3, 2)); // L
      expect(m.sourceOf(2, 3, 4, 3), (3, 0)); // D
    });

    test('180° mirrors both axes', () {
      const m = OrientationMatrix(quarterTurns: 2);
      expect(m.sourceOf(0, 0, 4, 3), (3, 2));
      expect(m.sourceOf(3, 2, 4, 3), (0, 0));
    });

    test('270° samples the CCW-rotated grid correctly', () {
      // Source 4x3:               CW270 output 3x4:
      //   A B C D                   D H L
      //   E F G H                   C G K
      //   I J K L                   B F J
      //                             A E I
      const m = OrientationMatrix(quarterTurns: 3);
      expect(m.outputSize(4, 3), (3, 4));
      expect(m.sourceOf(0, 0, 4, 3), (3, 0)); // D
      expect(m.sourceOf(2, 3, 4, 3), (0, 2)); // I
      expect(m.sourceOf(0, 3, 4, 3), (0, 0)); // A
    });

    test('flips mirror single axis (no rotation)', () {
      const h = OrientationMatrix(flip: FlipMode.horizontal);
      expect(h.sourceOf(0, 1, 4, 3), (3, 1));
      expect(h.sourceOf(3, 1, 4, 3), (0, 1));
      const v = OrientationMatrix(flip: FlipMode.vertical);
      expect(v.sourceOf(1, 0, 4, 3), (1, 2));
    });

    test('flip after odd rotation undoes in OUTPUT space', () {
      // Source 2x1 [A B]. CW90 → column [A; B]. flipH on 1-wide output is a
      // no-op, so output(0,0) is still A → source (0,0).
      const m = OrientationMatrix(quarterTurns: 1, flip: FlipMode.horizontal);
      expect(m.sourceOf(0, 0, 2, 1), (0, 0));
      expect(m.sourceOf(0, 1, 2, 1), (1, 0));

      // Source 2x2: a b / c d. CW90 → c a / d b. flipH → a c / b d.
      // output(0,0)=a → source (0,0); output(1,0)=c → source (0,1).
      const m2 = OrientationMatrix(quarterTurns: 1, flip: FlipMode.horizontal);
      expect(m2.sourceOf(0, 0, 2, 2), (0, 0));
      expect(m2.sourceOf(1, 0, 2, 2), (0, 1));
      expect(m2.sourceOf(0, 1, 2, 2), (1, 0));
      expect(m2.sourceOf(1, 1, 2, 2), (1, 1));
    });

    test('quarterTurns wrap modulo 4', () {
      final m = const OrientationMatrix(quarterTurns: 3).rotate90();
      expect(m.isIdentity, isTrue);
    });
  });

  group('ProbeSummary.fromResponse (العرض)', () {
    test('parses a healthy 200 with size + ranges + mime', () {
      final s = ProbeSummary.fromResponse(
        status: 200,
        url: 'https://cdn.x.com/podcast/ep1.mp3',
        headers: {
          'content-type': ['audio/mpeg'],
          'content-length': ['1048576'],
          'accept-ranges': ['bytes'],
        },
      );
      expect(s.kind, DownloadKind.audio);
      expect(s.sizeBytes, 1048576);
      expect(s.resumable, isTrue);
      expect(s.contentType, 'audio/mpeg');
      expect(s.fileName, 'ep1.mp3');
    });

    test('uses Content-Disposition filename and corrects extension', () {
      final s = ProbeSummary.fromResponse(
        status: 200,
        url: 'https://x.com/get?id=9',
        headers: {
          'content-type': ['image/jpeg'],
          'content-disposition': ['attachment; filename="غروب.jpg"'],
        },
      );
      expect(s.kind, DownloadKind.image);
      expect(s.fileName, 'غروب.jpg');
      expect(s.sizeBytes, -1); // unknown size stays honest
      expect(s.resumable, isFalse);
    });

    test('non-2xx throws an honest FormatException', () {
      expect(
        () => ProbeSummary.fromResponse(
            status: 404, url: 'https://x.com/a.mp4', headers: {}),
        throwsFormatException,
      );
      expect(
        () => ProbeSummary.fromResponse(
            status: 403, url: 'https://x.com/a.mp4', headers: {}),
        throwsFormatException,
      );
    });
  });

  group('renderImage pipeline (image_render)', () {
    // 2x2 red image as PNG bytes.
    Uint8List redPng() {
      final image = img.Image(width: 2, height: 2);
      for (final p in image) {
        p.r = 255;
        p.g = 0;
        p.b = 0;
        p.a = 255;
      }
      return Uint8List.fromList(img.encodePng(image));
    }

    test('neutral params decode → encode losslessly readable', () {
      final out = renderImage(redPng(), const EditParams());
      final decoded = img.decodePng(out)!;
      expect(decoded.width, 2);
      expect(decoded.height, 2);
      expect(decoded.getPixel(0, 0).r, 255);
      expect(decoded.getPixel(0, 0).g, 0);
    });

    test('grayscale turns red into BT.601 luma gray', () {
      final out = renderImage(
          redPng(), const EditParams(grayscale: true));
      final decoded = img.decodePng(out)!;
      final px = decoded.getPixel(0, 0);
      final expected = (0.299 * 255).round(); // 76
      expect((px.r - expected).abs() <= 1, isTrue, reason: 'r=${px.r}');
      expect(px.r, px.g);
      expect(px.g, px.b);
    });

    test('rotate 90 swaps dimensions', () {
      // 2x3 source.
      final src = img.Image(width: 2, height: 3);
      for (final p in src) {
        p.r = 10;
        p.g = 200;
        p.b = 30;
        p.a = 255;
      }
      final bytes = Uint8List.fromList(img.encodePng(src));
      final out = renderImage(bytes, const EditParams(quarterTurns: 1));
      final decoded = img.decodePng(out)!;
      expect(decoded.width, 3);
      expect(decoded.height, 2);
    });

    test('invert flips channels', () {
      final out =
          renderImage(redPng(), const EditParams(invert: true));
      final decoded = img.decodePng(out)!;
      final px = decoded.getPixel(0, 0);
      expect(px.r, 0);
      expect(px.g, 255);
      expect(px.b, 255);
    });

    test('maxEdge downscales the long side for previews', () {
      final src = img.Image(width: 100, height: 50);
      for (final p in src) {
        p.r = 100;
        p.g = 100;
        p.b = 100;
        p.a = 255;
      }
      final bytes = Uint8List.fromList(img.encodePng(src));
      final out = renderImage(bytes, const EditParams(), maxEdge: 10);
      final decoded = img.decodePng(out)!;
      expect(decoded.width, 10);
      expect(decoded.height, 5);
    });

    test('garbage bytes never produce a silent success', () {
      // Truncated PNG signature: the decoder accepts the magic but the IHDR
      // is missing, so decoding fails — our pipeline MUST surface that
      // (FormatException from a null decode, or the decoder's own error).
      expect(
        () => renderImage(
            Uint8List.fromList(
                [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]),
            const EditParams()),
        throwsA(anything),
      );
    });
  });
}
