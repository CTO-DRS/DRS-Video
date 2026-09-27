import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Platform;


/// v1.12.0 smart-intel algorithms — every function here is pure and
/// unit-tested; no I/O, no Flutter imports. IO glue lives in the
/// services that consume these helpers.

// ---------------------------------------------------------------------------
// Filename metadata parser — turns release-style file names into clean
// titles and tags: "The.Matrix.1999.1080p.BluRay.x264-GROUP" becomes
// title "The Matrix", year 1999, quality 1080p, source BluRay, codec x264.
// Works for Arabic names too (the cleanup is separator-level, so Arabic
// text passes through untouched).
// ---------------------------------------------------------------------------

class FilenameMeta {
  FilenameMeta._();

  static final _seasonEpisode = RegExp(
      r'[\.\s_-]?[Ss](\d{1,2})[\.\s_-]?[Ee](\d{1,3})');
  static final _altSeasonEpisode = RegExp(r'[\.\s_-](\d{1,2})x(\d{1,3})[\.\s_-]');
  static final _year = RegExp(r'[\.\s_\(]((?:19|20)\d{2})[\.\s_\)]');
  static final _quality = RegExp(r'(2160|1440|1080|720|480|360)[pP]');
  static final _source = RegExp(
      r'(BluRay|BDRip|BRRip|WEB[\.\s_-]?DL|WEBRip|WEB|HDTV|DVDRip|DVD|HDRip|CAM|TS)',
      caseSensitive: false);
  static final _codec = RegExp(r'(x265|x264|HEVC|H\.?265|H\.?264|AV1|XviD)',
      caseSensitive: false);
  static final _audioTag =
      RegExp(r'(AAC|AC3|DDP\+?|DTS|Atmos|FLAC|MP3|10bit|HSBS|HOU)', caseSensitive: false);
  static final _releaseGroup = RegExp(r'-([A-Za-z0-9_\.]{2,20})$');

  /// Parsed release metadata (null fields when absent).
  static FilenameInfo parse(String baseName) {
    var working = baseName.trim();
    var season, episode, year;

    final se = _seasonEpisode.firstMatch(working) ?? _altSeasonEpisode.firstMatch(working);
    if (se != null) {
      season = int.tryParse(se.group(1) ?? '');
      episode = int.tryParse(se.group(2) ?? '');
      working = working.replaceRange(se.start, se.end, ' ');
    }
    final y = _year.firstMatch(working);
    if (y != null) {
      year = int.tryParse(y.group(1) ?? '');
      working = working.replaceRange(y.start, y.end, ' ');
    }

    final quality = _quality.firstMatch(working)?.group(0)?.toLowerCase();
    final source = _source.firstMatch(working)?.group(0);
    final codec = _codec.firstMatch(working)?.group(0);
    working = working.replaceAll(_audioTag, ' ');
    working = working.replaceAll(_releaseGroup, ' ');

    // Strip technical leftovers token-by-token; anything that LOOKS like a
    // tag (single latin token, all-caps abbreviations) goes away too.
    final kept = <String>[];
    for (final tok in working.split(RegExp(r'[\.\s_]+'))) {
      if (tok.isEmpty) continue;
      if (_quality.hasMatch(tok) || _source.hasMatch(tok) || _codec.hasMatch(tok)) {
        continue;
      }
      if (tok.length <= 5 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(tok) &&
          tok == tok.toUpperCase() && tok != 'HD') {
        continue; // all-caps junk tokens (e.g. PROPER, REPACK, AAC)
      }
      kept.add(tok);
    }

    var title = kept.join(' ').trim();
    // Dotted names without spaces: "The.Matrix" already joined above; also
    // split camelCase runs ("FastX" -> leave, but "MovieName2023" cleaned).
    title = title.replaceAll(RegExp(r'\s{2,}'), ' ');
    if (title.isEmpty) title = baseName.trim();

    return FilenameInfo(
      title: title,
      year: year,
      season: season,
      episode: episode,
      quality: quality,
      source: source,
      codec: codec,
    );
  }

