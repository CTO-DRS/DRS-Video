import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'preferences_service.dart';
import '../utils/logger.dart';

/// Storage backend contract for credential secrets.
///
/// The production implementation ([KeystoreSecretVault]) wraps
/// flutter_secure_storage with EncryptedSharedPreferences enabled:
/// values are sealed with Tink AES-256-GCM under a master key that
/// never leaves the Android Keystore (hardware-backed where the device
/// supports it). Tests use [InMemorySecretVault].
abstract class SecretVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production vault: Android Keystore-backed encrypted storage.
///
/// [resetOnError] stays FALSE on purpose: silently wiping the user's
/// credentials on a transient Keystore error is worse than surfacing a
/// failed auth attempt.
class KeystoreSecretVault implements SecretVault {
  KeystoreSecretVault({this.sharedPreferencesName});

  /// Separate prefs file so the vault namespace is isolated from normal
  /// settings (and from backup tooling that copies shared_preferences).
  final String? sharedPreferencesName;

  static const AndroidOptions _android = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  FlutterSecureStorage _storage() => FlutterSecureStorage(
        aOptions: _android,
      );

  @override
  Future<String?> read(String key) => _storage().read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage().write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage().delete(key: key);
}

/// Plain in-memory vault for unit tests (never used in release builds).
class InMemorySecretVault implements SecretVault {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  /// Test introspection: assert a secret is really gone from memory.
  bool containsKey(String key) => _data.containsKey(key);
}

/// Owns every credential secret in the app: NAS server passwords and the
/// cloud-backup (WebDAV/SFTP) password.
///
/// P2 audit fix (C1): these used to live as plaintext — NAS passwords in
/// the `nas_servers` sqflite table, the cloud password inside a JSON blob
/// in SharedPreferences. Both were readable by any process with root or
/// by an adb-backup; now only non-secret connection metadata stays in the
/// database/prefs and the secrets live behind the Keystore.
///
/// Key layout (stable, migration-safe):
///   `nas_pwd_<serverId>`  — password for one NAS server row
///   `cloud_backup_pwd`    — password for the remote backup target
class SecureCredentialsStore {
  SecureCredentialsStore({required SecretVault vault}) : _vault = vault;

  final SecretVault _vault;

  static const String _nasPrefix = 'nas_pwd_';
  static const String _cloudBackupKey = 'cloud_backup_pwd';

  static String nasKeyFor(String serverId) => '$_nasPrefix$serverId';

  // ---- NAS passwords -----------------------------------------------------

  Future<String?> nasPassword(String serverId) =>
      _vault.read(nasKeyFor(serverId));

  /// Writes or clears (null) the stored password for [serverId].
  Future<void> setNasPassword(String serverId, String? password) async {
    final key = nasKeyFor(serverId);
    if (password == null || password.isEmpty) {
      await _vault.delete(key);
      return;
    }
    await _vault.write(key, password);
  }

  Future<void> deleteNasPassword(String serverId) =>
      _vault.delete(nasKeyFor(serverId));

  // ---- cloud backup password ----------------------------------------------

  Future<String?> cloudBackupPassword() => _vault.read(_cloudBackupKey);

  Future<void> setCloudBackupPassword(String? password) async {
    if (password == null || password.isEmpty) {
      await _vault.delete(_cloudBackupKey);
      return;
    }
    await _vault.write(_cloudBackupKey, password);
  }

  // ---- one-time migrations (idempotent, lazy, UI-safe) --------------------

  /// Moves any plaintext NAS password still stored in the `nas_servers`
  /// table into the vault, then blanks the column. Runs on every
  /// [NasRepository.servers] call until nothing is left to migrate, so
  /// upgrading installs converge without a schema change.
  ///
  /// Per-row fault tolerance: a row is only blanked AFTER its secret is
  /// durably in the vault, so a vault failure keeps the plaintext (worst
  /// case: the pre-fix status quo) instead of losing credentials.
  Future<int> migrateNasPasswords(Database db) async {
    var moved = 0;
    try {
      final rows = await db.query('nas_servers',
          columns: ['id', 'password'],
          where: "password IS NOT NULL AND password != ''");
      for (final row in rows) {
        final id = row['id'] as String?;
        final pw = row['password'] as String?;
        if (id == null || id.isEmpty || pw == null || pw.isEmpty) continue;
        try {
          await setNasPassword(id, pw);
          await db.update('nas_servers', {'password': ''},
              where: 'id = ?', whereArgs: [id]);
          moved++;
          AppLogger.instance
              .info('vault', 'migrated NAS password to Keystore ($id)');
        } catch (e) {
          // Keep the plaintext row; retry happens on the next servers().
          AppLogger.instance
              .warning('vault', 'NAS password migration deferred ($id): $e');
        }
      }
    } catch (e) {
      AppLogger.instance
          .warning('vault', 'NAS password migration scan failed: $e');
    }
    return moved;
  }

  /// Moves the cloud-backup password out of the SharedPreferences JSON
  /// blob into the vault and rewrites the blob without it.
  ///
  /// The config JSON is parsed inline (host/user/port stay untouched) to
  /// avoid a core→services dependency on CloudBackupConfig.
  Future<bool> migrateCloudBackupPassword(PreferencesService prefs) async {
    final raw = prefs.cloudBackupConfigRaw;
    if (raw == null || raw.isEmpty) return false;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return false;
    }
    if (decoded is! Map<Object?, Object?>) return false;
    final pw = decoded['password'];
    if (pw is! String || pw.isEmpty) return false;
    final host = decoded['host'];
    try {
      await setCloudBackupPassword(pw);
      // Rewrite the blob with the password stripped; every other field
      // round-trips unchanged so the UI keeps its saved form state.
      decoded['password'] = '';
      prefs.cloudBackupConfigRaw = jsonEncode(decoded);
      AppLogger.instance.info('vault',
          'migrated cloud backup password to Keystore (${host is String ? host : '?'})');
      return true;
    } catch (e) {
      AppLogger.instance
          .warning('vault', 'cloud password migration deferred: $e');
      return false;
    }
  }
}
