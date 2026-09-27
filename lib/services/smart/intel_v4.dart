/// intel_v4 — pure algorithm pack for v1.14.0 (downloads studio + media
/// studios + add-download sheet). Everything here is pure Dart: no I/O, no
/// Flutter imports, fully unit-testable.
///
/// Algorithms:
///  - DownloadClassifier: URL/content-type → download kind.
///  - ClipboardLinkGate: safe clipboard auto-paste decision (dedup + validity).
///  - FileNameSuggester: Content-Disposition/URL/mime → clean file name.
///  - MediaBucket: file path → studio bucket (video/audio/image/other).
///  - ImageAdjustments: brightness/contrast/gamma/grayscale/invert LUT math.
///  - OrientationMatrix: rotate/flip index mapping used by the image editor.
///  - ProbeSummary: parse HEAD response headers into a preview model.
library intel_v4;

import 'dart:math' as math;
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// DownloadClassifier
// ---------------------------------------------------------------------------

/// What a downloaded link most likely is. Drives default folder choice,
/// icons and post-download "open with" hints.
enum DownloadKind { video, audio, image, archive, document, app, other }

class DownloadClassifier {
  static const Map<String, DownloadKind> _byExt = {
    'mp4': DownloadKind.video, 'mkv': DownloadKind.video,
    'webm': DownloadKind.video, 'avi': DownloadKind.video,
    'mov': DownloadKind.video, 'flv': DownloadKind.video,
    'm4v': DownloadKind.video, '3gp': DownloadKind.video,
    'ts': DownloadKind.video, 'wmv': DownloadKind.video,
    'mp3': DownloadKind.audio, 'm4a': DownloadKind.audio,
    'aac': DownloadKind.audio, 'wav': DownloadKind.audio,
    'flac': DownloadKind.audio, 'ogg': DownloadKind.audio,
    'opus': DownloadKind.audio, 'oga': DownloadKind.audio,
    'jpg': DownloadKind.image, 'jpeg': DownloadKind.image,
    'png': DownloadKind.image, 'gif': DownloadKind.image,
    'webp': DownloadKind.image, 'bmp': DownloadKind.image,
    'heic': DownloadKind.image, 'avif': DownloadKind.image,
    'zip': DownloadKind.archive, 'rar': DownloadKind.archive,
    '7z': DownloadKind.archive, 'tar': DownloadKind.archive,
    'gz': DownloadKind.archive, 'apk': DownloadKind.app,
    'pdf': DownloadKind.document, 'srt': DownloadKind.document,
    'vtt': DownloadKind.document, 'txt': DownloadKind.document,
    'epub': DownloadKind.document, 'doc': DownloadKind.document,
    'docx': DownloadKind.document, 'ass': DownloadKind.document,
  };

  static const Map<String, DownloadKind> _byMime = {
    'video/': DownloadKind.video, 'audio/': DownloadKind.audio,
    'image/': DownloadKind.image,
    'application/zip': DownloadKind.archive,
    'application/x-rar': DownloadKind.archive,
    'application/x-7z': DownloadKind.archive,
    'application/gzip': DownloadKind.archive,
    'application/vnd.android.package-archive': DownloadKind.app,
    'application/pdf': DownloadKind.document,
    'text/': DownloadKind.document,
  };

  /// mime-prefix → canonical extension (used by [extensionFor]).
  static const Map<String, String> _mimePrimaryExt = {
    'video/mp4': 'mp4', 'video/webm': 'webm', 'video/x-matroska': 'mkv',
    'video/': 'mp4',
    'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/ogg': 'ogg',
    'audio/': 'm4a',
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
    'image/': 'jpg',
    'application/zip': 'zip', 'application/pdf': 'pdf',
    'application/vnd.android.package-archive': 'apk',
    'text/': 'txt',
  };

  /// Classifies by content-type first (authoritative), then extension.
  static DownloadKind classify({required String url, String? contentType}) {
    final mime = (contentType ?? '').toLowerCase().split(';').first.trim();
    for (final entry in _byMime.entries) {
      if (mime.startsWith(entry.key)) return entry.value;
    }
    final ext = extensionOf(url);
    final byExt = _byExt[ext];
    if (byExt != null) return byExt;
    return DownloadKind.other;
  }

  /// Extension of a URL path (no query/fragment), lowercased, no dot.
  static String extensionOf(String url) {
    final clean = url.split('?').first.split('#').first;
    final slash = clean.lastIndexOf('/');
    final last = slash < 0 ? clean : clean.substring(slash);
    final dot = last.lastIndexOf('.');
    if (dot < 0 || dot == last.length - 1 || last.length - dot > 6) return '';
    return last.substring(dot + 1).toLowerCase();
  }

