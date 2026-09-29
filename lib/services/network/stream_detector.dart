import 'package:flutter/foundation.dart';

/// How a network URL is delivered to the player.
enum StreamKind { hls, dash, progressive, unknown }

/// Pure, deterministic classification of streaming URLs.
///
/// libmpv (media_kit) plays HLS and DASH natively, so the app only needs to
/// KNOW what kind of stream it is facing to:
///   * show the right badge while the user types a URL,
///   * mark the resulting [MediaItem] as live (`liveHint`) so the player
///     skips resume/progress persistence for live channels,
///   * pick sensible titles.
///
/// No network I/O happens here — everything derives from the URL string and
/// an optional content-type reported by a HEAD probe, keeping the class
/// trivially unit-testable.
class StreamDetector {
  StreamDetector._();

  static const _hlsExtensions = ['m3u8', 'm3u'];
  static const _dashExtensions = ['mpd'];
  static const _progressiveExtensions = [
    'mp4', 'm4v', 'mkv', 'webm', 'mov', 'avi', 'ts', 'flv', '3gp', 'ogv',
  ];

  /// Substrings that, when present in the URL path/host or the content-type,
  /// strongly suggest a LIVE stream rather than on-demand (VOD) content.
  static const _liveKeywords = [
    'live', '/hls/', 'chunklist', 'playlist.m3u8', 'index.m3u8',
    'master.m3u8', 'manifest', 'event', 'chunked',
  ];

  /// Classifies by URL shape only. Query strings and fragments are ignored
  /// (e.g. `https://cdn.io/live/master.m3u8?token=x` is still HLS).
  static StreamKind classifyUrl(String url) {
    final path = _pathOf(url);
    final ext = _extensionOf(path);
    if (_hlsExtensions.contains(ext)) return StreamKind.hls;
    if (_dashExtensions.contains(ext)) return StreamKind.dash;
    if (_progressiveExtensions.contains(ext)) return StreamKind.progressive;
    return StreamKind.unknown;
  }

  /// Classifies by the HTTP Content-Type of a probe response.
  /// Handles parameters (`application/x-mpegurl; charset=utf-8`).
  static StreamKind classifyContentType(String? contentType) {
    if (contentType == null || contentType.isEmpty) return StreamKind.unknown;
    final ct = contentType.toLowerCase().split(';').first.trim();
    if (ct.contains('mpegurl')) return StreamKind.hls;
    if (ct.contains('dash+xml')) return StreamKind.dash;
    if (ct.startsWith('video/') || ct.startsWith('audio/')) {
      return StreamKind.progressive;
    }
    return StreamKind.unknown;
  }

  /// True when URL or content-type contains strong live-stream markers.
  static bool hasLiveKeyword(String url, [String? contentType]) {
    final haystack = '${_pathOf(url)} ${contentType ?? ''}'.toLowerCase();
    return _liveKeywords.any(haystack.contains);
  }

  /// The decision used by MediaActions: should this item be treated as live?
  ///
  /// Rules (first match wins, all deterministic):
  ///  1. HLS/DASH + live keyword                          → live
  ///  2. HLS/DASH + probe returned no size at all          → live (a VOD
  ///     manifest file virtually always has a content-length)
  ///  3. anything else                                     → not live
  static bool isLiveLike({
    required String url,
    String? contentType,
    int? sizeBytes,
    bool resumable = false,
  }) {
    var kind = classifyUrl(url);
    if (kind == StreamKind.unknown) kind = classifyContentType(contentType);
    if (kind != StreamKind.hls && kind != StreamKind.dash) return false;
    if (hasLiveKeyword(url, contentType)) return true;
    if (sizeBytes == null && !resumable) return true;
    return false;
  }

  /// Human-facing badge key for the open-URL sheet: null means "nothing
  /// interesting detected" and the UI hides the chip.
  static StreamKind? badgeFor(String url) {
    final kind = classifyUrl(url);
    return kind == StreamKind.unknown ? null : kind;
  }

  // ---- helpers -----------------------------------------------------------

  static String _pathOf(String url) {
    final withoutScheme =
        url.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    final noQuery = withoutScheme.split(RegExp('[?#]')).first;
    return noQuery;
  }

  static String _extensionOf(String path) {
    final lastSegment = path.split('/').where((s) => s.isNotEmpty).lastOrNull;
    if (lastSegment == null) return '';
    final dot = lastSegment.lastIndexOf('.');
    if (dot <= 0 || dot == lastSegment.length - 1) return '';
    return lastSegment.substring(dot + 1).toLowerCase();
  }

  @visibleForTesting
  static String pathForTesting(String url) => _pathOf(url);

  @visibleForTesting
  static String extensionForTesting(String path) => _extensionOf(path);
}
