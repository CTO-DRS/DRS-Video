import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/utils/logger.dart';

/// Resolves social-network share links (Facebook videos/reels and
/// Twitter/X statuses) into direct, playable media URLs.
///
/// Same contract as [TikTokResolver]: copied links are HTML pages, never
/// media, so mpv needs a real stream URL first.
///
/// Channels:
/// - Twitter/X: public syndication JSON (cdn.syndication.twimg.com), then
///   the fxtwitter mirror API. Best-bitrate MP4 variant wins.
/// - Facebook: mobile page fetch with a real UA; scrape
///   browser_native_hd_url / browser_native_sd_url / hd_src / sd_src /
///   og:video. HD preferred.
///
/// All JSON parsing lives in PURE static functions (unit-tested). The
/// network wrapper NEVER throws — failures return null and the player
/// reports the real error (or the user falls back to the in-app browser).
class SocialResolver {
  SocialResolver._();

  static final SocialResolver instance = SocialResolver._();

  Dio? _dio;
  final _cache = <String, _CacheEntry>{};

  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const _mobileUa =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  static const _cacheTtl = Duration(hours: 6);

  Dio _ensureDio() {
    _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (s) => s != null && s < 400,
    ));
    return _dio!;
  }

  // ------------------------------------------------------------------
  // URL detection (pure)
  // ------------------------------------------------------------------

  static final RegExp _fbHosts =
      RegExp(r'^(?:[a-z0-9-]+\.)*(?:facebook\.com|fb\.watch|fb\.me)$');
  static final RegExp _twHosts = RegExp(r'^(?:[a-z0-9-]+\.)*(?:twitter\.com|x\.com|t\.co)$');

  static bool isFacebookUrl(String url) {
    final host = _hostOf(url);
    return host != null && _fbHosts.hasMatch(host);
  }

  static bool isTwitterUrl(String url) {
    final host = _hostOf(url);
    return host != null && _twHosts.hasMatch(host);
  }

  static bool isSocialUrl(String url) =>
      isFacebookUrl(url) || isTwitterUrl(url);

  static String? _hostOf(String url) {
    try {
      return Uri.parse(url.trim()).host.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  /// Numeric status id from twitter.com/<user>/status/<id> forms.
  static String? extractTweetId(String url) {
    final m = RegExp(r'/(?:status|statuses)/(\d{8,20})').firstMatch(url);
    return m?.group(1);
  }

  /// Best-effort display title from a social URL (page/reel id fragments).
  static String fallbackTitle(String url) {
    if (isFacebookUrl(url)) {
      final reel = RegExp(r'/reel[s]?/(\d+)').firstMatch(url);
      if (reel != null) return 'Facebook Reel ${reel.group(1)}';
      final watch = RegExp(r'/watch/?\?v=(\d+)').firstMatch(url);
      if (watch != null) return 'Facebook Video ${watch.group(1)}';
      return 'Facebook Video';
    }
    final id = extractTweetId(url);
    return id != null ? 'X Video $id' : 'X Video';
  }

  // ------------------------------------------------------------------
  // Pure JSON/HTML parsers (unit-tested)
  // ------------------------------------------------------------------

  /// Picks the highest-bitrate MP4 variant from syndication tweet JSON.
  /// Shape: mediaDetails[].video_info.variants[] = {bitrate, content_type, url}.
  static SocialResolved? parseSyndicationJson(String body, {required String pageUrl}) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, Object?>) return null;
      final media = json['mediaDetails'];
      if (media is! List || media.isEmpty) return null;

      String? bestUrl;
      int bestBitrate = -1;
      int? width;
      int? height;
      for (final m in media) {
        if (m is! Map<String, Object?>) continue;
        final info = m['video_info'];
        if (info is! Map<String, Object?>) continue;
        final w = info['width'];
        final h = info['height'];
        if (w is int) width = w;
        if (h is int) height = h;
        final variants = info['variants'];
        if (variants is! List) continue;
        for (final v in variants) {
          if (v is! Map<String, Object?>) continue;
          final ct = v['content_type'];
          if (ct is! String || !ct.contains('mp4')) continue;
          final url = v['url'];
          if (url is! String || url.isEmpty) continue;
          final br = v['bitrate'];
          final bitrate = br is int ? br : 0;
          if (bitrate > bestBitrate) {
            bestBitrate = bitrate;
            bestUrl = url;
          }
        }
      }
      if (bestUrl == null) return null;

      final user = json['user'];
      final author = user is Map<String, Object?> ? user['name'] as String? : null;
      final text = json['text'] as String?;
      return SocialResolved(
        playUrl: bestUrl,
        title: (text != null && text.trim().isNotEmpty)
            ? (text.length > 80 ? '${text.substring(0, 80)}…' : text)
            : fallbackTitle(pageUrl),
        author: author,
        width: width,
        height: height,
        headers: const {'User-Agent': _desktopUa, 'Referer': 'https://x.com/'},
      );
    } catch (_) {
      return null;
    }
  }

  /// fxtwitter mirror: tweet.media.all/videos[] = {url, type}.
  static SocialResolved? parseFxtwitterJson(String body, {required String pageUrl}) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, Object?>) return null;
      final tweet = json['tweet'];
      if (tweet is! Map<String, Object?>) return null;
      final media = tweet['media'];
      if (media is! Map<String, Object?>) return null;

      final videos = media['videos'];
      final List? list = videos is List ? videos : (media['all'] is List ? media['all'] as List : null);
      if (list == null || list.isEmpty) return null;

      String? bestUrl;
      int bestBitrate = -1;
      int? width;
      int? height;
      for (final v in list) {
        if (v is! Map<String, Object?>) continue;
        final type = v['type'];
        final url = v['url'];
        if (url is! String || url.isEmpty) continue;
        final isVideo = (type is String && type == 'video') ||
            url.contains('.mp4') ||
            url.contains('video');
        if (!isVideo) continue;
        final br = v['bitrate'];
        final bitrate = br is int ? br : 0;
        if (bitrate > bestBitrate) {
          bestBitrate = bitrate;
          bestUrl = url;
          final w = v['width'];
          final h = v['height'];
          if (w is int) width = w;
          if (h is int) height = h;
        }
      }
      if (bestUrl == null) return null;

      final author = tweet['author'];
      final authorName =
          author is Map<String, Object?> ? author['name'] as String? : null;
      final text = tweet['text'] as String?;
      return SocialResolved(
        playUrl: bestUrl,
        title: (text != null && text.trim().isNotEmpty)
            ? (text.length > 80 ? '${text.substring(0, 80)}…' : text)
            : fallbackTitle(pageUrl),
        author: authorName,
        width: width,
        height: height,
        headers: const {'User-Agent': _desktopUa, 'Referer': 'https://x.com/'},
      );
    } catch (_) {
      return null;
    }
  }

  /// Scrapes a playable URL out of a Facebook mobile HTML page.
  static SocialResolved? parseFacebookHtml(String html, {required String pageUrl}) {
    if (html.isEmpty) return null;

    // Priority: native HD > native SD > legacy hd_src > sd_src > og:video.
    final candidates = <String?>[
      for (final key in const [
        'browser_native_hd_url',
        'browser_native_sd_url',
        'hd_src_no_ratelimit',
        'hd_src',
        'sd_src_no_ratelimit',
        'sd_src',
        'videoUrl',
      ])
        _extractJsonString(html, key),
      _extractMeta(html, 'og:video:secure_url'),
      _extractMeta(html, 'og:video:url'),
      _extractMeta(html, 'og:video'),
    ].whereType<String>().toList();

    for (final url in candidates) {
      if (url.startsWith('http') &&
          (url.contains('.mp4') || url.contains('video') || url.contains('fbcdn'))) {
        final title = _extractMeta(html, 'og:title') ?? fallbackTitle(pageUrl);
        return SocialResolved(
          playUrl: url.replaceAll('\\/', '/').replaceAll('\\u0025', '%'),
          title: title,
          author: null,
          width: null,
          height: null,
          headers: {
            'User-Agent': _mobileUa,
            'Referer': 'https://m.facebook.com/',
          },
        );
      }
    }
    return null;
  }

  static String? _extractJsonString(String html, String key) {
    // Matches "key":"..." with escaped characters kept simple (mp4 URLs
    // rarely contain raw quotes; escapes are unescaped below).
    final idx = html.indexOf('"$key"');
    if (idx < 0) return null;
    final colon = html.indexOf(':', idx + key.length + 2);
    if (colon < 0) return null;
    final open = html.indexOf('"', colon);
    if (open < 0) return null;
    final buf = StringBuffer();
    var i = open + 1;
    while (i < html.length) {
      final c = html[i];
      if (c == '\\') {
        if (i + 1 < html.length) {
          buf.write(html[i + 1]);
          i += 2;
          continue;
        }
        break;
      }
      if (c == '"') break;
      buf.write(c);
      i++;
    }
    final v = buf.toString();
    return v.isEmpty ? null : v;
  }

  static String? _extractMeta(String html, String property) {
    final m = RegExp(
      'property=["\']${RegExp.escape(property)}["\'][^>]*content=["\']([^"\']+)["\']',
      caseSensitive: false,
    ).firstMatch(html);
    if (m != null) return m.group(1);
    // content-before-property variant.
    final m2 = RegExp(
      'content=["\']([^"\']+)["\'][^>]*property=["\']${RegExp.escape(property)}["\']',
      caseSensitive: false,
    ).firstMatch(html);
    return m2?.group(1);
  }

  // ------------------------------------------------------------------
  // Network resolution
  // ------------------------------------------------------------------

  /// Resolves a social URL. Returns null on any failure (never throws).
  Future<SocialResolved?> resolve(String url) async {
    final key = url.trim();
    final hit = _cache[key];
    if (hit != null && !hit.isExpired) return hit.value;

    SocialResolved? result;
    try {
      if (isTwitterUrl(key)) {
        result = await _resolveTwitter(key);
      } else if (isFacebookUrl(key)) {
        result = await _resolveFacebook(key);
      }
    } catch (e) {
      AppLogger.instance.warning('social', 'resolve failed for $key: $e');
    }

    if (result != null) {
      _cache[key] = _CacheEntry(result, DateTime.now().add(_cacheTtl));
      AppLogger.instance.info('social',
          'resolved ${isTwitterUrl(key) ? 'twitter' : 'facebook'} link OK');
    }
    return result;
  }

  Future<SocialResolved?> _resolveTwitter(String url) async {
    final id = extractTweetId(url);
    if (id == null) return null;
    final dio = _ensureDio();

    // 1) Public syndication endpoint (no auth).
    try {
      final r = await dio.get<Object>(
        'https://cdn.syndication.twimg.com/tweet-result',
        queryParameters: {'id': id, 'token': 'x', 'lang': 'en'},
        options: Options(headers: {'User-Agent': _desktopUa}),
      );
      final body = r.data is String ? r.data as String : jsonEncode(r.data);
      final parsed = parseSyndicationJson(body, pageUrl: url);
      if (parsed != null) return parsed;
    } on DioException catch (e) {
      AppLogger.instance.warning('social',
          'syndication failed: ${e.response?.statusCode}');
    }

    // 2) fxtwitter mirror.
    try {
      final r = await dio.get<Object>('https://api.fxtwitter.com/status/$id',
          options: Options(headers: {'User-Agent': _desktopUa}));
      final body = r.data is String ? r.data as String : jsonEncode(r.data);
      return parseFxtwitterJson(body, pageUrl: url);
    } on DioException catch (e) {
      AppLogger.instance.warning('social',
          'fxtwitter failed: ${e.response?.statusCode}');
      return null;
    }
  }

  Future<SocialResolved?> _resolveFacebook(String url) async {
    final dio = _ensureDio();

    // Short links (fb.watch) already redirect via followRedirects.
    // Prefer the mobile site: lighter DOM, fewer login walls.
    for (final base in [
      url.replaceFirst('//www.facebook.com', '//m.facebook.com'),
      url,
    ]) {
      try {
        final r = await dio.get<String>(base,
            options: Options(headers: {
              'User-Agent': _mobileUa,
              'Accept-Language': 'en-US,en;q=0.9',
            }));
        final html = r.data ?? '';
        final parsed = parseFacebookHtml(html, pageUrl: url);
        if (parsed != null) return parsed;
      } on DioException catch (e) {
        AppLogger.instance.warning(
            'social', 'fb page failed (${e.response?.statusCode})');
      }
    }
    return null;
  }

  /// Best-effort title fetch (used when registering a link as a library
  /// item before playback).
  Future<String?> fetchTitle(String url) async {
    try {
      if (isTwitterUrl(url)) {
        final id = extractTweetId(url);
        if (id == null) return null;
        final dio = _ensureDio();
        final r = await dio.get<Object>('https://api.fxtwitter.com/status/$id',
            options: Options(headers: {'User-Agent': _desktopUa}));
        final body = r.data is String ? r.data as String : jsonEncode(r.data);
        return parseFxtwitterJson(body, pageUrl: url)?.title;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class SocialResolved {
  const SocialResolved({
    required this.playUrl,
    required this.title,
    required this.author,
    required this.width,
    required this.height,
    required this.headers,
  });

  final String playUrl;
  final String title;
  final String? author;
  final int? width;
  final int? height;
  final Map<String, String> headers;
}

class _CacheEntry {
  _CacheEntry(this.value, this.expiresAt);

  final SocialResolved value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
