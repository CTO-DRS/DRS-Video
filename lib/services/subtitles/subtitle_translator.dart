import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';
import '../player/subtitle_charset.dart';
import '../player/subtitle_parser.dart';
import '../smart/intel_v3.dart';

/// Free subtitle translation over the public Google translate web endpoint
/// (`client=gtx` — the same one the web widget uses; no key, no account).
///
/// Pipeline: SRT → cue texts (timing kept intact) → char-budgeted batches
/// → gtx requests with retry/backoff → 1:1 line mapping (per-line fallback
/// when the server merges lines) → translated SRT. Everything is cached
/// under cache/translations so a re-translation of the same file is
/// instant and offline.
///
/// The fetcher is injectable for tests; production uses Dio.
class SubtitleTranslator {
  SubtitleTranslator({Dio? dio, this.fetcherOverride, this.baseDirOverride})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 25),
              responseType: ResponseType.plain,
            ));

  final Dio _dio;

  /// Test hook: when set, every request goes through it instead of Dio.
  final Future<String> Function(Uri url)? fetcherOverride;

  /// Test hook: base dir for the translation cache (app default = temp).
  final Future<String>? Function()? baseDirOverride;

  static const endpoint = 'https://translate.googleapis.com/translate_a/single';

  /// Languages offered in the sheet (ISO codes the endpoint understands).
  static const List<(String, String)> languages = [
    ('ar', 'العربية'),
    ('en', 'English'),
    ('fr', 'Français'),
    ('es', 'Español'),
    ('de', 'Deutsch'),
    ('tr', 'Türkçe'),
    ('ur', 'اردو'),
    ('hi', 'हिन्दी'),
    ('id', 'Indonesia'),
    ('fa', 'فارسی'),
    ('ru', 'Русский'),
    ('zh-CN', '中文'),
    ('ja', '日本語'),
    ('ko', '한국어'),
    ('pt', 'Português'),
    ('it', 'Italiano'),
  ];

  /// Progress: 0..1 while translating. [sourceLang] is the detected source
  /// (filled on the first successful batch).
  Future<TranslationResult> translateSrt(
    String srt, {
    required String targetLang,
    void Function(double progress)? onProgress,
  }) async {
    // Real validation first: refuse garbage before spending network time.
    SubtitleParser.parse(srt);

    final texts = SrtTextOps.textsForTranslation(srt);
    if (texts.isEmpty) {
      return const TranslationResult(
          srt: '', detectedSource: '', partial: false, translatedCues: 0);
    }

    final batches = TranslationBatcher.batch(texts);
    final translated = List<String>.from(texts);
    String detected = '';
    var done = 0;
    var failedCues = 0;

    for (final batch in batches) {
      final ok = await _translateBatch(
        batch.payload,
        targetLang,
        expectedLines: batch.lines.length,
      );
      if (ok != null) {
        if (detected.isEmpty && ok.detectedSource.isNotEmpty) {
          detected = ok.detectedSource;
          // Already in the target language — no network waste on the
          // rest; the caller keeps the original file (honest no-op).
          if (detected.toLowerCase() == targetLang.toLowerCase()) {
            return TranslationResult(
              srt: '',
              detectedSource: detected,
              partial: false,
              translatedCues: 0,
              alreadyTarget: true,
            );
          }
        }
        for (var i = 0; i < ok.lines.length; i++) {
          final idx = batch.startCue + i;
          if (idx >= 0 && idx < translated.length) translated[idx] = ok.lines[i];
        }
      } else {
        failedCues += batch.lines.length;
      }
      done += batch.lines.length;
      onProgress?.call(done / texts.length);
    }

    final partial = failedCues > 0;
    final resultSrt = SrtTextOps.rebuild(srt, translated);
    return TranslationResult(
      srt: resultSrt,
      detectedSource: detected,
      partial: partial,
      translatedCues: texts.length - failedCues,
    );
  }

  /// One batch → (translated lines mapped 1:1). Two strategies:
  /// 1. whole-payload request, then map by '\n' count;
  /// 2. per-line requests when the server merged lines.
  /// Returns null only when BOTH strategies fail for a line — the caller
  /// keeps the original text for those cues (honest partial result).
  Future<({String text, String detectedSource, List<String> lines})?>
      _translateBatch(
    String payload,
    String targetLang, {
    required int expectedLines,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _request(payload, targetLang);
        final parsed = GtxResponse.parse(res);
        final lines = GtxResponse.mapLines(parsed.text, expectedLines);
        if (lines != null) {
          return (
            text: parsed.text,
            detectedSource: parsed.detectedSource,
            lines: lines.map((e) => e.trim()).toList(),
          );
        }
        // Server merged/split lines — per-line fallback.
        final perLine = await _translatePerLine(payload, targetLang);
        if (perLine != null) {
          return (
            text: perLine.join('\n'),
            detectedSource: parsed.detectedSource,
            lines: perLine,
          );
        }
        return null;
      } catch (e) {
        AppLogger.instance.warning('translate', 'batch attempt $attempt: $e');
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
      }
    }
    return null;
  }

  Future<List<String>?> _translatePerLine(
      String payload, String targetLang) async {
    final lines = payload.split('\n');
    final out = <String>[];
    for (final line in lines) {
      if (line.trim().isEmpty) {
        out.add(line);
        continue;
      }
      try {
        final res = await _request(line, targetLang);
        final parsed = GtxResponse.parse(res);
        out.add(parsed.text.trim());
      } catch (_) {
        return null; // whole batch falls back to original text
      }
    }
    return out;
  }

  Future<String> _request(String q, String targetLang) async {
    final uri = Uri.parse(endpoint).replace(queryParameters: {
      'client': 'gtx',
      'sl': 'auto',
      'tl': targetLang,
      'dt': 't',
      'q': q,
    });
    final override = fetcherOverride;
    if (override != null) return override(uri);
    final res = await _dio.get<String>(uri.toString());
    final body = res.data;
    if (body == null || body.isEmpty) {
      throw const FormatException('gtx: empty body');
    }
    return body;
  }

  // ---- file-level glue ------------------------------------------------

  /// Translates an SRT file on disk and writes the result into the app's
  /// translation cache. Returns a rich result (null = nothing usable —
  /// empty input, or the file was already in the target language).
  Future<SubtitleFileTranslation?> translateFile(
    String inputPath, {
    required String targetLang,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    final text = SubtitleCharset.decode(bytes);
    final res = await translateSrt(
      text,
      targetLang: targetLang,
      onProgress: onProgress,
    );
    if (res.srt.trim().isEmpty) {
      if (res.alreadyTarget) {
        return SubtitleFileTranslation(
          srtPath: null, partial: false, alreadyTarget: true);
      }
      return null;
    }
    final dir = await _translationsDir();
    final path = '${dir.path}/${TranslationCacheKeys.fileKey(text, targetLang)}';
    await File(path).writeAsString(res.srt, flush: true, encoding: utf8);
    return SubtitleFileTranslation(
      srtPath: path, partial: res.partial, alreadyTarget: false);
  }

  /// Cached translation lookup — same input text + target → same file.
  Future<String?> cachedTranslation(String srtText, String targetLang) async {
    final dir = await _translationsDir();
    final f = File(
        '${dir.path}/${TranslationCacheKeys.fileKey(srtText, targetLang)}');
    return f.existsSync() ? f.path : null;
  }

  Future<Directory> _translationsDir() async {
    final base = await getTranslationsBase();
    final dir = Directory(base);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// App default: cache/translations under the temp dir; tests inject.
  Future<String> getTranslationsBase() async {
    final override = baseDirOverride;
    if (override != null) return override() ?? _defaultBase();
    return _defaultBase();
  }

  Future<String> _defaultBase() async {
    final base = await getTemporaryDirectory();
    return '${base.path}/translations';
  }
}

/// File-level translation outcome (written cache path + status flags).
class SubtitleFileTranslation {
  const SubtitleFileTranslation({
    required this.srtPath,
    required this.partial,
    required this.alreadyTarget,
  });

  /// Path of the translated SRT inside the cache; null when the input was
  /// already in the target language (nothing to write).
  final String? srtPath;
  final bool partial;
  final bool alreadyTarget;
}

/// Outcome of a full-file translation.
class TranslationResult {
  const TranslationResult({
    required this.srt,
    required this.detectedSource,
    required this.partial,
    required this.translatedCues,
    this.alreadyTarget = false,
  });

  final String srt;
  final String detectedSource;
  final bool partial;
  final int translatedCues;

  /// True when the source language already equals the target — nothing
  /// was translated on purpose.
  final bool alreadyTarget;

  bool get isEmpty => srt.trim().isEmpty;
}
