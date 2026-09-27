import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/core/storage/preferences_service.dart';
import 'package:drs_video/services/network/smart_url.dart';
import 'package:drs_video/state/floating_player_controller.dart';

void main() {
  group('SmartUrl — URL extraction from shared text', () {
    test('plain URL passes through', () {
      expect(
        SmartUrl.extractUrlFromText('https://example.com/video.mp4'),
        'https://example.com/video.mp4',
      );
    });

    test('extracts URL from surrounding text (share sheet payloads)', () {
      const text = 'شاهد هذا الفيديو https://youtu.be/dQw4w9WgXcQ سيتحقق من ذلك';
      expect(SmartUrl.extractUrlFromText(text),
          'https://youtu.be/dQw4w9WgXcQ');
    });

    test('strips trailing sentence punctuation', () {
      expect(
        SmartUrl.extractUrlFromText('Check this: https://x.com/a.mp4.'),
        'https://x.com/a.mp4',
      );
      expect(
        SmartUrl.extractUrlFromText('رابط: https://x.com/a.mp4، وقول رأيك'),
        'https://x.com/a.mp4',
      );
    });

    test('returns null for text without URLs', () {
      expect(SmartUrl.extractUrlFromText('نص عادي بدون روابط'), isNull);
      expect(SmartUrl.extractUrlFromText(''), isNull);
    });

    test('does not swallow Arabic text glued after the URL', () {
      final url = SmartUrl.extractUrlFromText(
          'https://example.com/v.mp4 والفيديو التالي');
      expect(url, 'https://example.com/v.mp4');
    });
  });

  group('SmartUrl — YouTube detection', () {
    test('recognizes standard watch URLs', () {
      expect(SmartUrl.isYouTube('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          isTrue);
      expect(SmartUrl.extractYouTubeId(
              'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
    });

    test('recognizes youtu.be short links', () {
      expect(SmartUrl.isYouTube('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(SmartUrl.extractYouTubeId('https://youtu.be/dQw4w9WgXcQ?t=42'),
          'dQw4w9WgXcQ');
    });

    test('recognizes shorts, embed, live and mobile hosts', () {
      expect(
          SmartUrl.isYouTube('https://m.youtube.com/shorts/abc12345678'),
          isTrue);
      expect(SmartUrl.extractYouTubeId(
              'https://m.youtube.com/shorts/abc12345678'),
          'abc12345678');
      expect(SmartUrl.isYouTube(
          'https://music.youtube.com/watch?v=abcdefghijk'), isTrue);
      expect(SmartUrl.isYouTube('https://www.youtube.com/embed/abcdefghijk'),
          isTrue);
      expect(SmartUrl.isYouTube('https://youtube.com/live/abcdefghijk'),
          isTrue);
    });

    test('rejects non-YouTube hosts and malformed ids', () {
      expect(SmartUrl.isYouTube('https://vimeo.com/123456'), isFalse);
      expect(SmartUrl.isYouTube('https://example.com/watch?v=abc'), isFalse);
      expect(SmartUrl.isYouTube('https://youtube.com/'), isFalse);
    });
  });

  group('SmartUrl — classification and titles', () {
    test('HLS manifests', () {
      expect(SmartUrl.classify('http://srv.example/live/index.m3u8'),
          SmartUrlKind.hls);
    });

    test('DASH manifests', () {
      expect(SmartUrl.classify('https://cdn.example/stream.mpd'),
          SmartUrlKind.dash);
    });

    test('raw streaming protocols', () {
      expect(SmartUrl.classify('rtsp://cam.local:554/stream'),
          SmartUrlKind.rtspRtmp);
      expect(SmartUrl.classify('rtmps://live.example/app/key'),
          SmartUrlKind.rtspRtmp);
      expect(SmartUrl.classify('mms://old.example/video'),
          SmartUrlKind.rtspRtmp);
    });

    test('ftp family', () {
      expect(SmartUrl.classify('ftp://nas.local/media/movie.mkv'),
          SmartUrlKind.ftp);
      expect(SmartUrl.classify('sftp://nas.local/media/movie.mkv'),
          SmartUrlKind.ftp);
    });

    test('direct files default to direct', () {
      expect(SmartUrl.classify('https://site.example/movie.mp4'),
          SmartUrlKind.direct);
      expect(SmartUrl.classify('https://site.example/page'),
          SmartUrlKind.direct);
    });

    test('title falls back from filename to host', () {
      expect(SmartUrl.titleFor('https://a.b/c/movie%20file.mp4'),
          'movie file.mp4');
      expect(SmartUrl.titleFor('https://a.b/'), 'a.b');
    });

    test('supported scheme check', () {
      expect(SmartUrl.hasSupportedScheme('https://a.b/c.mp4'), isTrue);
      expect(SmartUrl.hasSupportedScheme('rtsp://a.b/c'), isTrue);
      expect(SmartUrl.hasSupportedScheme('content://media/video/1'), isFalse);
      expect(SmartUrl.hasSupportedScheme('not a url'), isFalse);
    });
  });

  group('FloatingPlayerController', () {
    test('show/hide toggles visibility', () {
      final c = FloatingPlayerController();
      expect(c.visible, isFalse);
      c.show();
      expect(c.visible, isTrue);
      c.hide();
      expect(c.visible, isFalse);
      c.dispose();
    });

    test('auto-hides when media is removed from the player', () {
      var hasMedia = true;
      final player = _FakePlayer();
      final c = FloatingPlayerController();
      c.attach(player, () => hasMedia);

      c.show();
      expect(c.visible, isTrue);

      // Playback ends / stop() clears the current item:
      hasMedia = false;
      player.notifyListeners();
      expect(c.visible, isFalse,
          reason: 'the floating window must not outlive playback');
      c.dispose();
    });

    test('stays visible while media keeps playing', () {
      final player = _FakePlayer();
      final c = FloatingPlayerController();
      c.attach(player, () => true);
      c.show();
      player.notifyListeners();
      expect(c.visible, isTrue);
      c.dispose();
    });

    test('dragTo keeps the last user position (anchor initialized)', () {
      final c = FloatingPlayerController();
      c.setOffset(const Offset(40, 60));
      expect(c.anchorInitialized, isTrue);
      c.dragTo(const Offset(120, 200));
      expect(c.offset, const Offset(120, 200));
      c.dispose();
    });
  });

  group('PreferencesService — floating window default', () {
    test('enableFloatingPlayer defaults to true', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs =
          PreferencesService(await SharedPreferences.getInstance());
      expect(prefs.enableFloatingPlayer, isTrue);
      prefs.enableFloatingPlayer = false;
      expect(prefs.enableFloatingPlayer, isFalse);
    });

    test('app version constant bumped to 1.12.0', () {
      expect(AppConstants.appVersion, '1.14.3');
    });
  });
}

class _FakePlayer extends ChangeNotifier {}
