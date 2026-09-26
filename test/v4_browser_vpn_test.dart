import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/data/repositories/browser_repository.dart';
import 'package:drs_video/services/browser/ad_block.dart';
import 'package:drs_video/services/network/vpngate_service.dart';
import 'package:drs_video/services/vpn/vpn_service.dart';

/// Pure re-implementation of the blocklist asset parse (same rules as
/// AdBlockList._parse) used to validate the bundled asset itself.
Set<String> parseBlocklist(String raw) {
  final out = <String>{};
  for (var line in raw.split('\n')) {
    line = line.trim().toLowerCase();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.contains(' ')) line = line.split(' ').last;
    if (line.contains('.') && !line.startsWith('.')) out.add(line);
  }
  return out;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('v1.4.0 browser utils (ad blocking + URL handling)', () {
    test('subdomain matching matches base and subdomains only', () {
      final set = {'doubleclick.net', 'googlesyndication.com'};
      expect(AdBlockList.matches(set, 'doubleclick.net'), isTrue);
      expect(AdBlockList.matches(set, 'ad.doubleclick.net'), isTrue);
      expect(AdBlockList.matches(set, 'a.b.c.doubleclick.net'), isTrue);
      expect(AdBlockList.matches(set, 'notdoubleclick.net'), isFalse);
      expect(AdBlockList.matches(set, 'example.com'), isFalse);
      expect(AdBlockList.matches(set, ''), isFalse);
    });

    test('normalizeUrl: bare host, scheme, and search fallback', () {
      expect(BrowserUtils.normalizeUrl('youtube.com'), 'https://youtube.com');
      expect(BrowserUtils.normalizeUrl('http://x.tv/a.m3u8'),
          'http://x.tv/a.m3u8');
      expect(BrowserUtils.normalizeUrl('أغاني 2026'),
          contains('duckduckgo.com/?q='));
      expect(BrowserUtils.normalizeUrl(''), '');
    });

    test('isMediaStreamUrl detects direct streams only', () {
      expect(BrowserUtils.isMediaStreamUrl('https://x.com/v/movie.mp4'),
          isTrue);
      expect(
          BrowserUtils.isMediaStreamUrl('https://x.com/live/index.m3u8?tok=1'),
          isTrue);
      expect(BrowserUtils.isMediaStreamUrl('https://x.com/manifest.mpd'),
          isTrue);
      expect(BrowserUtils.isMediaStreamUrl('https://x.com/page.html'), isFalse);
      expect(BrowserUtils.isMediaStreamUrl('https://x.com/img.png'), isFalse);
    });

    test('isYouTubeWatchUrl covers all watchable hosts', () {
      expect(
          BrowserUtils.isYouTubeWatchUrl(
              'https://www.youtube.com/watch?v=abc'), isTrue);
      expect(BrowserUtils.isYouTubeWatchUrl('https://youtu.be/abc'), isTrue);
      expect(BrowserUtils.isYouTubeWatchUrl(
          'https://www.youtube.com/shorts/xyz'), isTrue);
      expect(BrowserUtils.isYouTubeWatchUrl('https://youtube.com/feed'),
          isFalse);
      expect(
          BrowserUtils.isYouTubeWatchUrl('https://tiktok.com/@a'), isFalse);
    });

    test('bundled blocklist asset is real and parseable', () {
      final f = File('assets/blocklists/ad_domains.txt');
      expect(f.existsSync(), isTrue,
          reason: 'blocklist asset must exist before build');
      final domains = parseBlocklist(f.readAsStringSync());
      // StevenBlack unified list has tens of thousands of real domains.
      expect(domains.length, greaterThan(50000));
      // Known ad/tracker hosts must be present.
      expect(domains.contains('doubleclick.net'), isTrue);
      expect(domains.contains('googlesyndication.com'), isTrue);
      // No garbage entries.
      expect(domains.any((d) => d.contains(' ') || d.startsWith('.')), isFalse);
    });

    test('bundled sites catalog is valid JSON with real entries', () {
      final f = File('assets/sites/catalog.json');
      expect(f.existsSync(), isTrue);
      final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final sites = (map['sites'] as List).cast<Map<String, dynamic>>();
      expect(sites.length, greaterThanOrEqualTo(180));
      final urls = sites.map((s) => s['u'] as String).toSet();
      expect(urls.length, sites.length, reason: 'no duplicate URLs');
      for (final s in sites) {
        expect((s['u'] as String).startsWith('https://'), isTrue,
            reason: '${s['n']} must be https');
        expect(s['n'].toString().isNotEmpty, isTrue);
      }
      // Core platforms the user explicitly asked for.
      expect(urls.contains('https://www.youtube.com'), isTrue);
      expect(urls.contains('https://www.tiktok.com'), isTrue);
    });
  });

  group('v1.4.0 VPNGate parsing', () {
    test('parseVpngateCsv skips header/comments and sorts by score', () {
      final csv = [
        '# VPN Gate public csv',
        '#HostName,IP,Score,Ping,Speed,CountryLong,ShortName,'
            '#VPNSessions,Udp,Tcp,OpenVPN_ConfigData_Base64',
        'srv-a,1.2.3.4,5000,30,5000000,Japan,JP,10,1194,443,' +
            base64Encode(utf8.encode('client\ndev tun\nremote 1.2.3.4 443')),
        'srv-b,5.6.7.8,9000,60,9000000,Korea,KR,5,1194,443,' +
            base64Encode(utf8.encode('client\ndev tun\nremote 5.6.7.8 443')),
      ].join('\n');
      final servers = parseVpngateCsv(csv);
      expect(servers.length, 2);
      expect(servers.first.hostName, 'srv-b',
          reason: 'sorted by score descending');
      expect(servers.first.config, contains('remote 5.6.7.8 443'));
    });

    test('rows without a config are dropped; speed filter applies', () {
      final csv = [
        '#x',
        'a,1.1.1.1,10,10,0,US,US,1,1194,443,',
        'b,2.2.2.2,10,10,3000000,US,US,1,1194,443,' +
            base64Encode(utf8.encode('remote 2.2.2.2 443')),
      ].join('\n');
      expect(parseVpngateCsv(csv).length, 1);
      expect(parseVpngateCsv(csv, minSpeedBps: 5000000).length, 0);
      expect(parseVpngateCsv(csv, minSpeedBps: 1000000).length, 1);
    });

    test('singleRemoteConfig keeps one remote (plugin ANR guard)', () {
      const cfg = 'client\nremote a.com 443\nremote b.com 443\ndev tun\n'
          'auth-user-pass\n';
      final reduced = VpnService.singleRemoteConfig(cfg);
      final remotes =
          reduced.split('\n').where((l) => l.startsWith('remote ')).toList();
      expect(remotes.length, 1);
      expect(remotes.first, 'remote a.com 443');
      // Single-remote configs pass through untouched (no crash).
      final single = VpnService.singleRemoteConfig('remote x 1\ndev tun');
      expect(single, 'remote x 1\ndev tun');
    });
  });

  group('v1.4.0 browser storage (DB v4)', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(inMemoryDatabasePath, version: 1);
      final batch = db.batch();
      batch.execute('''
        CREATE TABLE browser_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          url TEXT NOT NULL,
          title TEXT,
          visited_at INTEGER NOT NULL
        )''');
      batch.execute('''
        CREATE TABLE browser_bookmarks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          url TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )''');
      batch.execute('''
        CREATE TABLE user_sites (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          url TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL
        )''');
      await batch.commit(noResult: true);
    });

    tearDown(() => db.close());

    test('history dedupes by URL and caps rows', () async {
      final repo = BrowserRepository(db);
      await repo.addHistory('https://a.com', 'A');
      await repo.addHistory('https://a.com', 'A again');
      await repo.addHistory('https://b.com', 'B');
      final rows = await repo.history();
      expect(rows.length, 2);
      expect(rows.first.url, 'https://b.com', reason: 'newest first');
      // Cap enforcement.
      for (var i = 0; i < (AppConstants.browserHistoryCap + 50); i++) {
        await repo.addHistory('https://c.com?p=$i', 'C$i');
      }
      final capped = await repo.history(limit: 1000);
      expect(capped.length, AppConstants.browserHistoryCap);
    });

    test('bookmarks add/remove/isBookmarked round trip', () async {
      final repo = BrowserRepository(db);
      expect(await repo.isBookmarked('https://x.com'), isFalse);
      await repo.addBookmark('https://x.com', 'X');
      expect(await repo.isBookmarked('https://x.com'), isTrue);
      // Re-adding the same URL does not duplicate (UNIQUE + replace).
      await repo.addBookmark('https://x.com', 'X2');
      expect((await repo.bookmarks()).length, 1);
      await repo.removeBookmark('https://x.com');
      expect(await repo.isBookmarked('https://x.com'), isFalse);
    });

    test('user sites CRUD', () async {
      final repo = BrowserRepository(db);
      final site = await repo.addUserSite('MySite', 'https://my.site');
      expect(site, isNotNull);
      final all = await repo.userSites();
      expect(all.length, 1);
      expect(all.first.name, 'MySite');
      await repo.removeUserSite(site!.id);
      expect((await repo.userSites()).length, 0);
    });

    test('DatabaseService constant bumped to v4', () {
      expect(AppConstants.dbVersion, 4);
      expect(AppConstants.appVersion, '1.4.1');
    });
  });
}
