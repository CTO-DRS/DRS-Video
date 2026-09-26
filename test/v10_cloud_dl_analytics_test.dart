import 'package:flutter_test/flutter_test.dart';

import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/services/backup/cloud_backup_service.dart';
import 'package:drs_video/services/smart/analytics_export.dart';

void main() {
  // =====================================================================
  // CloudBackupConfig (v1.8.0)
  // =====================================================================
  group('CloudBackupConfig', () {
    test('effective port falls back to protocol defaults', () {
      // Default is TLS-on (safer default) → 443.
      expect(
        const CloudBackupConfig(kind: CloudBackupKind.webdav, host: 'x')
            .effectivePort,
        443,
      );
      expect(
        const CloudBackupConfig(
                kind: CloudBackupKind.webdav, host: 'x', useTls: false)
            .effectivePort,
        80,
      );
      expect(
        const CloudBackupConfig(kind: CloudBackupKind.sftp, host: 'x')
            .effectivePort,
        22,
      );
      // Explicit port always wins.
      expect(
        const CloudBackupConfig(
                kind: CloudBackupKind.sftp, host: 'x', port: 2222)
            .effectivePort,
        2222,
      );
    });

    test('serialize → tryParse round-trips every field', () {
      const cfg = CloudBackupConfig(
        kind: CloudBackupKind.sftp,
        host: 'nas.local',
        port: 2022,
        username: 'user',
        password: 'pass',
        useTls: false,
        basePath: '/media',
      );
      final parsed = CloudBackupConfig.tryParse(cfg.serialize());
      expect(parsed, isNotNull);
      expect(parsed!.kind, CloudBackupKind.sftp);
      expect(parsed.host, 'nas.local');
      expect(parsed.port, 2022);
      expect(parsed.username, 'user');
      expect(parsed.password, 'pass');
      expect(parsed.basePath, '/media');
    });

    test('junk inputs are rejected, never throw', () {
      expect(CloudBackupConfig.tryParse(null), isNull);
      expect(CloudBackupConfig.tryParse(''), isNull);
      expect(CloudBackupConfig.tryParse('not json'), isNull);
      expect(CloudBackupConfig.tryParse('[]'), isNull);
      expect(CloudBackupConfig.tryParse('{"kind":"webdav"}'), isNull,
          reason: 'missing host');
      expect(CloudBackupConfig.tryParse('{"host":""}'), isNull,
          reason: 'blank host');
    });

    test('unknown kind falls back to webdav', () {
      final cfg = CloudBackupConfig.tryParse(
          '{"kind":"telegram","host":"h.io"}');
      expect(cfg, isNotNull);
      expect(cfg!.kind, CloudBackupKind.webdav);
    });
  });

  group('CloudBackupService remote paths', () {
    test('remote dir joins base path safely', () {
      expect(
        cloudBackupRemoteDirForTesting(
            const CloudBackupConfig(kind: CloudBackupKind.webdav, host: 'h')),
        '/drs-video-backups',
      );
      expect(
        cloudBackupRemoteDirForTesting(const CloudBackupConfig(
            kind: CloudBackupKind.webdav, host: 'h', basePath: '/dav')),
        '/dav/drs-video-backups',
      );
      expect(
        cloudBackupRemoteDirForTesting(const CloudBackupConfig(
            kind: CloudBackupKind.webdav, host: 'h', basePath: '/dav/')),
        '/dav/drs-video-backups',
        reason: 'trailing slash normalized',
      );
    });

    test('webdavBaseUrl omits default ports, keeps custom ones', () {
      expect(
        const CloudBackupConfig(
                kind: CloudBackupKind.webdav, host: 'h.io', useTls: false)
            .webdavBaseUrl,
        'http://h.io',
      );
      expect(
        const CloudBackupConfig(
                kind: CloudBackupKind.webdav,
                host: 'h.io',
                port: 5005,
                useTls: false)
            .webdavBaseUrl,
        'http://h.io:5005',
      );
      expect(
        const CloudBackupConfig(
                kind: CloudBackupKind.webdav,
                host: 'h.io',
                useTls: true,
                basePath: '/dav')
            .webdavBaseUrl,
        'https://h.io/dav',
      );
    });
  });

  group('CloudBackupPolicy.shouldAutoBackup', () {
    const cfg = CloudBackupConfig(kind: CloudBackupKind.webdav, host: 'h');
    final now = DateTime(2026, 9, 27, 12);

    test('disabled or unconfigured → never', () {
      expect(
          CloudBackupPolicy.shouldAutoBackup(
              enabled: false, config: cfg, lastBackupAt: null, now: now),
          isFalse);
      expect(
          CloudBackupPolicy.shouldAutoBackup(
              enabled: true, config: null, lastBackupAt: null, now: now),
          isFalse);
    });

    test('first run and due backups fire', () {
      expect(
          CloudBackupPolicy.shouldAutoBackup(
              enabled: true, config: cfg, lastBackupAt: null, now: now),
          isTrue);
      expect(
          CloudBackupPolicy.shouldAutoBackup(
            enabled: true,
            config: cfg,
            lastBackupAt: now.subtract(const Duration(hours: 25)),
            now: now,
          ),
          isTrue);
    });

    test('recent backup does not fire again', () {
      expect(
          CloudBackupPolicy.shouldAutoBackup(
            enabled: true,
            config: cfg,
            lastBackupAt: now.subtract(const Duration(hours: 2)),
            now: now,
          ),
          isFalse);
    });
  });

  // =====================================================================
  // AnalyticsExport (v1.8.0)
  // =====================================================================
  group('AnalyticsExport.csvEscape', () {
    test('plain values pass through', () {
      expect(AnalyticsExport.csvEscape('hello'), 'hello');
      expect(AnalyticsExport.csvEscape(42), '42');
      expect(AnalyticsExport.csvEscape(null), '');
    });

    test('commas, quotes and newlines are wrapped + doubled', () {
      expect(AnalyticsExport.csvEscape('a,b'), '"a,b"');
      expect(AnalyticsExport.csvEscape('say "hi"'), '"say ""hi"""');
      expect(AnalyticsExport.csvEscape('line1\nline2'), '"line1\nline2"');
      expect(AnalyticsExport.csvEscape('cr\rlf'), '"cr\rlf"');
    });
  });

  group('AnalyticsExport.buildHistoryCsv', () {
    test('header first, one row per item, progress merged', () {
      final items = [
        MediaItem(
          id: 'a',
          title: 'Comma, Title',
          uri: 'https://x.io/a.mp4',
          type: MediaItemType.network,
          durationMs: 60000,
          width: 1920,
          height: 1080,
        )..isFavorite = true,
        MediaItem(
          id: 'b',
          title: 'Never Played',
          uri: 'https://x.io/b.mp4',
          type: MediaItemType.local,
        ),
      ];
      final csv = AnalyticsExport.buildHistoryCsv(items, {
        'a': WatchProgress(
          itemId: 'a',
          positionMs: 30000,
          durationMs: 60000,
          completed: false,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
      });

      final lines = csv.trim().split('\n');
      expect(lines.first, AnalyticsExport.header.join(','));
      expect(lines.length, 3, reason: 'header + 2 items');

      // Item 'a': escaped title, favorite=1, progress columns filled.
      expect(lines[1], contains('"Comma, Title"'));
      expect(lines[1], contains(',1,'));
      expect(lines[1], contains('30000'));
      expect(lines[1], contains(',0,'), reason: 'not completed');

      // Item 'b': no progress → blank position/completed/updated columns.
      expect(lines[2], contains('Never Played'));
      expect(lines[2].endsWith(',,,'), isTrue,
          reason: 'blank position/completed/updated_at');
    });

    test('empty inventory yields header-only file', () {
      final csv = AnalyticsExport.buildHistoryCsv(const [], {});
      expect(csv.trim().split('\n').length, 1);
      expect(csv, startsWith('title,uri,type,'));
    });
  });
}
