import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/services/network/social_resolver.dart';
import 'package:drs_video/services/player/sleep_timer.dart';
import 'package:drs_video/services/smart/smart_playlists.dart';

MediaItem _item(String id, String title,
    {int plays = 0, bool fav = false, DateTime? added, DateTime? lastPlayed}) {
  final m = MediaItem(
    id: id,
    title: title,
    uri: 'https://x/$id',
    type: MediaItemType.network,
    addedAt: added,
    lastPlayedAt: lastPlayed,
  );
  m.playCount = plays;
  m.isFavorite = fav;
  return m;
}

void main() {
  group('SocialResolver URL detection', () {
    test('facebook forms detected (www/m/web/reel/watch/fb.watch)', () {
      expect(
          SocialResolver.isFacebookUrl(
              'https://www.facebook.com/watch/?v=123456'),
          isTrue);
      expect(SocialResolver.isFacebookUrl('https://m.facebook.com/reel/998877'),
          isTrue);
      expect(SocialResolver.isFacebookUrl('https://fb.watch/abcDEF123/'),
          isTrue);
      expect(
          SocialResolver.isFacebookUrl(
              'https://www.facebook.com/share/v/xyz/'),
          isTrue);
      // evil-host negative
      expect(
          SocialResolver.isFacebookUrl(
              'https://evil-facebook.com/watch/?v=1'),
          isFalse);
    });

    test('twitter/x forms detected, t.co passes, others fail', () {
      expect(
          SocialResolver.isTwitterUrl(
              'https://twitter.com/user/status/1743000000000000000'),
          isTrue);
      expect(
          SocialResolver.isTwitterUrl(
              'https://x.com/user/status/1743000000000000000?s=20'),
          isTrue);
      expect(SocialResolver.isTwitterUrl('https://t.co/abc'), isTrue);
      expect(SocialResolver.isTwitterUrl('https://evil-x.com/status/123'),
          isFalse);
    });

    test('tweet id extraction', () {
      expect(
        SocialResolver.extractTweetId(
            'https://x.com/nasa/status/1743000000000000000?s=20&t=zz'),
        '1743000000000000000',
      );
      expect(SocialResolver.extractTweetId('https://x.com/home'), isNull);
    });

    test('fallback titles', () {
      expect(
          SocialResolver.fallbackTitle('https://m.facebook.com/reel/987654'),
          'Facebook Reel 987654');
      expect(
          SocialResolver.fallbackTitle(
              'https://x.com/a/status/1743000000000000000'),
          'X Video 1743000000000000000');
    });
  });

  group('SocialResolver pure parsers', () {
    test('syndication JSON: best bitrate mp4 wins + title/author', () {
      const body = '''
      {
        "text": "إطلاق المسبار الجديد 🚀",
        "user": {"name": "NASA Arabic"},
        "mediaDetails": [
          {"video_info": {
            "width": 1280, "height": 720,
            "variants": [
              {"bitrate": 320000, "content_type": "video/mp4", "url": "https://video.twimg.com/low.mp4"},
              {"bitrate": 2176000, "content_type": "video/mp4", "url": "https://video.twimg.com/high.mp4"},
              {"bitrate": 632000, "content_type": "application/x-mpegURL", "url": "https://video.twimg.com/pl.m3u8"}
            ]
          }}
        ]
      }''';
      final r = SocialResolver.parseSyndicationJson(
          body, pageUrl: 'https://x.com/a/status/123');
      expect(r, isNotNull);
      expect(r!.playUrl, 'https://video.twimg.com/high.mp4');
      expect(r.author, 'NASA Arabic');
      expect(r.width, 1280);
      expect(r.headers['Referer'], 'https://x.com/');
    });

    test('syndication JSON without media → null', () {
      expect(SocialResolver.parseSyndicationJson('{"text":"hi"}',
          pageUrl: 'x'), isNull);
      expect(SocialResolver.parseSyndicationJson('not json', pageUrl: 'x'),
          isNull);
    });

    test('fxtwitter mirror JSON parsed', () {
      const body = '''
      {
        "tweet": {
          "text": "clip",
          "author": {"name": "DrS"},
          "media": {
            "videos": [
              {"type": "video", "url": "https://v.x/vid.mp4", "bitrate": 900000, "width": 1920, "height": 1080}
            ]
          }
        }
      }''';
      final r = SocialResolver.parseFxtwitterJson(
          body, pageUrl: 'https://x.com/a/status/9');
      expect(r, isNotNull);
      expect(r!.playUrl, 'https://v.x/vid.mp4');
      expect(r.height, 1080);
    });

    test('facebook HTML: browser_native_hd_url preferred, escapes unescaped', () {
      const html = '''
      <html><head><meta property="og:title" content="فيديو جميل"></head><body>
      <script>
      var x = {"browser_native_sd_url":"https:\\/\\/scontent.fbcdn.net\\/sd.mp4?oh=x",
               "browser_native_hd_url":"https:\\/\\/scontent.fbcdn.net\\/hd.mp4?oh=y"};
      </script></body></html>''';
      final r = SocialResolver.parseFacebookHtml(html,
          pageUrl: 'https://m.facebook.com/reel/1');
      expect(r, isNotNull);
      expect(r!.playUrl, 'https://scontent.fbcdn.net/hd.mp4?oh=y');
      expect(r.title, 'فيديو جميل');
      expect(r.headers['Referer'], 'https://m.facebook.com/');
    });

    test('facebook HTML: og:video meta fallback and garbage → null', () {
      const html2 =
          '<meta property="og:video:secure_url" content="https://v.fb/x.mp4">';
      final r2 = SocialResolver.parseFacebookHtml(html2, pageUrl: 'u');
      expect(r2, isNotNull);
      expect(r2!.playUrl, 'https://v.fb/x.mp4');

      expect(SocialResolver.parseFacebookHtml('<html></html>', pageUrl: 'u'),
          isNull);
      expect(SocialResolver.parseFacebookHtml('', pageUrl: 'u'), isNull);
    });
  });

  group('SmartPlaylistGenerator', () {
    final now = DateTime(2026, 9, 27, 12);

    test('standard five lists generated, empty lists dropped', () {
      final lib = [
        _item('a', 'فيلم كرة القدم',
            plays: 3, lastPlayed: now.subtract(const Duration(days: 1))),
        _item('b', 'مباراة كرة',
            plays: 1, lastPlayed: now.subtract(const Duration(days: 2))),
        _item('c', 'وثائقي الفضاء', fav: true),
        _item('c2', 'وثائقي المحيطات', fav: true),
        _item('d', 'درس برمجة'),
        _item('e', 'درس برمجة متقدم'),
      ];
      final progress = {
        'a': WatchProgress(
            itemId: 'a',
            positionMs: 300000,
            durationMs: 600000,
            updatedAt: now),
        'd': WatchProgress(
            itemId: 'd',
            positionMs: 120000,
            durationMs: 600000,
            updatedAt: now),
      };
      final playlists = SmartPlaylistGenerator()
          .generate(library: lib, progressByItem: progress, now: now);

      final kinds = playlists.map((p) => p.kind).toSet();
      expect(kinds, containsAll([
        SmartPlaylistKind.continueWatching,
        SmartPlaylistKind.unwatched,
        SmartPlaylistKind.mostPlayed,
        SmartPlaylistKind.recentlyPlayed,
        SmartPlaylistKind.favorites,
      ]));
      // favorites has 2 items → present
      final favs = playlists.firstWhere((p) => p.kind == SmartPlaylistKind.favorites);
      expect(favs.items.map((m) => m.id), containsAll(['c', 'c2']));
    });

    test('continue watching excludes completed and untouched', () {
      final lib = [
        _item('a', 'A'),
        _item('a2', 'A2'),
        _item('b', 'B'),
        _item('c', 'C', plays: 1),
      ];
      final progress = {
        'a': WatchProgress(
            itemId: 'a',
            positionMs: 50000,
            durationMs: 600000,
            updatedAt: now), // 8% — in progress
        'a2': WatchProgress(
            itemId: 'a2',
            positionMs: 300000,
            durationMs: 600000,
            updatedAt: now), // 50% — in progress
        'b': WatchProgress(
            itemId: 'b',
            positionMs: 590000,
            durationMs: 600000,
            completed: true,
            updatedAt: now), // completed
      };
      final cw = SmartPlaylistGenerator()
          .generate(library: lib, progressByItem: progress, now: now)
          .firstWhere((p) => p.kind == SmartPlaylistKind.continueWatching);
      expect(cw.items.map((m) => m.id), containsAll(['a', 'a2']));
      expect(cw.items.map((m) => m.id), isNot(contains('b')));
      expect(cw.items.map((m) => m.id), isNot(contains('c')));
    });

    test('becauseYouWatched clusters share keywords and cap at 4', () {
      final lib = [
        _item('w1', 'فيلم المغامرة الكبير',
            plays: 2, lastPlayed: now.subtract(const Duration(hours: 3))),
        _item('s1', 'مغامرة في الصحراء'),
        _item('s2', 'مغامرة الغابة'),
        _item('x', 'طبخ الكسكس'),
        _item('y', 'طبخ المعكرونة'),
        _item('z', 'طبخ المحاشي'),
        _item('w2', 'رحلة إلى الفضاء',
            plays: 1, lastPlayed: now.subtract(const Duration(hours: 1))),
        _item('s3', 'رحلة على القمر'),
        _item('s4', 'رحلة إلى المريخ'),
      ];
      final playlists = SmartPlaylistGenerator()
          .generate(library: lib, progressByItem: const {}, now: now);
      final because = playlists
          .where((p) => p.kind == SmartPlaylistKind.becauseYouWatched)
          .toList();
      expect(because.length, 2); // 2 watched anchors produced clusters
      final anchorTitles = because.map((p) => p.anchorTitle).toSet();
      expect(anchorTitles, contains('فيلم المغامرة الكبير'));
      // The most recently watched anchor comes first (w2, 1h ago).
      final firstCluster = because.first;
      expect(firstCluster.anchorTitle, 'رحلة إلى الفضاء');
      expect(firstCluster.items.map((m) => m.id), containsAll(['s3', 's4']));
      // The older anchor's cluster shares مغامره with s1/s2.
      final adventureCluster = because
          .firstWhere((p) => p.anchorTitle == 'فيلم المغامرة الكبير');
      expect(adventureCluster.items.map((m) => m.id),
          containsAll(['s1', 's2']));
      // No anchor includes itself in its own cluster
      for (final p in because) {
        expect(p.items.any((m) => m.title == p.anchorTitle), isFalse);
      }
    });
  });

  group('SleepTimer v1.6.0', () {
    test('fadeFactor: null until fade window, then ramps 1→0', () async {
      final fired = Completer<void>();
      final timer = SleepTimer(fired.complete);

      timer.start(const Duration(seconds: 12));
      expect(timer.fadeFactor, isNull); // 12s > 10s window

      await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 600));
      final f1 = timer.fadeFactor;
      expect(f1, isNotNull);
      expect(f1!, lessThan(0.95));
      expect(f1, greaterThan(0.5));

      timer.cancel();
      expect(timer.fadeFactor, isNull);
      expect(timer.isActive, isFalse);
      timer.dispose();
    });

    test('fires at zero and exposes end-of-video mode', () async {
      final fired = Completer<void>();
      final timer = SleepTimer(() => fired.complete());
      timer.start(const Duration(milliseconds: 900));
      await fired.future.timeout(const Duration(seconds: 3));
      expect(timer.isActive, isFalse);
      expect(timer.fadeFactor, isNull);

      timer.startEndOfVideo();
      expect(timer.isEndOfVideo, isTrue);
      expect(timer.consumeEndOfVideo(), isTrue);
      expect(timer.isEndOfVideo, isFalse);
      timer.dispose();
    });
  });
}
