import '../network/social_resolver.dart';
import '../network/tiktok_resolver.dart';
import '../network/youtube_resolver.dart';
import '../smart/intel_v4.dart';

/// A platform share link (TikTok / X / Facebook) resolved into the real
/// media URL that the download engine can fetch.
class ResolvedPlatformMedia {
  const ResolvedPlatformMedia({
    required this.directUrl,
    required this.headers,
    this.title,
    this.platform,
  });

  final String directUrl;

  /// HTTP headers the CDN requires (User-Agent/Referer for web-scrape
  /// addresses). Empty for header-free CDN URLs (TikTok feed/tikwm).
  final Map<String, String> headers;

  /// Best-effort display title (TikTok description / tweet text).
  final String? title;

  final String? platform;
}

/// v1.14.1 — the missing link between the downloads feature and the
/// platform resolvers.
///
/// Root cause of "TikTok download saves a .txt document instead of the
/// video": a copied share link (`vt.tiktok.com/...`) is an HTML *page*, and
/// the download pipeline used to probe/enqueue that page URL verbatim —
/// so the engine downloaded the page markup and named it after the page's
/// content-type (text/html → document). The same applies to X/Facebook
/// share links and explains "downloads do not work from platforms".
///
/// [resolve] turns the page URL into the direct MP4/MP4-variant URL (with
/// the headers the CDN expects) BEFORE any probe/enqueue happens, and the
/// pure helpers below enforce the iron rule: page-like responses are never
/// saved as media.
class PlatformDownloadResolver {
  PlatformDownloadResolver._();

  static final PlatformDownloadResolver instance =
      PlatformDownloadResolver._();

  /// Pure: true when [url] is a platform page link we know how to resolve.
  /// v1.14.3: YouTube watch/shorts/youtu.be links included — they were the
  /// last big class of pasted links that could NEVER download (the probe
  /// saw youtube.com's HTML page and the guard rejected it).
  /// (Instagram/reddit etc. intentionally excluded — no working resolver.)
  static bool needsResolution(String url) =>
      TikTokResolver.isTikTokUrl(url) ||
      SocialResolver.isSocialUrl(url) ||
      YouTubeResolver.isYouTubeUrl(url);

  /// v1.14.3 pure download policy for a resolved YouTube video: a
  /// downloadable task needs a single progressive (muxed) file. Live
  /// streams are HLS manifests and DASH-only videos have no muxed stream —
  /// both are honest failures, never garbage downloads.
  static ResolvedPlatformMedia? mediaFromYouTube({
    required bool isLive,
    required String? muxedUrl,
    required String title,
  }) {
    if (isLive || muxedUrl == null || muxedUrl.isEmpty) return null;
    final t = title.trim();
    return ResolvedPlatformMedia(
      directUrl: muxedUrl,
      headers: const {},
      title: t.isEmpty ? null : t,
      platform: 'youtube',
    );
  }

  /// Pure: page-like MIME types that must never be saved as downloaded
  /// media. These responses mean "this URL is a web page" — either
  /// extraction failed or the link was never a direct file.
  static bool isPageLikeMime(String? contentType) {
    if (contentType == null || contentType.isEmpty) return false;
    final mime = contentType.toLowerCase().split(';').first.trim();
    return mime == 'text/html' ||
        mime == 'application/xhtml+xml' ||
        mime == 'application/json' ||
        mime == 'text/json';
  }

  /// Pure: the user explicitly asked to save a web page (URL carries an
  /// .html/.htm extension) — the HTML guard must not block that.
  static bool hasPageExtension(String url) {
    final ext = DownloadClassifier.extensionOf(url);
    return ext == 'html' || ext == 'htm' || ext == 'xhtml';
  }

  /// Pure: the download-engine gate. Blocks the exact failure users saw
  /// (HTML page saved as .txt/.html "video") while keeping explicit page
  /// saves and header-less probes (probe failed → mime null) working.
  static bool shouldAbortAsPageSave({
    required String? contentType,
    required String url,
  }) {
    if (hasPageExtension(url)) return false;
    return isPageLikeMime(contentType);
  }

  /// Resolves a platform page link into direct media. Returns null when
  /// the URL is not a platform link (nothing to do) or extraction failed
  /// (callers abort with a clear error instead of saving garbage).
  Future<ResolvedPlatformMedia?> resolve(String url) async {
    if (!needsResolution(url)) return null;

    // v1.14.3: YouTube watch/shorts/youtu.be links resolve through
    // youtube_explode (same engine playback uses). We download the best
    // MUXED (audio+video in one file) stream — a single real MP4 the
    // native engine can fetch. Video-only/audio-only pairs would need
    // ffmpeg muxing we don't ship; live streams are HLS manifests —
    // neither becomes a fake/corrupt download.
    if (YouTubeResolver.isYouTubeUrl(url)) {
      try {
        final r = await YouTubeResolver.instance.resolve(url,
            timeout: const Duration(seconds: 20));
        if (r == null) return null;
        return mediaFromYouTube(
          isLive: r.isLive,
          muxedUrl: r.muxedUrl,
          title: r.title,
        );
      } catch (_) {
        return null; // resolvers never throw into the download path
      }
    }

    if (TikTokResolver.isTikTokUrl(url)) {
      try {
        final r = await TikTokResolver.instance.resolve(url);
        if (r == null) return null;
        final title = r.title.trim();
        return ResolvedPlatformMedia(
          directUrl: r.playUrl,
          headers: r.headers ?? const {},
          title: title.isEmpty ? null : title,
          platform: 'tiktok',
        );
      } catch (_) {
        return null; // resolvers never throw into the download path
      }
    }

    try {
      final s = await SocialResolver.instance.resolve(url);
      if (s == null) return null;
      final title = s.title.trim();
      return ResolvedPlatformMedia(
        directUrl: s.playUrl,
        headers: s.headers,
        title: title.isEmpty ? null : title,
        platform: SocialResolver.isTwitterUrl(url) ? 'twitter' : 'facebook',
      );
    } catch (_) {
      return null;
    }
  }
}
