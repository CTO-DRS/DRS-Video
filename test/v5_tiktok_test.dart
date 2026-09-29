import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/services/network/smart_url.dart';
import 'package:drs_video/services/network/tiktok_resolver.dart';
import 'package:drs_video/services/network/tiktok_webview_extractor.dart';

void main() {
  group('TikTokResolver — URL detection', () {
    test('detects every real TikTok link form', () {
      expect(TikTokResolver.isTikTokUrl('https://www.tiktok.com/@user/video/7318517321748022790'), isTrue);
      expect(TikTokResolver.isTikTokUrl('https://vm.tiktok.com/ZMhQxKpLE/'), isTrue);
      expect(TikTokResolver.isTikTokUrl('https://vt.tiktok.com/ZSAbcd123/'), isTrue);
      expect(TikTokResolver.isTikTokUrl('https://m.tiktok.com/v/7318517321748022790.html'), isTrue);
      expect(TikTokResolver.isTikTokUrl('https://tiktok.com/@user/video/7318517321748022790'), isTrue);
      expect(TikTokResolver.isTikTokUrl('http://mobile.tiktok.com/@a/video/123456'), isTrue);
    });

    test('rejects non-TikTok URLs', () {
      expect(TikTokResolver.isTikTokUrl('https://youtube.com/watch?v=x'), isFalse);
      expect(TikTokResolver.isTikTokUrl('https://example.com/video/123'), isFalse);
      expect(TikTokResolver.isTikTokUrl('https://tiktok.com.evil.io/video/123'), isFalse);
      expect(TikTokResolver.isTikTokUrl('not a url'), isFalse);
      expect(TikTokResolver.isTikTokUrl(''), isFalse);
      // Direct media links must never be routed through the resolver.
      expect(TikTokResolver.isTikTokUrl('https://cdn.example.com/clip.mp4'), isFalse);
    });

    test('extracts the video id from canonical URLs', () {
      expect(
        TikTokResolver.extractVideoId('https://www.tiktok.com/@user/video/7318517321748022790'),
        '7318517321748022790',
      );
      expect(
        TikTokResolver.extractVideoId('https://www.tiktok.com/@user/photo/7318517321748022790'),
        isNull,
      );
      // Short links carry no id until a redirect is followed.
      expect(TikTokResolver.extractVideoId('https://vm.tiktok.com/ZMhQxKpLE/'), isNull);
    });

    test('SmartUrl extracts TikTok links from arbitrary share text', () {
      const text = 'شوف هذا الفيديو! https://vm.tiktok.com/ZMhQxKpLE/ لا تفوته';
      expect(SmartUrl.extractUrlFromText(text), 'https://vm.tiktok.com/ZMhQxKpLE/');
      const en = 'Check this out 😂 https://www.tiktok.com/@user/video/7318517321748022790';
      expect(
        SmartUrl.extractUrlFromText(en),
        'https://www.tiktok.com/@user/video/7318517321748022790',
      );
    });
  });

  group('TikTokResolver — mobile feed API parser', () {
    test('parses play_addr url_list into a resolved stream', () {
      final json = jsonDecode(_feedApiFixture) as Map<String, dynamic>;
      final r = TikTokResolver.parseFeedApiJson(json);
      expect(r, isNotNull);
      expect(r!.videoId, '7318517321748022790');
      expect(r.title, 'لقطات من السفر 🌊 #travel');
      expect(r.author, 'DRS Travel');
      expect(r.playUrl, startsWith('https://v16m-default.akamaized.net'));
      expect(r.width, 1080);
      expect(r.height, 1920);
      expect(r.durationMs, 27433);
      // Feed-API CDN URLs need no extra headers.
      expect(r.headers, isNull);
    });

    test('returns null on empty/structurally-wrong payloads', () {
      expect(TikTokResolver.parseFeedApiJson({}), isNull);
      expect(TikTokResolver.parseFeedApiJson({'aweme_list': []}), isNull);
      expect(TikTokResolver.parseFeedApiJson({
        'aweme_list': [{'aweme_id': 'x'}], // no video
      }), isNull);
      expect(TikTokResolver.parseFeedApiJson({
        'aweme_list': [
          {
            'aweme_id': 'x',
            'video': {'play_addr': {'url_list': []}},
          }
        ],
      }), isNull);
    });
  });

  group('TikTokResolver — web page rehydration parsers', () {
    test('finds __UNIVERSAL_DATA_FOR_REHYDRATION__ JSON inside HTML', () {
      final payload = TikTokResolver.extractRehydrationPayload(_pageHtml);
      expect(payload, isNotNull);
      final r = TikTokResolver.parseWebPagePayload(payload!, '7318517321748022790');
      expect(r, isNotNull);
      expect(r!.playUrl, 'https://v16-webapp.tiktok.com/video/tos/useast2a/tos.mp4?a=1');
      expect(r.title, 'TikTok clip');
      expect(r.author, 'DRS');
      // Web CDN URLs must carry UA/Referer headers for mpv.
      expect(r.headers, isNotNull);
      expect(r.headers!['Referer'], 'https://www.tiktok.com/');
    });

    test('falls back to legacy SIGI_STATE payload', () {
      final payload = TikTokResolver.extractRehydrationPayload(_sigiHtml);
      expect(payload, isNotNull);
      final r = TikTokResolver.parseWebPagePayload(payload!, '7318517321748022790');
      expect(r, isNotNull);
      expect(r!.playUrl, 'https://v16-webapp.tiktok.com/legacy.mp4');
    });

    test('returns null when the page carries neither payload', () {
      expect(TikTokResolver.extractRehydrationPayload('<html><body>captcha</body></html>'), isNull);
    });

    test('rejects itemStruct without a playable address', () {
      final payload = jsonDecode('''
      {"__DEFAULT_SCOPE__": {"webapp.video-detail": {"itemInfo": {"itemStruct": {
        "id": "7318517321748022790", "desc": "x",
        "video": {"playAddr": "", "duration": 10}
      }}}}}
      ''') as Map<String, dynamic>;
      expect(TikTokResolver.parseWebPagePayload(payload, '7318517321748022790'), isNull);
    });
  });

  group('TikTokResolver — tikwm API parser (v1.4.2)', () {
    test('parses success payload preferring hdplay', () {
      final json = jsonDecode('''
      {"code": 0, "msg": "success", "data": {
        "id": "7318517321748022790",
        "title": "فيديو التجربة",
        "play": "/video/tos/useast2a/standard.mp4",
        "hdplay": "https://www.tikwm.com/video/tos/useast2a/hd.mp4",
        "wmplay": "https://www.tikwm.com/video/wm.mp4",
        "duration": 21,
        "author": {"nickname": "DRS", "unique_id": "drs"}
      }}
      ''') as Map<String, dynamic>;
      final r = TikTokResolver.parseTikwmJson(json);
      expect(r, isNotNull);
      expect(r!.videoId, '7318517321748022790');
      expect(r.title, 'فيديو التجربة');
      expect(r.author, 'DRS');
      expect(r.playUrl, 'https://www.tikwm.com/video/tos/useast2a/hd.mp4');
      expect(r.durationMs, 21);
    });

    test('falls back to play and prefixes root-relative paths', () {
      final json = jsonDecode('''
      {"code": 0, "data": {"id": "1", "title": "t", "play": "/video/x.mp4", "author": {}}}
      ''') as Map<String, dynamic>;
      final r = TikTokResolver.parseTikwmJson(json);
      expect(r!.playUrl, 'https://www.tikwm.com/video/x.mp4');
    });

    test('returns null on error codes and missing media', () {
      expect(
        TikTokResolver.parseTikwmJson({'code': -1, 'msg': 'blocked'}),
        isNull,
      );
      expect(
        TikTokResolver.parseTikwmJson({'code': 0, 'data': {'id': '1'}}),
        isNull,
      );
      expect(TikTokResolver.parseTikwmJson({}), isNull);
    });
  });

  group('TikTokWebViewExtractor — URL matcher (v1.4.2)', () {
    test('accepts real TikTok video CDN requests', () {
      expect(
        TikTokWebViewExtractor.looksLikeVideoUrl(
            'https://v16-webapp.tiktok.com/video/tos/useast2a/tos-useast2a-ve-0068/e6e1e2.mp4?mime_type=video_mp4'),
        isTrue,
      );
      expect(
        TikTokWebViewExtractor.looksLikeVideoUrl(
            'https://v16m-default.akamaized.net/video/tos/useast2a/a.mp4'),
        isTrue,
      );
      expect(
        TikTokWebViewExtractor.looksLikeVideoUrl(
            'https://v95-p.douyinvod.com/video/tos/x.mp4'),
        isFalse, // douyin CDN is out of scope
      );
    });

    test('rejects non-media traffic and streamed containers', () {
      expect(
        TikTokWebViewExtractor.looksLikeVideoUrl(
            'https://www.tiktok.com/api/item/detail/?aid=1988'),
        isFalse,
      );
      expect(
        TikTokWebViewExtractor.looksLikeVideoUrl(
            'https://v16-webapp.tiktok.com/hls/tos/live.m3u8'),
        isFalse,
      );
      expect(
        TikTokWebViewExtractor.looksLikeVideoUrl(
            'blob:https://www.tiktok.com/9b8c-1a2b'),
        isFalse,
      );
      expect(
        TikTokWebViewExtractor.looksLikeVideoUrl(
            'https://lf16-tiktok-web.tiktok.com/web/static/js/chunk.js'),
        isFalse,
      );
    });
  });
}

