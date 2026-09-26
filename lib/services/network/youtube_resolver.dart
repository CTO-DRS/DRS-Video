import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import 'smart_url.dart';

/// How long a resolved YouTube stream stays valid in the cache. YouTube
/// stream URLs are time-limited, so after this window the next play
/// re-resolves instead of reusing a dead URL.
const Duration _cacheTtl = Duration(hours: 4);

/// Result of resolving a YouTube URL into a real, playable stream.
class ResolvedStream {
  const ResolvedStream({
    required this.videoId,
    required this.title,
    required this.author,
    required this.isLive,
    this.videoUrl,
    this.audioUrl,
    this.muxedUrl,
    this.width,
    this.height,
  });

  final String videoId;
  final String title;
  final String author;
  final bool isLive;

  /// Best video-only stream URL (played together with [audioUrl] via
  /// mpv's external audio file). Null when the manifest has none.
  final String? videoUrl;

  /// Best audio-only stream URL (loaded as mpv external audio track).
  final String? audioUrl;

  /// Fallback single URL containing both audio+video (muxed), or the HLS
  /// manifest URL for live streams. Used when [videoUrl] is unavailable.
  final String? muxedUrl;

  final int? width;
  final int? height;

  /// The URL mpv should open: video-only when paired with audio,
  /// otherwise the muxed/live fallback.
  String? get playUrl => videoUrl ?? muxedUrl;
}

/// Resolves YouTube watch/shorts/embed links into direct media URLs using
/// youtube_explode_dart (real extraction, no scraping hacks).
///
/// Resolved stream URLs are time-limited by YouTube, so results are cached
/// per video id for 4 hours only; after that the next play re-resolves.
/// Every failure returns null — the caller falls back to direct playback
/// and the player surfaces the real error; this module never throws.
class YouTubeResolver {
  YouTubeResolver._();

  static final YouTubeResolver instance = YouTubeResolver._();

  YoutubeExplode? _yt;
  final _cache = <String, _CacheEntry>{};

  static bool isYouTubeUrl(String url) => SmartUrl.isYouTube(url);

  static String? extractVideoId(String url) => SmartUrl.extractYouTubeId(url);

  /// Resolves [url]; null on any failure (offline, age-restricted,
  /// extraction API change, ...). Safe to call from UI paths.
  Future<ResolvedStream?> resolve(
    String url, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final id = extractVideoId(url);
    if (id == null) return null;

    final cached = _cache[id];
    if (cached != null && !cached.isExpired) return cached.value;

    try {
      final result = await _resolveNow(id).timeout(timeout);
      if (result != null) _cache[id] = _CacheEntry(result);
      return result;
    } catch (e, s) {
      AppLogger.instance.error('youtube', 'resolve $id failed: $e', e, s);
      return null;
    }
  }

  /// Quick metadata lookup used when saving a link (title for the list).
  /// Returns null on failure — the caller keeps the URL-derived title.
  Future<String?> fetchTitle(String url) async {
    final r = await resolve(url, timeout: AppConstants.youtubeTitleTimeout);
    return r?.title;
  }

  Future<ResolvedStream?> _resolveNow(String id) async {
    _yt ??= YoutubeExplode();
    final yt = _yt!;
    final video = await yt.videos.get(id);
    final manifest = await yt.videos.streams.getManifest(id);

    StreamInfo? highestBitrate(Iterable<StreamInfo> streams) {
      StreamInfo? best;
      for (final s in streams) {
        if (best == null ||
            s.bitrate.bitsPerSecond > best.bitrate.bitsPerSecond) {
          best = s;
        }
      }
      return best;
    }

    if (video.isLive) {
      // Live: prefer the HLS muxed manifest (mpv plays HLS natively).
      final hlsUrl = highestBitrate(manifest.hls)?.url.toString();
      return ResolvedStream(
        videoId: id,
        title: video.title,
        author: video.author,
        isLive: true,
        muxedUrl: hlsUrl,
      );
    }

    // VOD: best video-only + best audio-only gives real 720p/1080p+ via
    // mpv's external audio track; muxed (<=360p) is the fallback.
    final videoOnly = manifest.videoOnly
        .where((s) => s.container.name == 'mp4')
        .toList()
      ..sort((a, b) => b.bitrate.bitsPerSecond
          .compareTo(a.bitrate.bitsPerSecond));
    final audioOnly = manifest.audioOnly
        .where((s) => s.container.name == 'mp4')
        .toList()
      ..sort((a, b) => b.bitrate.bitsPerSecond
          .compareTo(a.bitrate.bitsPerSecond));

    // Cap the video selection at 1080p: 4K video-only streams are huge;
    // 1080p mp4 keeps compatibility and bandwidth sane on phones.
    final capped = videoOnly
        .where((s) => s.videoResolution.height <= 1080)
        .toList();
    final chosenVideo = capped.isNotEmpty ? capped.first : null;
    final chosenAudio = audioOnly.isNotEmpty ? audioOnly.first : null;

    String? muxedUrl;
    if (chosenVideo == null) {
      final muxedUrlStream =
          highestBitrate(manifest.muxed.cast<StreamInfo>());
      muxedUrl = muxedUrlStream?.url.toString();
    }

    return ResolvedStream(
      videoId: id,
      title: video.title,
      author: video.author,
      isLive: false,
      videoUrl: chosenVideo?.url.toString(),
      audioUrl: chosenAudio?.url.toString(),
      muxedUrl: muxedUrl,
      width: chosenVideo?.videoResolution.width,
      height: chosenVideo?.videoResolution.height,
    );
  }
}

class _CacheEntry {
  _CacheEntry(this.value);
  final ResolvedStream value;
  final DateTime at = DateTime.now();

  bool get isExpired => DateTime.now().difference(at) > _cacheTtl;
}
