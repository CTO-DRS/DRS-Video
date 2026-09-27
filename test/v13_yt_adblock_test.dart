import 'package:flutter_test/flutter_test.dart';

import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/services/browser/ad_block.dart';
import 'package:drs_video/services/browser/yt_ad_killer.dart';

/// v1.11.0 — YouTube ad-blocking upgrade.
///
/// Three layers, all pure and unit-testable:
///   1. URL-pattern layer (AdBlockList.matchesAdUrlPattern / shouldBlockUrl)
///      — catches ad + ad-telemetry endpoints YouTube serves from its own
///      hosts, which the domain blocklist can never match;
///   2. in-page killer script (YtAdKiller) — auto-skip, fast-forward and
///      CSS-hide ads rendered inside the page DOM;
///   3. version bump.
void main() {
  group('v1.11.0 URL-pattern layer (AdBlockList)', () {
    test('blocks YouTube ad + ad-telemetry endpoints', () {
      const cases = [
        // Ad telemetry beacons.
        'https://www.youtube.com/api/stats/ads?ver=2&c=WEB',
        'https://www.youtube.com/api/stats/atr?el=adunit',
        'https://m.youtube.com/api/stats/ads?x=1',
        // Google ad-serving paths on YouTube hosts.
        'https://www.youtube.com/pagead/interaction?ad_type=video',
        'https://www.youtube-nocookie.com/pagead/idsos?x',
        // Ad click/verification endpoints.
        'https://www.youtube.com/ptracking?html5=1',
        'https://www.youtube.com/player_204?id=adunit',
        'https://r4---sn-x.googlevideo.com/videogoodput?id=1',
        'https://www.youtube.com/get_midroll_info?m=2',
        'https://www.youtube.com/get_video_ads?x',
        // Ad params inside otherwise-legal URLs (qoe/play stats).
        'https://www.youtube.com/api/stats/qoe?adformat=15&x=1',
        'https://www.youtube.com/api/stats/play?ad_type=skip',
        'https://www.youtube.com/watch?v=x&ctier=L',
      ];
      for (final c in cases) {
        expect(AdBlockList.matchesAdUrlPattern(c), isTrue, reason: c);
      }
    });

    test('never blocks real playback, pages or thumbnails', () {
      const cases = [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=x&t=30',
        'https://music.youtube.com/watch?v=x',
        'https://r4---sn-x.googlevideo.com/videoplayback?id=x&itag=22&source=youtube',
        'https://r4---sn-x.googlevideo.com/videoplayback?mime=video%2Fmp4',
        'https://i.ytimg.com/vi/x/hqdefault.jpg',
        'https://www.youtube.com/api/stats/play?p=x',
        'https://www.youtube.com/api/stats/delayplay?p=x',
        'https://www.youtube.com/api/stats/watchtime?x=1',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/feed/history',
        'https://www.youtube.com/results?search_query=test',
        'https://www.youtube.com/generate_204',
      ];
      for (final c in cases) {
        expect(AdBlockList.matchesAdUrlPattern(c), isFalse, reason: c);
      }
    });

    test('host scoping: aggressive fragments are YouTube-only', () {
      // Same paths on OTHER hosts must NOT be blocked by the yt-scoped
      // layer (a site could legitimately serve /api/stats/ads).
      expect(
        AdBlockList.matchesAdUrlPattern('https://example.com/api/stats/ads?x'),
        isFalse,
      );
      expect(
        AdBlockList.matchesAdUrlPattern('https://example.com/videogoodput'),
        isFalse,
      );
      // Subdomain host check cannot be fooled by look-alike domains.
      expect(
        AdBlockList.matchesAdUrlPattern('https://evilyoutube.com/api/stats/ads'),
        isFalse,
      );
      // Global unambiguous ad endpoints apply on ANY host.
      expect(
        AdBlockList.matchesAdUrlPattern('https://t.example.com/click?adurl=https://x'),
        isTrue,
      );
      expect(
        AdBlockList.matchesAdUrlPattern('https://ads.example.com/pagead/adfetch?x'),
        isTrue,
      );
      // Non-http / garbage never blocks.
      expect(AdBlockList.matchesAdUrlPattern(''), isFalse);
      expect(AdBlockList.matchesAdUrlPattern('file:///tmp/x'), isFalse);
      expect(AdBlockList.matchesAdUrlPattern('about:blank'), isFalse);
    });

    test('shouldBlockUrl combines pattern + host layers', () async {
      // Pattern layer works without the blocklist asset being loaded.
      expect(
        await AdBlockList.instance.shouldBlockUrl(
            'https://www.youtube.com/api/stats/ads?x=1'),
        isTrue,
      );
      expect(
        await AdBlockList.instance.shouldBlockUrl(
            'https://www.youtube.com/watch?v=abc'),
        isFalse,
      );
    });
  });

  group('v1.11.0 YtAdKiller in-page script', () {
    test('exposes the critical skip/purge machinery', () {
      final js = YtAdKiller.js;
      // Install guard + runtime pause switch.
      expect(js, contains('__drsAdKillInstalled'));
      expect(js, contains('__drsAdKill'));
      // Ad-break fast-forward (the player ad-state classes).
      expect(js, contains('.ad-showing'));
      expect(js, contains('currentTime'));
      // Continuous polling + DOM watching.
      expect(js, contains('setInterval'));
      expect(js, contains('MutationObserver'));
      // CSS unit hiding.
      expect(js, contains('drs-ad-css'));
      for (final s in YtAdKiller.hideSelectors.take(5)) {
        expect(js, contains(s), reason: s);
      }
      for (final s in YtAdKiller.skipSelectors.take(5)) {
        expect(js, contains(s), reason: s);
      }
    });

    test('selector coverage includes YouTube + mobile web + Arabic UI', () {
      expect(YtAdKiller.hideSelectors, contains('#masthead-ad'));
      expect(YtAdKiller.hideSelectors, contains('ytd-display-ad-renderer'));
      expect(
        YtAdKiller.hideSelectors,
        contains('ytm-promoted-video-renderer'),
      );
      expect(YtAdKiller.skipSelectors, contains('.ytp-ad-skip-button-modern'));
      expect(YtAdKiller.skipSelectors, contains('.videoAdUiSkipButton'));
      // Arabic "Skip" label for arabic-first users.
      expect(
        YtAdKiller.skipSelectors.any((s) => s.contains('تخطي')),
        isTrue,
      );
    });

    test('script is non-trivial and brace-balanced', () {
      final js = YtAdKiller.js;
      expect(js.length, greaterThan(1200));
      expect('{'.allMatches(js).length, equals('}'.allMatches(js).length));
      expect('('.allMatches(js).length, equals(')'.allMatches(js).length));
    });
  });

  group('v1.11.0 version bump', () {
    test('app version is 1.11.0', () {
      expect(AppConstants.appVersion, '1.13.0');
    });
  });
}
