/// v1.13.0 smart-intel algorithms — subtitle translation math, gesture
/// state machines and picture-calibration helpers. Every function here is
/// pure and unit-tested; no I/O, no Flutter imports. IO/network glue lives
/// in the services that consume these helpers.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../../core/utils/md5.dart';

// ---------------------------------------------------------------------------
// Translation batching — the free Google translate endpoint (client=gtx)
// accepts one q= parameter per request. To translate a full SRT with few
// round-trips we join cue texts with '\n' (internal newlines flattened to
// spaces first so the separator is unambiguous) and never exceed a char
// budget per request. Order is preserved: batch i covers cues
// [startCue, startCue + count).
// ---------------------------------------------------------------------------

class TranslationBatch {
  const TranslationBatch({required this.startCue, required this.lines});

  /// Index of the first cue covered by this batch.
  final int startCue;

  /// Cue texts (one entry per cue, in order). Internal newlines already
  /// flattened by the batcher.
  final List<String> lines;

  /// The wire payload: lines joined with '\n'.
  String get payload => lines.join('\n');
}

class TranslationBatcher {
  TranslationBatcher._();

  /// Keep comfortably under the ~5000-char server limit even after URL
  /// encoding expansion.
  static const int defaultCharBudget = 1400;

  /// Splits [texts] into ordered batches. A single line longer than the
  /// budget becomes its own batch (the server accepts long q; the budget
  /// only stops us from stacking many lines together).
  static List<TranslationBatch> batch(
    List<String> texts, {
    int charBudget = defaultCharBudget,
  }) {
    if (charBudget < 100) charBudget = 100;
    final batches = <TranslationBatch>[];
    var current = <String>[];
    var currentChars = 0;
    var startCue = 0;

    void flush() {
      if (current.isEmpty) return;
      batches.add(TranslationBatch(startCue: startCue, lines: List.of(current)));
      startCue += current.length;
      current = <String>[];
      currentChars = 0;
    }

    for (final raw in texts) {
      final line = flattenLine(raw);
      final lineCost = line.length + 1; // + '\n' separator
      if (current.isNotEmpty && currentChars + lineCost > charBudget) {
        flush();
      }
      current.add(line);
      currentChars += lineCost;
    }
    flush();
    return batches;
  }

  /// Newlines inside a single cue would corrupt the '\n' mapping contract;
  /// collapse every whitespace run (incl. \r\n) to one space.
  static String flattenLine(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ---------------------------------------------------------------------------
// gtx response parsing — the endpoint returns
// `[[["مرحبا","hello",null,null,10],...],null,"en",...]` where resp[0] is
// the list of translated chunks and resp[2] the detected source language.
// ---------------------------------------------------------------------------

class GtxResponse {
  const GtxResponse({required this.text, required this.detectedSource});

  final String text;
  final String detectedSource;

  /// Throws [FormatException] on any structure we do not fully understand —
  /// the caller then falls back to the per-line strategy instead of
  /// writing garbage into the subtitle.
  static GtxResponse parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List || decoded.isEmpty) {
      throw const FormatException('gtx: root is not a list');
    }
    final chunks = decoded[0];
    if (chunks is! List || chunks.isEmpty) {
      throw const FormatException('gtx: no chunks');
    }
    final buf = StringBuffer();
    for (final chunk in chunks) {
      if (chunk is! List || chunk.isEmpty) continue;
      final piece = chunk[0];
      if (piece is String) buf.write(piece);
    }
    var source = '';
    if (decoded.length > 2 && decoded[2] is String) source = decoded[2] as String;
    return GtxResponse(text: buf.toString(), detectedSource: source);
  }

  /// Translated lines that map 1:1 onto [expected] — null on a count
  /// mismatch, which triggers the per-line fallback instead of the classic
  /// "every subtitle shows the wrong text" bug.
  static List<String>? mapLines(String translated, int expected) {
    final lines = translated.split('\n');
    if (lines.length != expected) return null;
    return lines;
  }
}

// ---------------------------------------------------------------------------
// Translation cache keys — deterministic md5 of (text, target, source mode)
// so the same subtitle never translates twice (reuse of the RFC-1321 MD5
// implementation shipped for the updater).
// ---------------------------------------------------------------------------

class TranslationCacheKeys {
  TranslationCacheKeys._();

  static String fileKey(String srtText, String targetLang) =>
      'tr_${md5Hex(utf8.encode('v1|$targetLang|$srtText'))}.srt';

  static String batchKey(String payload, String targetLang) =>
      'v1|$targetLang|${md5Hex(utf8.encode(payload))}';
}

// ---------------------------------------------------------------------------
// SRT text operations — rewrite only the text lines of an SRT, keeping the
// numbering and timing lines byte-identical (players are picky about
// timing formatting, and re-serializing risks drift).
// ---------------------------------------------------------------------------

class SrtTextOps {
  SrtTextOps._();

