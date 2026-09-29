import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/features/sites/youtube_search_screen.dart';
import 'package:drs_video/services/downloader/platform_download_resolver.dart';

/// v1.14.3 regression tests — "لا ينزل أي شيء" for YouTube links.
///
/// Root cause discovered after the user's second slow/no-download report:
/// the downloads pipeline resolved TikTok/X/Facebook share pages but NOT
/// YouTube — a pasted watch URL was probed as-is, YouTube answered
/// text/html, and the HTML guard rejected EVERY YouTube download forever.
/// The fix: YouTube joins the platform resolver (youtube_explode, best
/// muxed MP4) and the Sites catalog routes YouTube to a native search
/// screen with per-result play/download.
void main() {
  group('PlatformDownloadResolver — YouTube in needsResolution (pure)', () {
    test('accepts every real YouTube URL form', () {
      expect(PlatformDownloadResolver.needsResolution(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://youtube.com/watch?v=dQw4w9WgXcQ&t=30s'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://m.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://www.youtube.com/shorts/aBcD_eFgHiJ'), isTrue);
      expect(PlatformDownloadResolver.needsResolution(
          'https://music.youtube.com/watch?v=dQw4w9WgXcQ'), isTrue);
    });

    test('still rejects invalid ids, look-alike hosts and non-platforms', () {
      // ids shorter than 8 chars are not video ids — never resolvable.
      expect(PlatformDownloadResolver.needsResolution(
          'https://youtube.com/watch?v=abc'), isFalse);
      expect(PlatformDownloadResolver.needsResolution(
          'https://youtube.com.evil.com/watch?v=dQw4w9WgXcQ'), isFalse);
      expect(PlatformDownloadResolver.needsResolution(
          'https://evil.com/?u=https://youtube.com/watch?v=dQw4w9WgXcQ'),
          isFalse);
      expect(PlatformDownloadResolver.needsResolution(
          'https://instagram.com/p/abc/'), isFalse);
      expect(PlatformDownloadResolver.needsResolution(
          'https://cdn.example.com/movie.mp4'), isFalse);
      expect(PlatformDownloadResolver.needsResolution(''), isFalse);
    });
  });

  group('PlatformDownloadResolver.mediaFromYouTube — download policy (pure)',
      () {
    test('muxed non-live video becomes a header-free download', () {
      final m = PlatformDownloadResolver.mediaFromYouTube(
        isLive: false,
        muxedUrl: 'https://rr3---sn-xyz.googlevideo.com/videoplayback?id=abc',
        title: '  My Video  ',
      );
      expect(m, isNotNull);
      expect(m!.platform, 'youtube');
      expect(m.directUrl, contains('googlevideo.com'));
      expect(m.headers, isEmpty);
      expect(m.title, 'My Video');
    });

    test('live streams never become download tasks (HLS is not a file)', () {
      expect(PlatformDownloadResolver.mediaFromYouTube(
        isLive: true,
        muxedUrl: 'https://manifest.googlevideo.com/api/manifest/hls.m3u8',
        title: 'Live',
      ), isNull);
    });

    test('DASH-only videos (no muxed stream) fail honestly, not with junk',
        () {
      expect(PlatformDownloadResolver.mediaFromYouTube(
        isLive: false,
        muxedUrl: null,
        title: 'Video',
      ), isNull);
      expect(PlatformDownloadResolver.mediaFromYouTube(
        isLive: false,
        muxedUrl: '',
        title: 'Video',
      ), isNull);
    });

    test('empty title becomes null title (filename suggester takes over)',
        () {
      final m = PlatformDownloadResolver.mediaFromYouTube(
        isLive: false,
        muxedUrl: 'https://g.example/v.mp4',
        title: '   ',
      );
      expect(m, isNotNull);
      expect(m!.title, isNull);
    });
  });

  group('YouTubeSearchScreen.isYouTubeSite — catalog routing (pure)', () {
    test('routes every YouTube host to the native screen', () {
      expect(YouTubeSearchScreen.isYouTubeSite('https://www.youtube.com'),
          isTrue);
      expect(YouTubeSearchScreen.isYouTubeSite('https://youtube.com'),
          isTrue);
      expect(YouTubeSearchScreen.isYouTubeSite('https://m.youtube.com'),
          isTrue);
      expect(YouTubeSearchScreen.isYouTubeSite('https://music.youtube.com'),
          isTrue);
      expect(YouTubeSearchScreen.isYouTubeSite('https://youtu.be'), isTrue);
    });

    test('other sites keep the WebView browser', () {
      expect(YouTubeSearchScreen.isYouTubeSite('https://www.tiktok.com'),
          isFalse);
      expect(YouTubeSearchScreen.isYouTubeSite('https://youtube.com.evil.com'),
          isFalse);
      expect(YouTubeSearchScreen.isYouTubeSite('not a url'), isFalse);
      expect(YouTubeSearchScreen.isYouTubeSite(''), isFalse);
    });
  });
}
