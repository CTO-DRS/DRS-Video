import 'package:flutter/services.dart' show rootBundle;

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

/// Real ad/tracker blocker for the built-in browser.
///
/// Layer 1 (this class): bundled domain list (StevenBlack unified hosts,
/// MIT) loaded into a HashSet — O(1) subdomain matching per request via
/// the WebView's `shouldInterceptRequest` hook.
///
/// The blocklist file is parsed lazily and can be reloaded; matching is
/// a pure static function so it is unit-testable without the asset.
class AdBlockList {
  AdBlockList._();
  static final AdBlockList instance = AdBlockList._();

  Set<String>? _domains;
  int _loadedCount = 0;

  int get domainCount => _loadedCount;
  bool get isLoaded => _domains != null;

  /// Loads (once) the bundled blocklist. Never throws.
  Future<bool> ensureLoaded() async {
    if (_domains != null) return true;
    try {
      final raw = await rootBundle.loadString(AppConstants.adBlockAsset);
      _domains = _parse(raw);
      _loadedCount = _domains!.length;
      AppLogger.instance
          .info('adblock', 'loaded $_loadedCount blocked domains');
      return true;
    } catch (e, s) {
      AppLogger.instance.error('adblock', 'blocklist load failed', e, s);
      _domains = const {};
      _loadedCount = 0;
      return false;
    }
  }

  /// Pure parser: one domain per line, '#' comments tolerated.
  static Set<String> _parse(String raw) {
    final out = <String>{};
    for (var line in raw.split('\n')) {
      line = line.trim().toLowerCase();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.contains(' ')) line = line.split(' ').last;
      if (line.contains('.') && !line.startsWith('.')) out.add(line);
    }
    return out;
  }

  /// Pure matcher: true when [host] is the domain itself or a subdomain.
  static bool matches(Set<String> domains, String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return false;
    if (domains.contains(h)) return true;
    // Strip one label at a time: a.b.evil.com -> b.evil.com -> evil.com.
    var rest = h;
    while (true) {
      final dot = rest.indexOf('.');
      if (dot < 0 || dot == rest.length - 1) return false;
      rest = rest.substring(dot + 1);
      if (domains.contains(rest)) return true;
    }
  }

  /// True when this request host must be blocked.
  Future<bool> shouldBlock(String host) async {
    await ensureLoaded();
    return matches(_domains ?? const {}, host);
  }
}

/// Pure URL/UA helpers for the built-in browser (unit-tested).
class BrowserUtils {
  BrowserUtils._();

  /// Normalizes user input into a URL. Bare domains get https://;
  /// text with spaces or without any dot is treated as a DuckDuckGo
  /// search (privacy-respecting engine, no tracking profile).
  static String normalizeUrl(String input) {
    final t = input.trim();
    if (t.isEmpty) return '';
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(t);
    if (hasScheme) return t;
    final looksLikeHost =
        !t.contains(' ') && t.contains('.') && !t.endsWith('.');
    if (looksLikeHost) return 'https://$t';
    return 'https://duckduckgo.com/?q=${Uri.encodeComponent(t)}';
  }

  /// Extracts the host of a URL string ('' when invalid).
  static String hostOf(String url) {
    try {
      return Uri.parse(url).host.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  /// True when the URL points at a directly playable video stream.
  static bool isMediaStreamUrl(String url) {
    final clean = url.split('?').first.split('#').first.toLowerCase();
    for (final ext in AppConstants.streamFileExtensions) {
      if (clean.endsWith('.$ext')) return true;
    }
    return false;
  }

  /// True for pages that contain a YouTube watchable video (reuse of the
  /// native resolver's detection keeps a single source of truth).
  static bool isYouTubeWatchUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return false;
    final host = u.host.toLowerCase().replaceAll('www.', '');
    if (host == 'youtu.be') return true;
    if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
      return u.path.startsWith('/watch') ||
          u.path.startsWith('/shorts/') ||
          u.path.startsWith('/embed/') ||
          u.path.startsWith('/live/');
    }
    return false;
  }

  /// Labels for the detected-streams sheet.
  static String streamKindLabel(String url) {
    final clean = url.split('?').first.toLowerCase();
    if (clean.endsWith('.m3u8')) return 'HLS';
    if (clean.endsWith('.mpd')) return 'DASH';
    if (clean.endsWith('.mp4') || clean.endsWith('.m4v')) return 'MP4';
    if (clean.endsWith('.webm')) return 'WebM';
    return 'FILE';
  }
}