const _feedApiFixture = '''
{
  "aweme_list": [
    {
      "aweme_id": "7318517321748022790",
      "desc": "لقطات من السفر 🌊 #travel",
      "author": {"nickname": "DRS Travel", "unique_id": "drstravel"},
      "video": {
        "play_addr": {
          "uri": "https://v16m-default.akamaized.net/o6C0g/video/tos/useast2a/tos.mp4",
          "url_list": [
            "https://v16m-default.akamaized.net/o6C0g/video/tos/useast2a/tos.mp4",
            "https://api16-normal-c-useast1a.tiktokcdn.com/video/tos/useast2a/tos.mp4"
          ]
        },
        "width": 1080,
        "height": 1920,
        "duration": 27433
      }
    }
  ],
  "extra": "ignored"
}
''';

const _pageHtml = '''
<!DOCTYPE html>
<html lang="en">
<head><title>TikTok</title></head>
<body>
<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"itemInfo":{"itemStruct":{"id":"7318517321748022790","desc":"TikTok clip","author":{"uniqueId":"drsvideo","nickname":"DRS"},"video":{"playAddr":"https://v16-webapp.tiktok.com/video/tos/useast2a/tos.mp4?a=1","downloadAddr":"https://v16-webapp.tiktok.com/dl.mp4","duration":21,"width":576,"height":1024}}}},"webapp.user-detail":{}}}
</script>
</body>
</html>
''';

const _sigiHtml = '''
<html><body>
<script id="SIGI_STATE" type="application/json">
{"ItemModule":{"7318517321748022790":{"id":"7318517321748022790","desc":"legacy","author":{"uniqueId":"drsvideo","nickname":"DRS"},"video":{"playAddr":"https://v16-webapp.tiktok.com/legacy.mp4","duration":15}}}}
</script>
</body></html>
''';