  static final RegExp _timing = RegExp(
      r'^\s*\d{1,3}:\d{2}:\d{2}[,.]\d{3}\s*-->\s*\d{1,3}:\d{2}:\d{2}[,.]\d{3}');

  /// Splits an SRT into blocks of consecutive non-empty lines and returns,
  /// per block, the indexes of its text lines (index 0 = cue number,
  /// index 1 = timing, 2+ = text).
  static List<List<String>> textLinesOf(String srt) {
    final out = <List<String>>[];
    final lines = srt.split('\n');
    var block = <String>[];
    for (final line in lines) {
      final t = line.trimRight();
      if (t.trim().isEmpty) {
        if (block.isNotEmpty) {
          out.add(_textIndexes(block));
          block = <String>[];
        }
      } else {
        block.add(t);
      }
    }
    if (block.isNotEmpty) out.add(_textIndexes(block));
    return out;
  }

  /// Returns the text lines (everything after the timing line) of a block.
  static List<String> _textIndexes(List<String> block) {
    final start = block.length >= 2 && _timing.hasMatch(block[1]) ? 2 : 1;
    return block.sublist(start.clamp(0, block.length));
  }

  /// Extracts cue texts in order (one flattened line per block that has
  /// text). Blocks without text lines are skipped entirely so the
  /// translation result maps back 1:1.
  static List<String> textsForTranslation(String srt) {
    final texts = <String>[];
    for (final textLines in textLinesOf(srt)) {
      if (textLines.isEmpty) continue;
      texts.add(TranslationBatcher.flattenLine(textLines.join(' ')));
    }
    return texts;
  }

  /// Rebuilds the SRT replacing the text lines of the n-th text-bearing
  /// block with [translated[n]]. Ordering and timing untouched.
  static String rebuild(String srt, List<String> translated) {
    final lines = srt.split('\n');
    final blocks = <List<int>>[]; // [start, end) line ranges of blocks
    var start = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) {
        if (i > start) blocks.add([start, i]);
        start = i + 1;
      }
    }
    if (start < lines.length) blocks.add([start, lines.length]);

    final out = List<String>.of(lines);
    var t = 0;
    for (final range in blocks) {
      if (t >= translated.length) break;
      final block = lines.sublist(range[0], range[1]);
      if (block.isEmpty) continue;
      final textStart =
          block.length >= 2 && _timing.hasMatch(block[1]) ? 2 : 1;
      var hasText = false;
      for (var k = textStart; k < block.length; k++) {
        if (block[k].trim().isNotEmpty) hasText = true;
      }
      if (!hasText) continue;
      // Replace the whole text span with the translated single line.
      out[range[0] + textStart] = translated[t];
      for (var k = range[0] + textStart + 1; k < range[1]; k++) {
        out[k] = ''; // drop extra text lines of the block
      }
      t++;
    }
    return out.join('\n');
  }
}

// ---------------------------------------------------------------------------
// Zoom & pan math for the pinch gesture — mpv video-zoom is a log scale
// (0 = fit, +1 = ~2x) and pan is in normalized units bounded by the zoom
// surplus so the picture can never be dragged completely off screen.
// ---------------------------------------------------------------------------

class ZoomPanMath {
  ZoomPanMath._();

  static const double minZoom = 0.0; // mpv log units (fit)
  static const double maxZoom = 2.0; // ~4x linear
  static const double step = 0.08;

  static double clampZoom(double zoom) => zoom.clamp(minZoom, maxZoom).toDouble();

  /// Pan bound: half the extra size the zoom introduces. mpv's pan-x/y is
  /// normalized to the video size, and a zoom of `z` log units (linear
  /// factor = 2^z) overflows the frame by (2^z - 1) of the picture —
  /// half of that per side. At zoom 0 the bound is 0: nothing to pan at
  /// fit size.
  static double panBoundExact(double zoom) {
    if (zoom <= 0) return 0;
    if (zoom > maxZoom) zoom = maxZoom;
    return (math.pow(2, zoom) - 1) / 2;
  }

