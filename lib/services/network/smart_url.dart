/// Smart URL analysis for the platforms feature (v1.3.0).
///
/// Pure functions only — no network, no Flutter — so the whole module is
/// unit-testable. Used by:
///  - share/view intents ("open this link with DRS Video")
///  - clipboard quick-play
///  - the add-link dialog / smart open flow
///  - YouTube detection before handing off to [YouTubeResolver]
library;

/// Stream kind detected for a URL.
enum SmartUrlKind {
  /// HTTP Live Streaming playlist (.m3u8/.m3u) or YouTube live.
  hls,

  /// MPEG-DASH manifest (.mpd).
  dash,

  /// Raw streaming protocol (rtsp/rtmp/rtmps/mms).
  rtspRtmp,

  /// FTP/FTPS/SFTP resource.
  ftp,

  /// Progressive/direct media file (mp4, mkv, webm, ...) or unknown
  /// extension behind http(s) — mpv probes the real container anyway.
  direct,
}

/// Result of analyzing a shared/pasted URL.
class SmartUrl {
  SmartUrl._();

  /// Matches the first http(s)/rtsp/rtmp(s)/mms/ftp(s)/sftp URL inside
  /// arbitrary shared text (share sheets often add a title or the app
  /// name around the link).
  static final RegExp _urlInText = RegExp(
    r'(?:https?|rtsp|rtmps?|mms|ftps?|sftp)://[^\s<>"\u0600-\u06FF]+',
    caseSensitive: false,
  );

  /// Extracts the first media URL from arbitrary text; null when the text
  /// contains no URL at all.
  static String? extractUrlFromText(String text) {
    final m = _urlInText.firstMatch(text.trim());
    if (m == null) return null;
    var url = m.group(0)!;
    // Trailing punctuation from sentences is common in shared text.
    while (url.isNotEmpty && '.,;:!?)\u060C'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    return url.isEmpty ? null : url;
  }

  /// True when the scheme is accepted from share/view intents.
  static bool hasSupportedScheme(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return false;
    const schemes = {
      'http', 'https', 'rtsp', 'rtmp', 'rtmps', 'mms', 'ftp', 'ftps', 'sftp',
    };
    return schemes.contains(uri.scheme.toLowerCase());
  }

  /// True when the URL is a YouTube watch/short/embed/youtu.be link.
  static bool isYouTube(String url) => extractYouTubeId(url) != null;

  static final RegExp _ytHost = RegExp(
    r'^(?:www\.|m\.|music\.)?youtube\.com$|^youtu\.be$|^youtube-nocookie\.com$',
    caseSensitive: false,
  );

  /// Extracts the 11-char video id from common YouTube URL forms:
  /// watch?v=, /watch/, youtu.be/, /shorts/, /embed/, /live/.
  static String? extractYouTubeId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return null;
    if (!_ytHost.hasMatch(uri.host)) return null;

    // youtu.be/<id>
    if (uri.host.toLowerCase() == 'youtu.be') {
      final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return _validId(seg.isEmpty ? null : seg.first);
    }

    final q = uri.queryParameters['v'];
    if (q != null) return _validId(q);

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // /shorts/<id>, /embed/<id>, /live/<id>, /v/<id>
    if (segments.length >= 2) {
      const prefixes = {'shorts', 'embed', 'live', 'v'};
      if (prefixes.contains(segments[0].toLowerCase())) {
        return _validId(segments[1]);
      }
    }
    // /watch/<id> (rare but exists)
    if (segments.length >= 2 && segments[0].toLowerCase() == 'watch') {
      return _validId(segments[1]);
    }
    return null;
  }

  static String? _validId(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    // YouTube ids: 11 chars, but be tolerant with separators (#t= etc).
    final clean = v.split(RegExp(r'[?#&/]')).first;
    if (clean.length < 8 || clean.length > 16) return null;
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(clean) ? clean : null;
  }

  /// Classifies a supported URL into its stream kind.
  static SmartUrlKind classify(String url) {
    final clean = url.trim().toLowerCase();
    final uri = Uri.tryParse(clean);
    final path = uri?.path ?? clean;
    final ext = path.contains('.')
        ? path.substring(path.lastIndexOf('.') + 1)
        : '';

    switch (uri?.scheme ?? '') {
      case 'rtsp':
      case 'rtmp':
      case 'rtmps':
      case 'mms':
        return SmartUrlKind.rtspRtmp;
      case 'ftp':
      case 'ftps':
      case 'sftp':
        return SmartUrlKind.ftp;
    }

    if (ext == 'm3u8' || ext == 'm3u') return SmartUrlKind.hls;
    if (ext == 'mpd') return SmartUrlKind.dash;
    return SmartUrlKind.direct;
  }

  /// Human title derived from the URL: file name (decoded) or host.
  static String titleFor(String url) {
    final uri = Uri.tryParse(url.trim());
    final path = uri?.path ?? '';
    final segments = path.split('/').where((s) => s.trim().isNotEmpty).toList();
    if (segments.isNotEmpty) {
      var last = segments.last;
      try {
        last = Uri.decodeComponent(last);
      } catch (_) {
        // Malformed percent-encoding — keep the raw segment.
      }
      if (last.isNotEmpty) return last;
    }
    return uri?.host ?? url;
  }

  /// Friendly source label used in UI hints (e.g. "HLS بث تكيّفي").
  static String kindLabel(SmartUrlKind kind) => switch (kind) {
        SmartUrlKind.hls => 'HLS',
        SmartUrlKind.dash => 'DASH',
        SmartUrlKind.rtspRtmp => 'RTSP/RTMP',
        SmartUrlKind.ftp => 'FTP/SFTP',
        SmartUrlKind.direct => 'HTTP',
      };
}
