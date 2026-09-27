import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/utils/logger.dart';
import 'tiktok_webview_extractor.dart';

/// v1.14.2 per-phase time budgets.
///
/// v1.14.1 killed the WHOLE resolve with one outer 15s timeout while the
/// layers ran sequentially — on networks where tikwm is slow/blocked the
/// budget died on layer 1 and the headless WebView (the only layer that
/// survives anti-bot challenges) NEVER RAN. Now each phase owns its own
/// budget and the API layer races in parallel, so a hanging endpoint can
/// no longer starve the others.

/// How long a resolved TikTok stream stays valid in the cache. TikTok CDN
/// URLs live for hours; after this window the next play re-resolves.
const Duration _cacheTtl = Duration(hours: 6);

/// Result of resolving a TikTok share URL into a real, playable stream.
class TikTokResolved {
  const TikTokResolved({
    required this.videoId,
    required this.title,
    required this.author,
    required this.playUrl,
    this.width,
    this.height,
    this.durationMs,
    this.headers,
  });

  final String videoId;
  final String title;
  final String author;

  /// Direct progressive MP4 (usually watermark-free from the mobile feed
  /// API). mpv plays it natively.
  final String playUrl;

  final int? width;
  final int? height;
  final int? durationMs;

  /// Extra HTTP headers mpv must send (User-Agent/Referer for web-scrape
  /// URLs). Null when the CDN needs none.
  final Map<String, String>? headers;
}

/// Resolves TikTok share links (vm.tiktok.com/... copied from the share
/// sheet, www.tiktok.com/@user/video/123..., m.tiktok.com/...) into direct
/// MP4 URLs.
///
/// Why this exists: a copied TikTok link is an HTML *page*, not media —
/// handing it to mpv fails with "unknown playback error". This resolver
/// performs real extraction through FOUR independent methods, cheapest
/// first:
///
///  1. Mobile feed API (`aweme/v1/feed`) — no-watermark play address.
///  2. Static web page rehydration data (`__UNIVERSAL_DATA_FOR_REHYDRATION__`
///     / legacy `SIGI_STATE`) — needs UA/Referer headers for the CDN.
///  3. tikwm.com public resolver API — third-party free service.
///  4. Headless WebView (v1.4.2) — a real browser engine renders the page
///     and we read the same payload or capture the video CDN request. This
///     survives the anti-bot challenges that break plain HTTP fetches.
///
/// Every failure returns null — the caller falls back to direct playback
/// and the player surfaces the real error; this module never throws.
class TikTokResolver {
  TikTokResolver._();

  static final TikTokResolver instance = TikTokResolver._();

  Dio? _dio;
  final _cache = <String, _CacheEntry>{};

  static const _mobileUa =
      'Mozilla/5.0 (Linux; Android 14; SM-S901B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  // ---- pure URL logic (unit-tested, no I/O) ----

  static final RegExp _tikTokHost = RegExp(
    r'^(?:www\.|m\.|vm\.|vt\.|mobile\.)?tiktok\.com$',
    caseSensitive: false,
  );

  static final RegExp _videoIdInPath = RegExp(r'/video/(\d{6,32})');