  /// Best-effort fallback extension for a download: mime → ext when the URL
  /// carries no usable extension. Never empty (falls back to 'bin').
  static String extensionFor({required String url, String? contentType}) {
    final byUrl = extensionOf(url);
    if (byUrl.isNotEmpty) return byUrl;
    final mime = (contentType ?? '').toLowerCase().split(';').first.trim();
    for (final entry in _mimePrimaryExt.entries) {
      if (mime.startsWith(entry.key)) return entry.value;
    }
    return 'bin';
  }

  /// Icon code-point hint (kept as enum-adjacent helper for the UI).
  static bool isStreamable(DownloadKind kind) =>
      kind == DownloadKind.video || kind == DownloadKind.audio;
}

// ---------------------------------------------------------------------------
// ClipboardLinkGate — safe auto-paste
// ---------------------------------------------------------------------------

/// Decision for auto-pasting a clipboard string into the add-download sheet.
enum ClipboardDecision { accept, duplicate, invalid }

class ClipboardLinkGate {
  /// - [raw] clipboard text.
  /// - [lastAccepted] the last URL this gate already accepted (dedup so the
  ///   sheet does not re-suggest the same link forever).
  /// - [alreadyInField] the sheet field already holds this exact text.
  static ClipboardDecision decide(
    String? raw, {
    String? lastAccepted,
    String? alreadyInField,
  }) {
    if (raw == null) return ClipboardDecision.invalid;
    final t = raw.trim();
    if (t.isEmpty || t.length > 2048) return ClipboardDecision.invalid;
    final uri = Uri.tryParse(t);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return ClipboardDecision.invalid;
    }
    if (uri.host.isEmpty) return ClipboardDecision.invalid;
    if (alreadyInField != null && alreadyInField.trim() == t) {
      return ClipboardDecision.duplicate;
    }
    if (lastAccepted != null && lastAccepted == t) {
      return ClipboardDecision.duplicate;
    }
    return ClipboardDecision.accept;
  }

  /// Non-URL text like a bare YouTube id is rejected; only real links pass.
  static bool isHttpUrl(String s) =>
      decide(s) == ClipboardDecision.accept;
}

// ---------------------------------------------------------------------------
// FileNameSuggester
// ---------------------------------------------------------------------------

class FileNameSuggester {
  static const Map<String, String> _mimeToExt = {
    'video/mp4': 'mp4', 'video/webm': 'webm', 'video/x-matroska': 'mkv',
    'video/quicktime': 'mov', 'video/x-msvideo': 'avi',
    'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/aac': 'aac',
    'audio/wav': 'wav', 'audio/x-wav': 'wav', 'audio/flac': 'flac',
    'audio/ogg': 'ogg', 'audio/opus': 'opus',
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/gif': 'gif',
    'image/webp': 'webp', 'image/bmp': 'bmp',
    'application/zip': 'zip', 'application/pdf': 'pdf',
    'application/vnd.android.package-archive': 'apk',
    'application/x-subrip': 'srt', 'text/plain': 'txt',
  };

  // RFC 6266 / 5987: filename*=UTF-8''… (extended), quoted filename="…",
  // then a plain unquoted token. Raw strings with double-quote delimiters
  // keep the single quotes inside the patterns intact.
  static final RegExp _dispExt =
      RegExp(r"filename\*=(?:utf-8)''([^;]+)", caseSensitive: false);
  static final RegExp _dispQuoted =
      RegExp(r'filename\s*=\s*"([^"]*)"', caseSensitive: false);
  static final RegExp _dispPlain =
      RegExp(r'filename\s*=\s*([^";]+)', caseSensitive: false);

  static String? _dispositionName(String d) {
    var m = _dispExt.firstMatch(d);
    if (m != null) {
      final raw = m.group(1)!.trim();
      try {
        return Uri.decodeComponent(raw);
      } catch (_) {
        return raw;
      }
    }
    m = _dispQuoted.firstMatch(d);
    if (m != null) return m.group(1)!.trim();
    m = _dispPlain.firstMatch(d);
    if (m != null) return m.group(1)!.trim();
    return null;
  }