  /// A display title from a file path: extension stripped, metadata
  /// parsed, fallback to the raw base name when parsing adds nothing.
  static String displayTitle(String path) {
    final base = path.split(Platform.pathSeparator).last;
    final stem = base.replaceAll(RegExp(r'\.[A-Za-z0-9]{1,5}$'), '');
    return parse(stem).title;
  }
}

class FilenameInfo {
  const FilenameInfo({
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.quality,
    this.source,
    this.codec,
  });

  final String title;
  final int? year;
  final int? season;
  final int? episode;
  final String? quality;
  final String? source;
  final String? codec;

  /// "The Matrix (1999) · S01E02 · 1080p" style suffix for subtitles/UI.
  String? get tagLine {
    final parts = <String>[];
    if (season != null && episode != null) {
      parts.add('S${season.toString().padLeft(2, '0')}'
          'E${episode.toString().padLeft(2, '0')}');
    }
    if (quality != null) parts.add(quality!);
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

// ---------------------------------------------------------------------------
// Sibling-subtitle matching — given a video path and the files sitting in
// the same directory, pick the subtitle that most plausibly belongs to it:
//   1. exact stem match            (movie.srt next to movie.mkv)
//   2. stem-prefix with a suffix   (movie.arabic.srt, movie.en.srt)
//   3. shortest fuzzy overlap      (same folder, closest stem)
// ---------------------------------------------------------------------------

class SiblingSubtitles {
  SiblingSubtitles._();

  static const extensions = ['srt', 'vtt', 'ass', 'ssa', 'sub'];

  static String _stem(String fileName) {
    final base = fileName.split(Platform.pathSeparator).last;
    return base.replaceAll(RegExp(r'\.[A-Za-z0-9]{1,5}$'), '').toLowerCase();
  }

  static bool _isSubtitle(String fileName) {
    final m = RegExp(r'\.([A-Za-z0-9]{1,5})$').firstMatch(fileName);
    if (m == null) return false;
    return extensions.contains(m.group(1)!.toLowerCase());
  }

  /// Returns the best candidate full path, or null.
  static String? find(String videoPath, List<String> candidates) {
    final videoStem = _stem(videoPath);
    if (videoStem.isEmpty) return null;
    final subs = candidates.where(_isSubtitle).toList();
    if (subs.isEmpty) return null;

    String? best;
    var bestScore = -1;
    var bestShared = 0;
    for (final c in subs) {
      final stem = _stem(c);
      var score = 0;
      var shared = 0;
      if (stem == videoStem) {
        score = 1000;
      } else if (stem.startsWith(videoStem) &&
          stem.length > videoStem.length &&
          stem.substring(videoStem.length, videoStem.length + 1) == '.') {
        score = 800 - (stem.length - videoStem.length);
      } else if (videoStem.startsWith(stem) && stem.length >= 3) {
        score = 600 - (videoStem.length - stem.length);
      } else {
        // Token overlap (fuzzy): shared words between the two stems.
        final a = videoStem.split(RegExp(r'[^a-z0-9\u0600-\u06ff]+')).toSet();
        final b = stem.split(RegExp(r'[^a-z0-9\u0600-\u06ff]+')).toSet()..remove('');
        if (a.isEmpty || b.isEmpty) continue;
        shared = a.intersection(b).length;
        if (shared == 0) continue;
        score = 100 + shared * 10 - (stem.length - videoStem.length).abs() ~/ 4;
      }
      // Language hint bonuses (Arabic first — this is an Arabic-first app).
      final lower = stem.toLowerCase();
      if (lower.contains('.ar') || lower.contains('arabic') ||
          lower.contains('.ara') || lower.contains('مترجم') ||
          lower.contains('عربي')) {
        score += 50;
      } else if (lower.contains('.en') || lower.contains('english')) {
        score += 20;
      }
      if (score > bestScore) {
        bestScore = score;
        bestShared = shared;
        best = c;
      }
    }
    // Prefix/exact classes (>=600) always win; token-overlap matches need
    // at least TWO shared words so unrelated same-folder subs stay out.
    return (bestScore >= 600 || bestShared >= 2) ? best : null;
  }
}

// ---------------------------------------------------------------------------
// Adaptive seek — long videos deserve bigger double-tap jumps.
// ---------------------------------------------------------------------------

class AdaptiveSeek {
  AdaptiveSeek._();

  /// Double-tap seek step for a video of [durationMs].
  ///  <15 min → 10 s · <1 h → 15 s · <2 h → 20 s · longer → 30 s
  /// (piecewise, deterministic, never below 5 s nor above 60 s).
  static int stepMs(int durationMs) {
    if (durationMs <= 0) return 10000;
    final minutes = durationMs / 60000.0;
    int step;
    if (minutes < 15) {
      step = 10000;
    } else if (minutes < 60) {
      step = 15000;
    } else if (minutes < 120) {
      step = 20000;
    } else {
      step = 30000;
    }
    return step.clamp(5000, 60000);
  }
}

// ---------------------------------------------------------------------------
// Battery saver — auto audio-only when the battery is low and unplugged.
// ---------------------------------------------------------------------------

class BatterySaver {
  BatterySaver._();

  static const defaultThresholdPercent = 20;

  /// True when playback should switch to audio-only automatically.
  static bool shouldAutoAudioOnly({
    required bool enabled,
    required int levelPercent,
    required bool plugged,
    int thresholdPercent = defaultThresholdPercent,
  }) {
    if (!enabled) return false;
    if (plugged) return false;
    if (levelPercent < 0 || levelPercent > 100) return false;
    return levelPercent <= thresholdPercent;
  }
}

// ---------------------------------------------------------------------------
// Data saver — caps stream quality when the user opts in.
// ---------------------------------------------------------------------------

class DataSaver {
  DataSaver._();

  /// Cap applied when data saver is on (kbps) — 720p-ish for HLS/DASH.
  static const defaultCapKbps = 3000;

  /// The effective HLS cap: never RAISES an explicit user cap, only
  /// lowers the auto (null) cap or a larger one.
  static int? effectiveHlsCap(int? userCap, {required bool saverOn}) {
    if (!saverOn) return userCap;
    if (userCap == null) return defaultCapKbps;
    return userCap < defaultCapKbps ? userCap : defaultCapKbps;
  }
}

// ---------------------------------------------------------------------------
// Intro skip memory — remember where the intro of a SERIES FOLDER ends and
// auto-seek past it on the next episode in the same folder.
// ---------------------------------------------------------------------------

class IntroSkip {
  IntroSkip._();

  /// Stable key for the folder that contains [path] (local paths and
  /// remote URLs alike — for URLs the directory segment is used).
  static String folderKeyOf(String path) {
    final p = path.trim();
    if (p.startsWith('http')) {
      final uri = Uri.tryParse(p);
      final segs = uri?.pathSegments.toList() ?? const <String>[];
      if (segs.length >= 2) {
        return Uri.encodeComponent(segs.sublist(0, segs.length - 1).join('/'));
      }
      return uri?.host ?? p;
    }
    final dir = p.split(Platform.pathSeparator)..removeLast();
    return dir.isEmpty ? p : dir.join('/');
  }

  /// The effective start position (ms) for a fresh open.
  /// Intro skip only fires BEFORE the resume point logic; if a saved
  /// resume position exists it always wins (never skip past user progress).
  static int? startMs({
    required int? introEndMs,
    required int? resumePositionMs,
  }) {
    if (introEndMs == null || introEndMs <= 0) return null;
    if (resumePositionMs != null && resumePositionMs > introEndMs) {
      return null; // user already watched past the intro
    }
    if (resumePositionMs != null && resumePositionMs >= 0) {
      return introEndMs > resumePositionMs ? introEndMs : null;
    }
    return introEndMs;
  }
}

// ---------------------------------------------------------------------------
// Video bookmarks — timestamp markers persisted per media item.
// ---------------------------------------------------------------------------

class VideoBookmark {
  const VideoBookmark({required this.positionMs, this.label});

  final int positionMs;
  final String? label;

  Map<String, Object?> toMap() => {'ms': positionMs, 'label': label};

  factory VideoBookmark.fromMap(Map<Object?, Object?> m) => VideoBookmark(
        positionMs: (m['ms'] as num?)?.toInt() ?? 0,
        label: m['label'] as String?,
      );

  VideoBookmark copyWith({int? positionMs, String? label}) => VideoBookmark(
        positionMs: positionMs ?? this.positionMs,
        label: label ?? this.label,
      );
}

class BookmarkCodec {
  BookmarkCodec._();

  /// Encodes sorted (ascending) — order is part of the contract.
  static String encode(List<VideoBookmark> marks) {
    final sorted = List.of(marks)..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    return jsonEncode(sorted.map((m) => m.toMap()).toList());
  }

  static List<VideoBookmark> decode(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => VideoBookmark.fromMap(m))
          .where((b) => b.positionMs >= 0)
          .toList()
        ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    } catch (_) {
      return const [];
    }
  }
}