  /// True for any tiktok.com host (short vm./vt. links included).
  static bool isTikTokUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return false;
    return _tikTokHost.hasMatch(uri.host);
  }

  /// Extracts the numeric video id when the URL already carries it
  /// (`/video/<id>`). Short links need a redirect follow first.
  static String? extractVideoId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final m = _videoIdInPath.firstMatch(uri.path);
    return m?.group(1);
  }

  /// Best-effort title shown in lists while saving; null on failure.
  Future<String?> fetchTitle(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final r = await resolve(url, timeout: timeout);
    return (r == null || r.title.isEmpty) ? null : r.title;
  }

  /// Resolves [url] into a direct stream. Null on any failure — safe to
  /// call from UI paths.
  ///
  /// [timeout] is an outer safety net only; with the v1.14.2 phase budgets
  /// a full deep run (race 8s → page 5s → webview 20s) needs ~33s, so the
  /// download path passes 35s while play paths keep tighter values.
  Future<TikTokResolved?> resolve(
    String url, {
    Duration timeout = const Duration(seconds: 35),
  }) async {
    if (!isTikTokUrl(url)) return null;

    try {
      return await _resolveNow(url).timeout(timeout);
    } catch (e, s) {
      AppLogger.instance.error('tiktok', 'resolve failed: $e', e, s);
      return null;
    }
  }

  /// Mobile feed API nodes. v1.14.2 live check (2026-09-27): api16 answers
  /// HTTP 429 and api22 answers 200-with-empty-body for many regions —
  /// racing several nodes means one dead node costs nothing.
  static const List<String> _feedNodes = [
    'https://api16-normal-c-useast1a.tiktokv.com',
    'https://api22-normal-c-useast2a.tiktokv.com',
    'https://api31-normal-useast1a.tiktokv.com',
  ];

  Future<TikTokResolved?> _resolveNow(String url) async {
    var pageUrl = url.trim();

    // 1) Short links (vm./vt.) redirect to the canonical /video/<id> URL.
    var id = extractVideoId(pageUrl);
    if (id == null) {
      pageUrl = await _followRedirects(pageUrl);
      id = extractVideoId(pageUrl);
    }
    if (id == null) return null;
    final videoId = id; // promoted once — closures can't capture `var id`

    final cached = _cache[id];
    if (cached != null && !cached.isExpired) return cached.value;

    // 2) PHASE 1 — parallel race: tikwm + every feed API node. First
    //    non-null answer wins; the whole phase is capped at 8s. tikwm is
    //    the only endpoint verified alive (region SA included), the feed
    //    nodes fail fast (429/empty <1s) so racing them costs nothing but
    //    rescues regions where tikwm itself is throttled.
    final raced = await raceSuccess<TikTokResolved>([
      () => _resolveViaTikwm(pageUrl),
      for (final node in _feedNodes) () => _resolveViaFeedApi(videoId, node),
    ], budget: const Duration(seconds: 8));
    if (raced != null) {
      _cache[id] = _CacheEntry(raced);
      return raced;
    }

    // 3) PHASE 2 — static web page rehydration data (needs UA/Referer
    //    headers). Own 5s budget so a dead phase can't starve phase 3.
    final viaPage = await _resolveViaWebPage(pageUrl, id)
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (viaPage != null) {
      _cache[id] = _CacheEntry(viaPage);
      return viaPage;
    }

    // 4) PHASE 3 — heavyweight: render the page in a real headless
    //    WebView. This is the path that survives TikTok's anti-bot
    //    challenges because the browser engine executes the page's
    //    JavaScript for real. v1.14.2 guarantees it gets its turn (own
    //    20s budget — under v1.14.1's shared 15s outer kill it never ran
    //    on slow networks).
    final viaWebView = await _resolveViaWebView(pageUrl, id)
        .timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (viaWebView != null) {
      _cache[id] = _CacheEntry(viaWebView);
      return viaWebView;
    }
    return null;
  }

  /// Runs [tasks] CONCURRENTLY and completes with the first non-null
  /// result, or null when every task finishes null/fails or [budget]
  /// elapses. Losers keep running but their result is ignored.
  ///
  /// v1.14.2 core concurrency primitive — replaces the sequential layer
  /// chain that made slow/blocked endpoints starve the working ones.
  static Future<T?> raceSuccess<T>(
    List<Future<T?> Function()> tasks, {
    required Duration budget,
  }) {
    if (tasks.isEmpty) return Future<T?>.value();
    final completer = Completer<T?>();
    var settled = false;
    var pending = tasks.length;

    void settle(T? value) {
      if (settled) return;
      settled = true;
      completer.complete(value);
    }

    Future<void> run(Future<T?> Function() task) async {
      try {
        final value = await task();
        if (value != null) return settle(value);
      } catch (_) {
        // individual racers may fail — the race itself never throws
      }
      pending--;
      if (pending == 0) settle(null);
    }

    Timer(budget, () => settle(null));
    for (final task in tasks) {
      unawaited(run(task));
    }
    return completer.future;
  }

  /// Follows short-link redirects manually so a hostile chain can never
  /// loop: at most 3 hops, always re-checked against tiktok.com, tight
  /// per-hop timeouts (a dead short-link host costs ≤3s per hop).
  Future<String> _followRedirects(String url) async {
    var current = url;
    for (var hop = 0; hop < 3; hop++) {
      final dio = _ensureDio();
      final res = await dio.get<Object?>(
        current,
        options: Options(
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
          responseType: ResponseType.plain,
          headers: {'User-Agent': _mobileUa},
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
      final status = res.statusCode ?? 0;
      final location = res.headers.value('location');
      if ((status == 301 || status == 302 || status == 303 ||
              status == 307 || status == 308) &&
          location != null &&
          location.isNotEmpty) {
        final next = Uri.parse(current).resolve(location).toString();
        if (!isTikTokUrl(next)) return next; // off-domain: stop, caller re-checks
        current = next;
        if (extractVideoId(current) != null) return current;
        continue;
      }
      break;
    }
    return current;
  }

  Future<TikTokResolved?> _resolveViaFeedApi(String id, String node) async {
    try {
      final dio = _ensureDio();
      final res = await dio.get<String>(
        '$node/aweme/v1/feed/',
        queryParameters: {
          'aweme_id': id,
          'version_code': '300904',
          'app_name': 'musical_ly',
          'channel': 'googleplay',
          'device_platform': 'android',
          'device_type': 'SM-S901B',
          'os_version': '14',
          'aid': '1180',
        },
        options: Options(
          responseType: ResponseType.json,
          headers: {'User-Agent': _mobileUa},
          validateStatus: (s) => s != null && s < 500,
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
      final body = res.data;
      if (body == null) return null;
      final dynamic json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      return parseFeedApiJson(json);
    } on DioException catch (e) {
      AppLogger.instance.error('tiktok', 'feed api http ${e.response?.statusMessage}', e, e.stackTrace);
      return null;
    }
  }

  Future<TikTokResolved?> _resolveViaWebPage(String pageUrl, String id) async {
    try {
      final dio = _ensureDio();
      final res = await dio.get<String>(
        pageUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': _desktopUa},
          validateStatus: (s) => s != null && s < 500,
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final html = res.data;
      if (html == null || html.isEmpty) return null;
      final resolved = extractRehydrationPayload(html);
      if (resolved == null) return null;
      return parseWebPagePayload(resolved, id);
    } on DioException catch (e) {
      AppLogger.instance.error('tiktok', 'page fetch failed', e, e.stackTrace);
      return null;
    }
  }

  /// tikwm.com response shape:
  /// `{code: 0, data: {id, title, play, hdplay, author: {nickname}}}`.
  /// `play`/`hdplay` are absolute https URLs or root-relative proxy paths.
  static TikTokResolved? parseTikwmJson(Map<String, dynamic> json) {
    if (json['code'] != 0) return null;
    final data = json['data'];
    if (data is! Map<String, dynamic>) return null;
    final author = data['author'];
    final play = _absoluteTikwm(data['hdplay'] ?? data['play']);
    if (play == null) return null;
    return TikTokResolved(
      videoId: (data['id'] ?? '').toString(),
      title: (data['title'] ?? '').toString().trim(),
      author: author is Map<String, dynamic>
          ? (author['nickname'] ?? '').toString()
          : '',
      playUrl: play,
      durationMs: _asInt(data['duration']),
    );
  }

  static String? _absoluteTikwm(Object? v) {
    final s = v?.toString() ?? '';
    if (s.startsWith('http')) return s;
    if (s.startsWith('/')) return 'https://www.tikwm.com$s';
    return null;
  }

  Future<TikTokResolved?> _resolveViaTikwm(String pageUrl) async {
    try {
      final dio = _ensureDio();
      final res = await dio.get<String>(
        'https://tikwm.com/api/',
        queryParameters: {'url': pageUrl, 'hd': '1'},
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': _mobileUa},
          validateStatus: (s) => s != null && s < 500,
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 7),
        ),
      );
      final body = res.data;
      if (body == null || body.isEmpty) return null;
      final dynamic json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      return parseTikwmJson(json);
    } on DioException catch (e) {
      AppLogger.instance.error('tiktok', 'tikwm http ${e.response?.statusCode}', e, e.stackTrace);
      return null;
    } catch (e, s) {
      AppLogger.instance.error('tiktok', 'tikwm parse failed', e, s);
      return null;
    }
  }

  /// Renders the page in a headless WebView and parses what the real
  /// browser engine produced (payload JSON first, captured CDN URL as
  /// fallback).
  Future<TikTokResolved?> _resolveViaWebView(String pageUrl, String id) async {
    try {
      final extraction = await TikTokWebViewExtractor.instance.extract(pageUrl);
      if (extraction == null) return null;

      if (extraction.payloadJson != null) {
        try {
          final dynamic decoded = jsonDecode(extraction.payloadJson!);
          if (decoded is Map<String, dynamic>) {
            final parsed = parseWebPagePayload(decoded, id);
            if (parsed != null) return parsed;
          }
        } catch (e, s) {
          AppLogger.instance.error('tiktok', 'webview payload parse failed', e, s);
        }
      }

      final media = extraction.mediaUrl;
      if (media != null && media.startsWith('http')) {
        return TikTokResolved(
          videoId: id,
          title: '',
          author: '',
          playUrl: media,
          headers: const {
            'User-Agent': _desktopUa,
            'Referer': 'https://www.tiktok.com/',
          },
        );
      }
      return null;
    } catch (e, s) {
      AppLogger.instance.error('tiktok', 'webview resolve failed', e, s);
      return null;
    }
  }

  Dio _ensureDio() {
    // v1.14.2: the base timeouts are deliberately generous (WebView-ish
    // callers) — every racing call overrides them per-Options above.
    _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 8),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (s) => s != null && s < 500,
    ));
    return _dio!;
  }

  // ---- pure parsers (unit-tested; no I/O below this line) ----

  /// Mobile feed API shape:
  /// `aweme_list[0].video.play_addr.url_list[]` + `desc` + `author.nickname`.
  static TikTokResolved? parseFeedApiJson(Map<String, dynamic> json) {
    final list = json['aweme_list'];
    if (list is! List || list.isEmpty) return null;
    final first = list.first;
    if (first is! Map<String, dynamic>) return null;
    final video = first['video'];
    if (video is! Map<String, dynamic>) return null;
    final playAddr = video['play_addr'];
    if (playAddr is! Map<String, dynamic>) return null;
    final urls = playAddr['url_list'];
    if (urls is! List || urls.isEmpty) return null;
    final url = urls.whereType<String>().firstWhere(
          (u) => u.startsWith('http'),
          orElse: () => '',
        );
    if (url.isEmpty) return null;

    final author = first['author'];
    return TikTokResolved(
      videoId: (first['aweme_id'] ?? '').toString(),
      title: (first['desc'] ?? '').toString().trim(),
      author: author is Map<String, dynamic>
          ? (author['nickname'] ?? '').toString()
          : '',
      playUrl: url,
      width: _asInt(video['width']),
      height: _asInt(video['height']),
      durationMs: _asInt(video['duration']),
    );
  }

  /// Finds the rehydration JSON inside a TikTok page: prefers the current
  /// `__UNIVERSAL_DATA_FOR_REHYDRATION__` script, falls back to the legacy
  /// `SIGI_STATE` script. Returns the decoded map, or null.
  static Map<String, dynamic>? extractRehydrationPayload(String html) {
    Map<String, dynamic>? decoded = _scriptJson(html,
        'id="__UNIVERSAL_DATA_FOR_REHYDRATION__"');
    if (decoded != null) return decoded;
    decoded = _scriptJson(html, "id='__UNIVERSAL_DATA_FOR_REHYDRATION__'");
    if (decoded != null) return decoded;
    decoded = _scriptJson(html, 'id="SIGI_STATE"');
    if (decoded != null) return decoded;
    decoded = _scriptJson(html, "id='SIGI_STATE'");
    return decoded;
  }

  static Map<String, dynamic>? _scriptJson(String html, String marker) {
    final markerIdx = html.indexOf(marker);
    if (markerIdx < 0) return null;
    final open = html.indexOf('>', markerIdx);
    final close = html.indexOf('</script>', open);
    if (open < 0 || close < 0 || close <= open) return null;
    try {
      final raw = html.substring(open + 1, close);
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Web page payload — current universal shape:
  /// `__DEFAULT_SCOPE__['webapp.video-detail'].itemInfo.itemStruct`.
  static TikTokResolved? parseWebPagePayload(
      Map<String, dynamic> payload, String videoId) {
    final scope = payload['__DEFAULT_SCOPE__'];
    if (scope is Map<String, dynamic>) {
      final detail = scope['webapp.video-detail'];
      if (detail is Map<String, dynamic>) {
        final itemInfo = detail['itemInfo'];
        if (itemInfo is Map<String, dynamic>) {
          final itemStruct = itemInfo['itemStruct'];
          if (itemStruct is Map<String, dynamic>) {
            return _fromItemStruct(itemStruct, videoId);
          }
        }
      }
    }
    // Legacy SIGI_STATE shape: `ItemModule[id].video`.
    final module = payload['ItemModule'];
    if (module is Map<String, dynamic>) {
      final item = module[videoId];
      if (item is Map<String, dynamic>) return _fromItemStruct(item, videoId);
    }
    return null;
  }

  static TikTokResolved? _fromItemStruct(
      Map<String, dynamic> item, String videoId) {
    final video = item['video'];
    if (video is! Map<String, dynamic>) return null;
    final addr = (video['playAddr'] ?? video['downloadAddr'] ?? '').toString();
    if (!addr.startsWith('http')) return null;
    final author = item['author'];
    return TikTokResolved(
      videoId: videoId,
      title: (item['desc'] ?? '').toString().trim(),
      author: author is Map<String, dynamic>
          ? (author['nickname'] ?? '').toString()
          : '',
      playUrl: addr,
      width: _asInt(video['width']),
      height: _asInt(video['height']),
      durationMs: _asInt(video['duration']),
      headers: const {
        'User-Agent': _desktopUa,
        'Referer': 'https://www.tiktok.com/',
      },
    );
  }

  static int? _asInt(Object? v) =>
      v == null ? null : (v is int ? v : int.tryParse(v.toString()));
}

class _CacheEntry {
  _CacheEntry(this.value);
  final TikTokResolved value;
  final DateTime at = DateTime.now();

  bool get isExpired => DateTime.now().difference(at) > _cacheTtl;
}