  /// Suggests a safe file name.
  ///
  /// Priority: Content-Disposition filename → URL basename → [fallback].
  /// The extension is corrected to match [contentType] when it disagrees.
  static String suggest({
    required String url,
    String? contentType,
    String? disposition,
    String fallback = 'download',
  }) {
    var name = '';
    if (disposition != null && disposition.isNotEmpty) {
      name = _dispositionName(disposition) ?? '';
    }
    if (name.isEmpty) {
      final clean = url.split('?').first.split('#').first;
      final slash = clean.lastIndexOf('/');
      if (slash >= 0 && slash < clean.length - 1) name = clean.substring(slash + 1);
    }
    if (name.isEmpty) name = fallback;
    name = sanitize(name);
    if (name.isEmpty) name = fallback;

    final mime = (contentType ?? '').toLowerCase().split(';').first.trim();
    final wantExt = _mimeToExt[mime] ?? DownloadClassifier.extensionOf(url);
    if (wantExt.isNotEmpty) {
      final hasExt = name.contains('.');
      final curExt = hasExt
          ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
          : '';
      if (!hasExt || curExt != wantExt) {
        final stem = hasExt ? name.substring(0, name.lastIndexOf('.')) : name;
        if (stem.trim().isNotEmpty) name = '$stem.$wantExt';
      }
    }
    return name;
  }

  /// Path-traversal-safe, cross-platform-safe name. Keeps Arabic + spaces.
  static String sanitize(String name) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.length > 120) s = s.substring(0, 120).trim();
    return s;
  }
}

// ---------------------------------------------------------------------------
// MediaBucket — file path → studio bucket
// ---------------------------------------------------------------------------

enum MediaBucket { video, audio, image, other }

class MediaCataloguer {
  static const videoExts = {
    'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'm4v', '3gp', 'ts', 'wmv',
  };
  static const audioExts = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'oga', 'wma',
  };
  static const imageExts = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'avif',
  };

  static MediaBucket of(String path) {
    final ext = path.contains('.')
        ? path.substring(path.lastIndexOf('.') + 1).toLowerCase()
        : '';
    if (videoExts.contains(ext)) return MediaBucket.video;
    if (audioExts.contains(ext)) return MediaBucket.audio;
    if (imageExts.contains(ext)) return MediaBucket.image;
    return MediaBucket.other;
  }

  /// Pure scan reducer: given file paths + their sizes/mtimes, bucket them.
  static Map<MediaBucket, List<StudioFile>> bucket(List<StudioFile> files) {
    final out = {
      for (final b in MediaBucket.values) b: <StudioFile>[],
    };
    for (final f in files) {
      out[of(f.path)]!.add(f);
    }
    // Newest first — deterministic order for the studios.
    for (final list in out.values) {
      list.sort((a, b) => b.modified.compareTo(a.modified));
    }
    return out;
  }
}

/// Plain data class describing a file on disk (pure; no dart:io types so
/// tests can construct it freely).
class StudioFile {
  StudioFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;
}

// ---------------------------------------------------------------------------
// ImageAdjustments — LUT math for the editor
// ---------------------------------------------------------------------------

/// Image adjustment parameters. Each channel byte goes through:
/// brightness (add) → contrast (scale around midpoint) → gamma curve →
/// grayscale mix → invert. Everything clamped to 0..255.
class ImageAdjustments {
  const ImageAdjustments({
    this.brightness = 0,
    this.contrast = 1.0,
    this.gamma = 1.0,
    this.grayscale = false,
    this.invert = false,
  });

  /// -255..255
  final int brightness;
  /// 0..2 (1 = unchanged)
  final double contrast;
  /// 0.1..3 (1 = unchanged)
  final double gamma;
  final bool grayscale;
  final bool invert;

  bool get isNeutral =>
      brightness == 0 &&
      contrast == 1.0 &&
      gamma == 1.0 &&
      !grayscale &&
      !invert;

  /// Builds a 256-entry lookup table. Pure function of the parameters.
  static Uint8List lut(ImageAdjustments a) {
    final table = Uint8List(256);
    final c = a.contrast.clamp(0.0, 2.0);
    final g = a.gamma <= 0 ? 1.0 : a.gamma;
    for (int i = 0; i < 256; i++) {
      double v = (i + a.brightness).toDouble();
      v = (v - 127.5) * c + 127.5;
      v = 255.0 * _powClamped(v / 255.0, 1.0 / g);
      if (a.invert) v = 255.0 - v;
      table[i] = v.round().clamp(0, 255);
    }
    return table;
  }

