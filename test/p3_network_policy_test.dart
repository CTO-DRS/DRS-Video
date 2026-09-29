import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drs_video/core/network/cleartext_policy.dart';
import 'package:drs_video/core/network/dio_client.dart';

void main() {
  group('CleartextPolicy.isAppControlledHost', () {
    test('exact host matches', () {
      expect(CleartextPolicy.isAppControlledHost('api.github.com'), isTrue);
      expect(CleartextPolicy.isAppControlledHost('vpngate.net'), isTrue);
      expect(CleartextPolicy.isAppControlledHost('tikwm.com'), isTrue);
      expect(
          CleartextPolicy.isAppControlledHost('translate.googleapis.com'),
          isTrue);
    });

    test('subdomains match the base host', () {
      expect(CleartextPolicy.isAppControlledHost('www.vpngate.net'), isTrue);
      expect(CleartextPolicy.isAppControlledHost('www.tikwm.com'), isTrue);
      expect(
          CleartextPolicy.isAppControlledHost('codeload.github.com'), isFalse,
          reason: 'github.com itself is NOT in the list (user-browsable); '
              'only api.github.com is pinned');
      expect(CleartextPolicy.isAppControlledHost('api.github.com.evil.test'),
          isFalse, reason: 'suffix spoofing must not match');
    });

    test('case-insensitive and trailing-dot tolerant', () {
      expect(CleartextPolicy.isAppControlledHost('API.GitHub.COM.'), isTrue);
      expect(CleartextPolicy.isAppControlledHost(' TIKWM.COM '), isTrue);
    });

    test('user media hosts never match', () {
      expect(CleartextPolicy.isAppControlledHost('192.168.1.10'), isFalse);
      expect(CleartextPolicy.isAppControlledHost('mynas.local'), isFalse);
      expect(CleartextPolicy.isAppControlledHost(''), isFalse);
    });
  });

  group('CleartextPolicy.mustReject', () {
    test('rejects cleartext to app-controlled hosts', () {
      expect(CleartextPolicy.mustReject(
          Uri.parse('http://api.github.com/repos/x/releases')), isTrue);
      expect(CleartextPolicy.mustReject(
          Uri.parse('http://www.vpngate.net/api/iphone/')), isTrue);
    });

    test('https to the same hosts is fine', () {
      expect(CleartextPolicy.mustReject(
          Uri.parse('https://api.github.com/repos/x/releases')), isFalse);
    });

    test('cleartext to user media hosts is allowed (with UI disclosure)', () {
      expect(CleartextPolicy.mustReject(
          Uri.parse('http://192.168.1.10:5006/video.mp4')), isFalse);
      expect(CleartextPolicy.mustReject(
          Uri.parse('http://provider.example/playlist.m3u')), isFalse);
    });
  });

  group('CleartextPolicy.isInsecureUrl', () {
    test('plain http is insecure', () {
      expect(CleartextPolicy.isInsecureUrl('http://cdn.example/a.mp4'), isTrue);
      expect(CleartextPolicy.isInsecureUrl('  http://nas.local:5005/v.mkv  '),
          isTrue);
      expect(CleartextPolicy.isInsecureUrl('http://x.example/p.m3u?token=S3cReT'),
          isTrue, reason: 'tokens inside the URL must be flagged');
    });

    test('https and non-http schemes are not flagged', () {
      expect(CleartextPolicy.isInsecureUrl('https://cdn.example/a.mp4'),
          isFalse);
      expect(CleartextPolicy.isInsecureUrl('ftp://nas.local/v.mkv'), isFalse,
          reason: 'ftp is handled by its own path; not a web URL');
      expect(CleartextPolicy.isInsecureUrl('/storage/emulated/0/a.mp4'),
          isFalse);
      expect(CleartextPolicy.isInsecureUrl(''), isFalse);
      expect(CleartextPolicy.isInsecureUrl('not a url'), isFalse);
    });

    test('loopback never counts (SFTP proxy stream)', () {
      expect(CleartextPolicy.isInsecureUrl('http://127.0.0.1:8765/stream/t/1'),
          isFalse);
      expect(CleartextPolicy.isInsecureUrl('http://localhost:8765/stream/t/2'),
          isFalse);
      expect(CleartextPolicy.isInsecureUrl('http://127.5.5.5/x'), isFalse,
          reason: 'whole 127/8 is loopback');
    });
  });

  group('CleartextGuardInterceptor (live Dio, fake adapter)', () {
    late Dio dio;
    late RecordingAdapter adapter;

    setUp(() {
      adapter = RecordingAdapter();
      dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 2),
      ));
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(const CleartextGuardInterceptor());
    });

    test('blocks cleartext to app-controlled hosts before any socket opens',
        () async {
      await expectLater(
        dio.get<Object>('http://api.github.com/repos/x/y'),
        throwsA(isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<CleartextViolationException>(),
        )),
      );
      expect(adapter.requested, isEmpty,
          reason: 'the request must never reach the network layer');
    });

    test('lets https and user-media cleartext through', () async {
      final r1 = await dio.get<Object>('https://api.github.com/repos/x/y');
      expect(r1.statusCode, 200);
      final r2 = await dio.get<Object>('http://192.168.1.10:80/v.m3u8');
      expect(r2.statusCode, 200);
      expect(adapter.requested.length, 2);
    });
  });

  group('DioClient wiring', () {
    test('shared client carries the cleartext guard', () {
      final types = DioClient.instance.dio.interceptors.map((i) => i.runtimeType);
      expect(types, contains(CleartextGuardInterceptor));
    });
  });

  group('Android native policy files (parity with the Dart policy)', () {
    const cfgPath =
        'android/app/src/main/res/xml/network_security_config.xml';
    const manifestPath = 'android/app/src/main/AndroidManifest.xml';

    test('network_security_config.xml exists and is wired in the manifest',
        () {
      final cfg = File(cfgPath).readAsStringSync();
      expect(cfg, contains('<network-security-config>'));
      // User media reality: base config allows cleartext with system CAs.
      expect(cfg, contains('cleartextTrafficPermitted="true"'));
      // App-controlled hosts: pinned https-only in the native stack too.
      expect(cfg, contains('cleartextTrafficPermitted="false"'));
      expect(cfg, contains('<certificates src="system"'));

      final manifest = File(manifestPath).readAsStringSync();
      expect(manifest,
          contains('android:networkSecurityConfig="@xml/network_security_config"'));
    });

    test('every app-controlled Dart host is pinned in the XML', () {
      final cfg = File(cfgPath).readAsStringSync();
      for (final host in CleartextPolicy.appControlledHosts) {
        expect(cfg, contains('>$host<'),
            reason: '$host missing from network_security_config.xml');
      }
    });

    test('every pinned XML domain is known to the Dart policy', () {
      final cfg = File(cfgPath).readAsStringSync();
      final domainBlock = cfg
          .substring(cfg.indexOf('cleartextTrafficPermitted="false"'))
          .substring(0, cfg.indexOf('</domain-config>') -
              cfg.indexOf('cleartextTrafficPermitted="false"'));
      final xmlDomains = RegExp(r'>([a-z0-9.]+)<')
          .allMatches(domainBlock)
          .map((m) => m.group(1)!)
          .toList();
      expect(xmlDomains, isNotEmpty);
      for (final d in xmlDomains) {
        expect(CleartextPolicy.isAppControlledHost(d), isTrue,
            reason: 'XML pins "$d" but the Dart policy does not know it');
      }
    });
  });
}

/// Fake adapter: records URIs, returns a canned 200 — no network involved.
class RecordingAdapter implements HttpClientAdapter {
  final requested = <Uri>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri);
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }
}
