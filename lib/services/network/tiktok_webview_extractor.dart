import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/utils/logger.dart';

/// Extraction result from a headless WebView run.
class WebViewExtraction {
  const WebViewExtraction({this.payloadJson, this.mediaUrl, this.finalUrl});

  /// Raw JSON text of `__UNIVERSAL_DATA_FOR_REHYDRATION__` / `SIGI_STATE`
  /// rendered by the real browser engine (survives JS challenges that
  /// break plain HTTP fetches).
  final String? payloadJson;

  /// A direct video URL observed while the page played the clip
  /// (`video/tos/...` CDN requests). Fallback when the JSON path fails.
  final String? mediaUrl;

  /// Final URL after redirects (short link → canonical /video/<id>).
  final String? finalUrl;

  bool get isEmpty =>
      (payloadJson == null || payloadJson!.isEmpty) && mediaUrl == null;
}

/// Loads a TikTok page in a REAL headless browser engine (the same
/// WebView the built-in browser uses) and harvests the video payload.
///
/// Why this exists: TikTok increasingly serves anti-bot challenges to
/// plain HTTP clients, so static fetches return a captcha page without
/// any data. A headless WebView executes JavaScript exactly like the
/// user's browser, so the page renders and embeds its data normally.
///
/// Heavy (5–15 s): last resort in the TikTokResolver chain. Never throws.
class TikTokWebViewExtractor {
  TikTokWebViewExtractor._();

  static final TikTokWebViewExtractor instance = TikTokWebViewExtractor._();

  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Extra waits after load stop for SPA data (TikTok hydrates late).
  static const _jsDelays = [Duration(seconds: 2), Duration(seconds: 4)];

  /// Extracts from [url]; null on any failure or timeout. Safe from UI.
  Future<WebViewExtraction?> extract(
    String url, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    HeadlessInAppWebView? headless;
    final done = Completer<WebViewExtraction>();
    final seen = <String>{};
    String? mediaUrl;

    try {
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(url),
          headers: {'User-Agent': _desktopUa},
        ),
        initialSettings: InAppWebViewSettings(
          userAgent: _desktopUa,
          javaScriptEnabled: true,
          useShouldInterceptRequest: true,
          useOnLoadResource: true,
          transparentBackground: true,
          loadsImagesAutomatically: false,
          cacheEnabled: true,
          supportZoom: false,
        ),
        shouldInterceptRequest: (c, request) async {
          final u = request.url.toString();
          if (looksLikeVideoUrl(u) && seen.add(u)) {
            mediaUrl ??= u; // first (usually the smallest/redirector) wins
            if (!done.isCompleted && _payloadSeen(seen, mediaUrl)) {
              // Not completing here: JSON is preferred; see onLoadStop.
            }
          }
          return null; // always allow the real request through
        },
        onLoadResource: (c, resource) {
          final u = resource.url?.toString();
          if (u != null && looksLikeVideoUrl(u) && seen.add(u)) {
            mediaUrl ??= u;
          }
        },
        onLoadStop: (c, finalUrl) async {
          try {
            // Attempt 1: immediate SSR payload.
            var json = await _readPayload(c);
            // Attempts 2..3: SPA hydration delays.
            for (final d in _jsDelays) {
              if (json != null && json.isNotEmpty) break;
              await Future<void>.delayed(d);
              json = await _readPayload(c);
            }
            if (!done.isCompleted) {
              done.complete(WebViewExtraction(
                payloadJson: (json != null && json.isNotEmpty) ? json : null,
                mediaUrl: mediaUrl,
                finalUrl: finalUrl?.toString(),
              ));
            }
          } catch (e, s) {
            AppLogger.instance.error('tiktok-web', 'loadStop JS failed', e, s);
            if (!done.isCompleted) {
              done.complete(WebViewExtraction(
                mediaUrl: mediaUrl,
                finalUrl: finalUrl?.toString(),
              ));
            }
          }
        },
      );

      await headless.run();
      final result = await done.future.timeout(timeout, onTimeout: () {
        AppLogger.instance.error(
            'tiktok-web', 'timeout after ${timeout.inSeconds}s', null, null);
        return WebViewExtraction(mediaUrl: mediaUrl);
      });
      return result.isEmpty ? null : result;
    } catch (e, s) {
      // WebView unavailable on this device or plugin error — the caller
      // has cheaper fallbacks and the player shows a real error anyway.
      AppLogger.instance.error('tiktok-web', 'extract failed: $e', e, s);
      return null;
    } finally {
      try {
        await headless?.dispose();
      } catch (_) {}
    }
  }

  Future<String?> _readPayload(InAppWebViewController c) async {
    final v = await c.evaluateJavascript(source: _payloadJs);
    if (v == null) return null;
    if (v is String) {
      // Plugin may return the text JSON-encoded with surrounding quotes.
      final t = v.trim();
      if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
        return _unquote(t);
      }
      return t.isEmpty ? null : t;
    }
    return v.toString();
  }

  static String _unquote(String s) {
    // Strip one level of JSON string quoting without extra deps.
    final body = s.substring(1, s.length - 1);
    return body
        .replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'),
            (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\n', '\n');
  }

  /// True for TikTok video CDN requests observed during playback.
  static bool looksLikeVideoUrl(String url) {
    if (!url.startsWith('http')) return false;
    final lower = url.toLowerCase();
    if (lower.contains('blob:') || lower.contains('.m3u8') ||
        lower.contains('.mpd')) {
      return false;
    }
    final isTikTokCdn = lower.contains('tiktokcdn') ||
        lower.contains('tiktok.com') ||
        lower.contains('akamaized.net') ||
        lower.contains('byteoversea') ||
        lower.contains('muscdn') ||
        lower.contains('musical.ly');
    if (!isTikTokCdn) return false;
    return lower.contains('/video/tos/') ||
        lower.contains('mime_type=video_mp4') ||
        lower.contains('.mp4');
  }

  static bool _payloadSeen(Set<String> seen, String? mediaUrl) =>
      mediaUrl != null;

  /// Reads TikTok's embedded state payload from the rendered DOM.
  static const _payloadJs =
      '(function(){'
      'var el = document.getElementById("__UNIVERSAL_DATA_FOR_REHYDRATION__");'
      'if (!el) el = document.getElementById("SIGI_STATE");'
      'return el ? el.textContent : "";'
      '})()';
}