  static double _powClamped(double x, double e) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    return math.pow(x, e).toDouble();
  }

  /// BT.601 luma used by the editor's grayscale pass (channel mixing that a
  /// per-channel LUT cannot express).
  static double luma(int r, int g, int b) =>
      0.299 * r + 0.587 * g + 0.114 * b;
}

// ---------------------------------------------------------------------------
// OrientationMatrix — rotate/flip index mapping
// ---------------------------------------------------------------------------

/// Describes a pure geometric transform on a w×h pixel grid.
enum FlipMode { none, horizontal, vertical }

class OrientationMatrix {
  const OrientationMatrix({
    this.quarterTurns = 0,
    this.flip = FlipMode.none,
  });

  /// 0..3 (90° steps, clockwise)
  final int quarterTurns;
  final FlipMode flip;

  bool get swapsAxes => quarterTurns.isOdd;
  bool get isIdentity => quarterTurns % 4 == 0 && flip == FlipMode.none;

  /// Output dimensions for an input w×h.
  (int, int) outputSize(int w, int h) =>
      swapsAxes ? (h, w) : (w, h);

  /// Maps output pixel (x,y) → source pixel (x',y') (inverse mapping used by
  /// sampling loops so every output pixel is filled exactly once).
  /// [w]/[h] are the SOURCE dimensions; output dims are swapped for odd
  /// quarter-turns (flip must be undone in OUTPUT space, rotation in SOURCE).
  (int, int) sourceOf(int x, int y, int w, int h) {
    final swap = quarterTurns.isOdd;
    final outW = swap ? h : w;
    final outH = swap ? w : h;
    var sx = x, sy = y;
    // Undo flip first (applied last in forward direction).
    if (flip == FlipMode.horizontal) sx = outW - 1 - sx;
    if (flip == FlipMode.vertical) sy = outH - 1 - sy;
    // Undo rotation: rotate output coordinates counter-clockwise by q turns.
    final q = ((quarterTurns % 4) + 4) % 4;
    switch (q) {
      case 1: // CW90: source(x',y') → out(h-1-y', x'); inverse: (y, h-1-x)
        return (sy, h - 1 - sx);
      case 2:
        return (w - 1 - sx, h - 1 - sy);
      case 3: // CW270: source(x',y') → out(y', w-1-x'); inverse: (w-1-y, x)
        return (w - 1 - sy, sx);
      default:
        return (sx, sy);
    }
  }

  OrientationMatrix rotate90() => OrientationMatrix(
      quarterTurns: (quarterTurns + 1) % 4, flip: flip);

  OrientationMatrix flipH() => OrientationMatrix(
      quarterTurns: quarterTurns,
      flip: flip == FlipMode.horizontal ? FlipMode.none : FlipMode.horizontal);

  OrientationMatrix flipV() => OrientationMatrix(
      quarterTurns: quarterTurns,
      flip: flip == FlipMode.vertical ? FlipMode.none : FlipMode.vertical);
}

// ---------------------------------------------------------------------------
// ProbeSummary — HEAD response → preview model (pure)
// ---------------------------------------------------------------------------

class ProbeSummary {
  const ProbeSummary({
    required this.kind,
    required this.fileName,
    required this.sizeBytes,
    required this.resumable,
    required this.contentType,
  });

  final DownloadKind kind;
  final String fileName;
  final int sizeBytes; // -1 unknown
  final bool resumable;
  final String contentType;

  /// Pure parser: [status] and [headers] from a HEAD request.
  /// Throws FormatException on non-2xx so the caller can show an honest error.
  static ProbeSummary fromResponse({
    required int status,
    required Map<String, List<String>> headers,
    required String url,
  }) {
    if (status < 200 || status >= 300) {
      throw FormatException('HTTP $status');
    }
    String? contentType;
    String? disposition;
    int size = -1;
    var resumable = false;
    headers.forEach((k, v) {
      final key = k.toLowerCase();
      final val = v.isEmpty ? '' : v.first;
      switch (key) {
        case 'content-type':
          contentType = val;
        case 'content-disposition':
          disposition = val;
        case 'content-length':
          size = int.tryParse(val.trim()) ?? -1;
        case 'accept-ranges':
          resumable = val.toLowerCase().contains('bytes');
      }
    });
    final name = FileNameSuggester.suggest(
      url: url,
      contentType: contentType,
      disposition: disposition,
    );
    return ProbeSummary(
      kind: DownloadClassifier.classify(url: url, contentType: contentType),
      fileName: name,
      sizeBytes: size,
      resumable: resumable,
      contentType: (contentType ?? '').split(';').first.trim(),
    );
  }
}
