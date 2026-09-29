import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/core/storage/database_service.dart';
import 'package:drs_video/core/storage/preferences_service.dart';
import 'package:drs_video/core/storage/secure_credentials.dart';
import 'package:drs_video/data/models/stream_models.dart';
import 'package:drs_video/data/repositories/stream_repositories.dart';
import 'package:drs_video/services/security/host_key_trust_store.dart';

/// P2 security regression tests (audit fixes C1/C2/C3).
///
/// C1 — credentials moved from plaintext (sqflite `nas_servers.password` /
/// the `cloud_backup_config` JSON blob in prefs) into a vault.
/// C2 — backup export/import must never carry secrets or trust anchors.
/// C3 — SSH host keys are pinned TOFU-style; a key change rejects the
/// handshake and records the presented fingerprint for the re-trust flow.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureCredentialsStore (C1)', () {
    late SecureCredentialsStore store;
    late InMemorySecretVault vault;

    setUp(() {
      vault = InMemorySecretVault();
      store = SecureCredentialsStore(vault: vault);
    });

    test('nas password round-trips; null clears the entry', () async {
      expect(await store.nasPassword('srv1'), isNull);
      await store.setNasPassword('srv1', 's3cret');
      expect(await store.nasPassword('srv1'), 's3cret');
      await store.setNasPassword('srv1', null);
      expect(await store.nasPassword('srv1'), isNull);
      expect(vault.containsKey('nas_pwd_srv1'), isFalse);
    });

    test('empty password is treated as "no secret"', () async {
      await store.setNasPassword('srv1', '');
      expect(await store.nasPassword('srv1'), isNull);
    });

    test('cloud backup password round-trips; null clears', () async {
      expect(await store.cloudBackupPassword(), isNull);
      await store.setCloudBackupPassword('dav-pass');
      expect(await store.cloudBackupPassword(), 'dav-pass');
      await store.setCloudBackupPassword(null);
      expect(await store.cloudBackupPassword(), isNull);
    });

    test('migrateNasPasswords moves plaintext rows into the vault',
        () async {
      final db = await DatabaseService.instance.database;
      await db.insert('nas_servers', {
        'id': 'nassrv:plain1',
        'name': 'Old',
        'protocol': 'sftp',
        'host': '192.168.1.10',
        'port': 22,
        'username': 'admin',
        'password': 'legacy-plain',
        'base_path': '/',
        'use_tls': 0,
        'created_at': 1,
      });
      final moved = await store.migrateNasPasswords(db);
      expect(moved, 1);
      // Secret now lives in the vault only.
      expect(await store.nasPassword('nassrv:plain1'), 'legacy-plain');
      final rows = await db.query('nas_servers',
          where: 'id = ?', whereArgs: ['nassrv:plain1']);
      expect(rows.single['password'], '');

      // Idempotent: nothing left to move.
      expect(await store.migrateNasPasswords(db), 0);
    });

    test('migrateCloudBackupPassword strips the blob and fills the vault',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs =
          PreferencesService(await SharedPreferences.getInstance());
      prefs.cloudBackupConfigRaw = jsonEncode({
        'kind': 'sftp',
        'host': 'nas.local',
        'port': 22,
        'username': 'admin',
        'password': 'blob-secret',
        'useTls': false,
        'basePath': '',
      });
      final moved = await store.migrateCloudBackupPassword(prefs);
      expect(moved, isTrue);
      expect(await store.cloudBackupPassword(), 'blob-secret');
      final raw = prefs.cloudBackupConfigRaw!;
      expect(raw.contains('blob-secret'), isFalse,
          reason: 'plaintext must be gone from prefs');
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      expect(decoded['password'], '');
      expect(decoded['host'], 'nas.local');
      expect(decoded['username'], 'admin');
      // Already migrated: no-op.
      expect(await store.migrateCloudBackupPassword(prefs), isFalse);
    });
  });

  group('NasRepository vault wiring (C1)', () {
    late SecureCredentialsStore store;
    late NasRepository repo;

    setUp(() {
      store = SecureCredentialsStore(vault: InMemorySecretVault());
      repo = NasRepository(DatabaseService.instance, credentials: store);
    });

    tearDown(() async {
      await DatabaseService.instance.deleteAllData();
    });

    NasServer server(String id) => NasServer(
          id: id,
          name: 'Home NAS',
          protocol: NasProtocol.sftp,
          host: '192.168.1.10',
          port: 22,
          username: 'admin',
          password: 'row-secret',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        );

    test('save stores the secret in the vault, the row stays clean',
        () async {
      await repo.save(server('nassrv:a'));
      expect(await store.nasPassword('nassrv:a'), 'row-secret');
      final db = await DatabaseService.instance.database;
      final rows = await db
          .query('nas_servers', where: 'id = ?', whereArgs: ['nassrv:a']);
      expect(rows.single['password'], '',
          reason: 'plaintext must never reach the database');
    });

    test('servers() hydrates the password from the vault', () async {
      await repo.save(server('nassrv:b'));
      final list = await repo.servers();
      expect(list, hasLength(1));
      expect(list.single.password, 'row-secret');
      expect(list.single.host, '192.168.1.10');
    });

    test('delete removes the DB row and the vault secret', () async {
      await repo.save(server('nassrv:c'));
      await repo.delete('nassrv:c');
      expect(await store.nasPassword('nassrv:c'), isNull);
      expect(await repo.servers(), isEmpty);
    });

    test('legacy plaintext rows migrate + hydrate on first servers()',
        () async {
      final db = await DatabaseService.instance.database;
      await db.insert('nas_servers', {
        'id': 'nassrv:legacy',
        'name': 'Legacy',
        'protocol': 'webdav',
        'host': 'nas.lan',
        'port': 5005,
        'username': 'u',
        'password': 'old-plain',
        'base_path': '/',
        'use_tls': 1,
        'created_at': 2,
      });
      final list = await repo.servers();
      expect(list.single.password, 'old-plain',
          reason: 'handed to the caller from the vault');
      expect(await store.nasPassword('nassrv:legacy'), 'old-plain');
      final rows = await db.query('nas_servers');
      expect(rows.single['password'], '',
          reason: 'plaintext column blanked after migration');
    });
  });

  group('HostKeyTrustStore + SshTofuVerifier (C3)', () {
    late HostKeyTrustStore trust;
    SharedPreferences? prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      trust = HostKeyTrustStore(prefs!);
    });

    Uint8List fp(String fingerprint) =>
        Uint8List.fromList(utf8.encode(fingerprint));

    test('first use trusts and remembers (TOFU)', () async {
      final v = SshTofuVerifier(trust, 'nas.local', 22, label: 'nas');
      final ok = await v.call('ssh-ed25519', fp('SHA256:AAAA'));
      expect(ok, isTrue);
      expect(trust.trustedFingerprint('nas.local', 22), 'SHA256:AAAA');
    });

    test('same fingerprint is accepted', () async {
      await trust.trust('nas.local', 22, 'SHA256:BBBB');
      final v = SshTofuVerifier(trust, 'nas.local', 22, label: 'nas');
      expect(await v.call('ssh-ed25519', fp('SHA256:BBBB')), isTrue);
    });

    test('changed fingerprint rejects + records the presented key',
        () async {
      await trust.trust('nas.local', 22, 'SHA256:ORIGINAL');
      final v = SshTofuVerifier(trust, 'nas.local', 22, label: 'nas');
      final ok = await v.call('ssh-ed25519', fp('SHA256:IMPOSTOR'));
      expect(ok, isFalse,
          reason: 'a changed host key must fail the handshake');
      expect(trust.lastMismatchFingerprint('nas.local', 22),
          'SHA256:IMPOSTOR');
      // The pinned anchor is untouched — the impostor never became trusted.
      expect(trust.trustedFingerprint('nas.local', 22), 'SHA256:ORIGINAL');
    });

    test('trust() overwrites the anchor and clears the mismatch', () async {
      await trust.trust('nas.local', 22, 'SHA256:OLD');
      await trust.recordMismatch('nas.local', 22, 'SHA256:NEW');
      await trust.trust('nas.local', 22, 'SHA256:NEW');
      expect(trust.trustedFingerprint('nas.local', 22), 'SHA256:NEW');
      expect(trust.lastMismatchFingerprint('nas.local', 22), isNull);
    });

    test('forget() removes the anchor (re-trust path)', () async {
      await trust.trust('nas.local', 22, 'SHA256:AAAA');
      await trust.forget('nas.local', 22);
      expect(trust.isTrusted('nas.local', 22), isFalse);
      final v = SshTofuVerifier(trust, 'nas.local', 22, label: 'nas');
      expect(await v.call('ssh-ed25519', fp('SHA256:BBBB')), isTrue,
          reason: 'after forgetting, the next connect re-runs TOFU');
    });

    test('hosts are case-insensitive; ports are part of the anchor',
        () async {
      await trust.trust('NAS.local', 22, 'SHA256:AAAA');
      expect(trust.trustedFingerprint('nas.LOCAL', 22), 'SHA256:AAAA');
      expect(trust.trustedFingerprint('nas.local', 2222), isNull);
    });
  });

  group('Backup secret exclusion (C2)', () {
    late PreferencesService prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PreferencesService(await SharedPreferences.getInstance());
    });

    test('exportSnapshot never contains credentials or PIN hashes',
        () async {
      await prefs.raw.setString(PrefKeys.cloudBackupConfig,
          '{"kind":"sftp","host":"h","password":"topsecret"}');
      await prefs.raw.setString(PrefKeys.appLockHash, 'salt:hash');
      await prefs.raw.setString(PrefKeys.vaultHash, 'salt:hash');
      await prefs.raw.setString('ssh_hostkey_nas.local_22', 'SHA256:AAAA');
      await prefs.raw.setString(PrefKeys.defaultQuality, '1080p');

      final snap = prefs.exportSnapshot();
      expect(snap.containsKey(PrefKeys.cloudBackupConfig), isFalse);
      expect(snap.containsKey(PrefKeys.appLockHash), isFalse);
      expect(snap.containsKey(PrefKeys.vaultHash), isFalse);
      expect(snap.containsKey('ssh_hostkey_nas.local_22'), isFalse,
          reason: 'trust anchors stay device-local');
      expect(snap[PrefKeys.defaultQuality], '1080p');
      expect(jsonEncode(snap).contains('topsecret'), isFalse);
    });

    test('applySnapshot refuses secrets (legacy/crafted backups)', () async {
      final applied = await prefs.applySnapshot({
        PrefKeys.cloudBackupConfig:
            '{"kind":"sftp","host":"evil","password":"x"}',
        PrefKeys.appLockHash: 'attacker:hash',
        PrefKeys.vaultHash: 'attacker:hash',
        'ssh_hostkey_evil_22': 'SHA256:EVIL',
        PrefKeys.defaultQuality: '720p',
      });
      expect(applied, 1,
          reason: 'only the innocuous setting is applied');
      expect(prefs.raw.getString(PrefKeys.cloudBackupConfig), isNull);
      expect(prefs.raw.getString(PrefKeys.appLockHash), isNull);
      expect(prefs.raw.getString(PrefKeys.vaultHash), isNull);
      expect(prefs.raw.getString('ssh_hostkey_evil_22'), isNull);
      expect(prefs.raw.getString(PrefKeys.defaultQuality), '720p');
    });

    test('stray vault-style keys are excluded from snapshots too', () async {
      // Defense in depth: production writes secrets only to the vault,
      // but if a vault-style key ever landed in prefs it must not leak
      // into a backup file either.
      await prefs.raw.setString('nas_pwd_nassrv:a', 'accident');
      await prefs.raw.setString('cloud_backup_pwd', 'accident');
      final snap = prefs.exportSnapshot();
      expect(snap.containsKey('nas_pwd_nassrv:a'), isFalse);
      expect(snap.containsKey('cloud_backup_pwd'), isFalse);
    });
  });
}