  static ({double zoom, double panX, double panY}) clampAll({
    required double zoom,
    required double panX,
    required double panY,
  }) {
    final z = clampZoom(zoom);
    final bound = panBoundExact(z);
    return (
      zoom: z,
      panX: panX.clamp(-bound, bound).toDouble(),
      panY: panY.clamp(-bound, bound).toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// Rotation cycle — mpv video-rotate accepts 0/90/180/270.
// ---------------------------------------------------------------------------

class RotationCycle {
  RotationCycle._();

  static const List<int> values = [0, 90, 180, 270];

  static int next(int current) {
    final i = values.indexOf(current);
    if (i < 0) return values[1]; // unknown behaves like 0 → next is 90
    return values[(i + 1) % values.length];
  }

  static int clamp(int deg) =>
      values.contains(deg) ? deg : (deg ~/ 90).clamp(0, 3) * 90;
}

// ---------------------------------------------------------------------------
// Long-press 2x speed boost — YouTube-style: hold to speed up, release to
// restore. State machine with an injectable clock so tests are
// deterministic: the boost only engages after [engageDelay] of holding,
// and a too-short hold leaves the rate untouched.
// ---------------------------------------------------------------------------

class LongPressBoost {
  LongPressBoost({this.engageDelayMs = 400, this.boostRate = 2.0});

  final int engageDelayMs;
  final double boostRate;

  bool _holding = false;
  int _holdStart = 0;
  bool _engaged = false;

  bool get isEngaged => _engaged;
  bool get isHolding => _holding;

  /// Begins a hold; [nowMs] is a monotonic-ish timestamp (clock injectable
  /// via tests). Never engages immediately.
  void start(int nowMs) {
    _holding = true;
    _holdStart = nowMs;
    _engaged = false;
  }

  /// Returns the engage decision once [engageDelayMs] has elapsed.
  /// Called repeatedly from the gesture handler; true exactly once.
  bool tick(int nowMs) {
    if (!_holding || _engaged) return false;
    if (nowMs - _holdStart >= engageDelayMs) {
      _engaged = true;
      return true;
    }
    return false;
  }

  /// Returns true when the boost must be restored (was engaged).
  bool end() {
    final was = _engaged;
    _holding = false;
    _engaged = false;
    _holdStart = 0;
    return was;
  }
}

// ---------------------------------------------------------------------------
// Bookmark navigation — nearest next/previous marker around a position,
// with a small tolerance so "next" while standing on a bookmark does not
// bounce in place.
// ---------------------------------------------------------------------------

class BookmarkNav {
  BookmarkNav._();

  static const int toleranceMs = 400;

  /// Sorted list expected (we sort defensively anyway).
  static int? next(List<int> marks, int positionMs) {
    if (marks.isEmpty) return null;
    final s = (List.of(marks)..sort()).toList();
    for (final m in s) {
      if (m > positionMs + toleranceMs) return m;
    }
    return null;
  }

  static int? previous(List<int> marks, int positionMs) {
    if (marks.isEmpty) return null;
    final s = (List.of(marks)..sort()).toList();
    for (var i = s.length - 1; i >= 0; i--) {
      if (s[i] < positionMs - toleranceMs) return s[i];
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Video picture calibration — mpv exposes brightness/contrast/saturation/
// gamma/hue in [-100, 100]. Clamps + JSON codec for persistence.
// ---------------------------------------------------------------------------

class VideoEq {
  const VideoEq({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.gamma = 0,
    this.hue = 0,
  });

  final double brightness;
  final double contrast;
  final double saturation;
  final double gamma;
  final double hue;

  static const double min = -100;
  static const double max = 100;

  bool get isNeutral =>
      brightness == 0 && contrast == 0 && saturation == 0 &&
      gamma == 0 && hue == 0;

  VideoEq withChannel(String channel, double value) {
    switch (channel) {
      case 'brightness':
        return VideoEq(
            brightness: clamp(value), contrast: contrast,
            saturation: saturation, gamma: gamma, hue: hue);
      case 'contrast':
        return VideoEq(
            brightness: brightness, contrast: clamp(value),
            saturation: saturation, gamma: gamma, hue: hue);
      case 'saturation':
        return VideoEq(
            brightness: brightness, contrast: contrast,
            saturation: clamp(value), gamma: gamma, hue: hue);
      case 'gamma':
        return VideoEq(
            brightness: brightness, contrast: contrast,
            saturation: saturation, gamma: clamp(value), hue: hue);
      case 'hue':
        return VideoEq(
            brightness: brightness, contrast: contrast,
            saturation: saturation, gamma: gamma, hue: clamp(value));
    }
    return this;
  }

  static double clamp(double v) => v.clamp(min, max).toDouble();

  Map<String, dynamic> toMap() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'gamma': gamma,
        'hue': hue,
      };

  static VideoEq fromMap(Map<String, dynamic> m) => VideoEq(
        brightness: clamp((m['brightness'] as num?)?.toDouble() ?? 0),
        contrast: clamp((m['contrast'] as num?)?.toDouble() ?? 0),
        saturation: clamp((m['saturation'] as num?)?.toDouble() ?? 0),
        gamma: clamp((m['gamma'] as num?)?.toDouble() ?? 0),
        hue: clamp((m['hue'] as num?)?.toDouble() ?? 0),
      );

  String encode() => jsonEncode(toMap());

  static VideoEq decode(String raw) {
    try {
      return fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const VideoEq();
    }
  }

  /// mpv property name per channel key (validated in tests so a typo can
  /// never silently no-op).
  static const Map<String, String> mpvProperty = {
    'brightness': 'brightness',
    'contrast': 'contrast',
    'saturation': 'saturation',
    'gamma': 'gamma',
    'hue': 'hue',
  };
}