// ---------------------------------------------------------------------------
// Closed-caption → SRT conversion (pure) — used by the YouTube
// auto-subtitles pipeline.
// ---------------------------------------------------------------------------

class CaptionCue {
  const CaptionCue({required this.startMs, required this.durationMs, required this.text});

  final int startMs;
  final int durationMs;
  final String text;
}

class SrtBuilder {
  SrtBuilder._();

  static String _stamp(int ms) {
    final h = (ms ~/ 3600000).toString().padLeft(2, '0');
    final m = ((ms % 3600000) ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final msec = (ms % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$msec';
  }

  /// Deterministic SRT; blank cues dropped, overlapping next-start clamps
  /// the previous end so players never render two cues on top of each other.
  static String build(List<CaptionCue> cues) {
    final clean = cues
        .map((c) => CaptionCue(
              startMs: c.startMs < 0 ? 0 : c.startMs,
              durationMs: c.durationMs <= 0 ? 1200 : c.durationMs,
              text: c.text.trim(),
            ))
        .where((c) => c.text.isNotEmpty)
        .toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    final buf = StringBuffer();
    for (var i = 0; i < clean.length; i++) {
      final c = clean[i];
      var end = c.startMs + c.durationMs;
      if (i + 1 < clean.length && end > clean[i + 1].startMs) {
        end = clean[i + 1].startMs;
      }
      if (end <= c.startMs) end = c.startMs + 500;
      buf
        ..writeln('${i + 1}')
        ..writeln('${_stamp(c.startMs)} --> ${_stamp(end)}')
        ..writeln(c.text)
        ..writeln();
    }
    return buf.toString();
  }
}


// ---------------------------------------------------------------------------
// Version comparison for the in-app updater — accepts "1.2.3", "1.2.3+11",
// "v1.2.3". Builds come from versionCode but release tags are names, so
// compare NAME parts semantically; equal names → not newer.
// ---------------------------------------------------------------------------

class VersionCompare {
  VersionCompare._();

  static List<int> _parts(String version) {
    var v = version.trim().toLowerCase();
    if (v.startsWith('v')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    final dash = RegExp(r'[-_]').firstMatch(v);
    if (dash != null) v = v.substring(0, dash.start);
    final parts = v
        .split('.')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  /// True when [candidate] is strictly newer than [current].
  static bool isNewer(String candidate, String current) {
    final a = _parts(candidate);
    final b = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }
}
