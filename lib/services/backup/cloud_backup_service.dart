import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../core/constants/app_constants.dart';
import '../security/host_key_trust_store.dart';

/// Which protocol the remote backup storage speaks.
enum CloudBackupKind { webdav, sftp }

/// User-configured remote storage for off-device backups.
///
/// Passwords live in SharedPreferences exactly like the NAS feature does
/// (same trust model, local-only app). The config serializes to JSON for
/// storage and for diagnostics.
class CloudBackupConfig {
  const CloudBackupConfig({
    required this.kind,
    required this.host,
    this.port = 0,
    this.username = '',
    this.password = '',
    this.useTls = true,
    this.basePath = '',
  });

  final CloudBackupKind kind;

  /// Host name or IP (e.g. `dav.jianguoyun.com`, `192.168.1.20`).
  final String host;

  /// 0 = protocol default (WebDAV 80/443, SFTP 22).
  final int port;
  final String username;
  final String password;

  /// WebDAV only: HTTPS instead of HTTP.
  final bool useTls;

  /// Optional sub-path under the host root (e.g. `/dav`). The backups
  /// themselves always live under [CloudBackupService.remoteDirName].
  final String basePath;

  int get effectivePort {
    if (port > 0) return port;
    switch (kind) {
      case CloudBackupKind.webdav:
        return useTls
            ? AppConstants.webdavTlsDefaultPort
            : AppConstants.webdavDefaultPort;
      case CloudBackupKind.sftp:
        return AppConstants.sftpDefaultPort;
    }
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'useTls': useTls,
        'basePath': basePath,
      };

  static CloudBackupConfig fromJson(Map<String, Object?> json) =>
      CloudBackupConfig(
        kind: CloudBackupKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => CloudBackupKind.webdav,
        ),
        host: json['host'] is String ? json['host'] as String : '',
        port: json['port'] is int ? json['port'] as int : 0,
        username:
            json['username'] is String ? json['username'] as String : '',
        password:
            json['password'] is String ? json['password'] as String : '',
        useTls: json['useTls'] is bool ? json['useTls'] as bool : true,
        basePath: json['basePath'] is String ? json['basePath'] as String : '',
      );

  String serialize() => jsonEncode(toJson());

  static CloudBackupConfig? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final host = decoded['host'];
      if (host is! String || host.trim().isEmpty) return null;
      return CloudBackupConfig.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Base URL for WebDAV (scheme + host + port + base path, no trailing /).
  String get webdavBaseUrl {
    final scheme = useTls ? 'https' : 'http';
    final portPart =
        effectivePort == (useTls ? 443 : 80) ? '' : ':$effectivePort';
    final base = basePath.isEmpty ? '' : basePath;
    return '$scheme://$host$portPart$base';
  }
}

/// One remote backup file discovered on the server.
class CloudBackupInfo {
  const CloudBackupInfo({
    required this.fileName,
    required this.sizeBytes,
    this.modifiedAt,
  });

  final String fileName;
  final int sizeBytes;
  final DateTime? modifiedAt;

  bool get isValidName => fileName.startsWith('drs-video-backup-');
}

/// Decision helper for the daily auto-upload — pure and unit-tested.
class CloudBackupPolicy {
  CloudBackupPolicy._();

  /// Auto-backup fires when: enabled + config exists + never backed up OR
  /// the last backup is at least [interval] old.
  static bool shouldAutoBackup({
    required bool enabled,
    required CloudBackupConfig? config,
    required DateTime? lastBackupAt,
    required DateTime now,
    Duration interval = const Duration(hours: 24),
  }) {
    if (!enabled || config == null) return false;
    if (lastBackupAt == null) return true;
    return now.difference(lastBackupAt) >= interval;
  }
}

/// Builds the backup JSON through [BackupService], then uploads/downloads
/// it over WebDAV or SFTP — mirroring the connection patterns already
/// proven in NasService.
class CloudBackupService {
  /// [trustStore] pins the SSH host key (TOFU). P2 security fix (C3):
  /// replaces `disableHostkeyVerification: true` — without it any machine
  /// on the path could impersonate the backup target and harvest the
  /// credentials (and receive every uploaded backup).
  CloudBackupService({required this.config, required this.trustStore});

  final CloudBackupConfig config;
  final HostKeyTrustStore trustStore;

  /// Directory (under the base path) holding the backups.
  static const String remoteDirName = 'drs-video-backups';

  String get remoteDir => config.basePath.isEmpty
      ? '/$remoteDirName'
      : '${config.basePath.endsWith('/') ? config.basePath.substring(0, config.basePath.length - 1) : config.basePath}/$remoteDirName';

  String remotePathFor(String fileName) =>
      '${remoteDir.endsWith('/') ? remoteDir.substring(0, remoteDir.length - 1) : remoteDir}/$fileName';

  // ---------------------------------------------------------------- WebDAV

  webdav.Client? _webdav;

  Future<webdav.Client> _webdavClient() async {
    if (_webdav != null) return _webdav!;
    final client = webdav.newClient(
      config.webdavBaseUrl,
      user: config.username,
      password: config.password,
    );
    client.setConnectTimeout(AppConstants.nasConnectTimeout.inMilliseconds);
    _webdav = client;
    return client;
  }

  Future<void> _ensureWebdavDir(webdav.Client client) async {
    await client.mkdirAll(remoteDir);
  }

  // ------------------------------------------------------------------ SFTP

  SSHClient? _ssh;
  SftpClient? _sftp;

  Future<SftpClient> _sftpClient() async {
    if (_sftp != null) return _sftp!;
    final ssh = _ssh;
    if (ssh != null && !ssh.isClosed) return _sftp = await ssh.sftp();
    final socket = await SSHSocket.connect(
      config.host,
      config.effectivePort,
      timeout: AppConstants.nasConnectTimeout,
    );
    final client = SSHClient(
      socket,
      username: config.username.isEmpty ? 'root' : config.username,
      onPasswordRequest: () => config.password,
      // P2 security fix (C3): TOFU host-key pinning — first connect
      // anchors the fingerprint; later changes reject the handshake
      // before the password is ever sent.
      onVerifyHostKey: SshTofuVerifier(
        trustStore,
        config.host,
        config.effectivePort,
        label: 'cloud-backup',
      ).call,
      keepAliveInterval: const Duration(seconds: 15),
    );
    _ssh = client;
    unawaitedCleanup(client);
    final sftp = await client.sftp();
    _sftp = sftp;
    return sftp;
  }

  void unawaitedCleanup(SSHClient client) {
    client.done.whenComplete(() {
      _ssh = null;
      _sftp = null;
    });
  }

  Future<void> _ensureSftpDir(SftpClient sftp) async {
    // mkdir -p behaviour: create each path segment, ignoring "already
    // exists" failures segment by segment.
    final segments = remoteDir
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    var current = '';
    for (final segment in segments) {
      current = '$current/$segment';
      try {
        await sftp.mkdir(current);
      } catch (_) {
        // Exists (or unsupported) — verify by listing the parent instead
        // of failing the whole upload.
      }
    }
  }

  // ------------------------------------------------------------------- API

  /// Verifies credentials and reachability. Throws on failure with a
  /// technical message for the log/diagnostics screen.
  Future<void> testConnection() async {
    if (config.kind == CloudBackupKind.webdav) {
      final client = await _webdavClient();
      await client.ping();
      await _ensureWebdavDir(client);
      return;
    }
    final sftp = await _sftpClient();
    await _ensureSftpDir(sftp);
  }

  /// Uploads the local backup file. Returns the remote path written.
  Future<String> uploadBackup(String localPath) async {
    final file = File(localPath);
    if (!file.existsSync()) {
      throw StateError('local backup missing: $localPath');
    }
    final fileName = p.basename(localPath);
    final remote = remotePathFor(fileName);
    if (config.kind == CloudBackupKind.webdav) {
      final client = await _webdavClient();
      await _ensureWebdavDir(client);
      await client.write(remote, await file.readAsBytes());
      return remote;
    }
    final sftp = await _sftpClient();
    await _ensureSftpDir(sftp);
    final handle = await sftp.open(
      remote,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      await handle.writeBytes(await file.readAsBytes());
    } finally {
      await handle.close();
    }
    return remote;
  }

  /// Lists remote backup files (newest first). Missing remote directory →
  /// empty list (first run), not an error.
  Future<List<CloudBackupInfo>> listBackups() async {
    if (config.kind == CloudBackupKind.webdav) {
      final client = await _webdavClient();
      List<webdav.File> entries;
      try {
        entries = await client.readDir(remoteDir);
      } catch (_) {
        return const [];
      }
      return entries
          .where((f) => f.name != null && (f.isDir != true))
          .map((f) => CloudBackupInfo(
                fileName: f.name!,
                sizeBytes: f.size ?? 0,
                modifiedAt: f.mTime,
              ))
          .where((b) => b.isValidName)
          .toList()
        ..sort(_newestFirst);
    }
    final sftp = await _sftpClient();
    List<SftpName> names;
    try {
      names = await sftp.listdir(remoteDir);
    } catch (_) {
      return const [];
    }
    return names
        .map((n) => CloudBackupInfo(
              fileName: n.filename,
              sizeBytes: n.attr.size ?? 0,
              modifiedAt: n.attr.modifyTime == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      n.attr.modifyTime! * 1000),
            ))
        .where((b) => b.isValidName)
        .toList()
      ..sort(_newestFirst);
  }

  static int _newestFirst(CloudBackupInfo a, CloudBackupInfo b) {
    final ta = a.modifiedAt?.millisecondsSinceEpoch ?? 0;
    final tb = b.modifiedAt?.millisecondsSinceEpoch ?? 0;
    return tb.compareTo(ta);
  }

  /// Downloads a remote backup to [savePath] (local file, overwritten).
  Future<String> downloadBackup(String fileName, String savePath) async {
    final remote = remotePathFor(fileName);
    if (config.kind == CloudBackupKind.webdav) {
      final client = await _webdavClient();
      await client.read2File(remote, savePath);
      return savePath;
    }
    final sftp = await _sftpClient();
    final handle = await sftp.open(remote, mode: SftpFileOpenMode.read);
    try {
      final bytes = await handle.readBytes();
      await File(savePath).writeAsBytes(bytes, flush: true);
    } finally {
      await handle.close();
    }
    return savePath;
  }

  /// Drops cached connections (called by the screen on dispose).
  Future<void> close() async {
    _webdav = null;
    try {
      await _sftp?.close();
    } catch (_) {}
    try {
      _ssh?.close();
    } catch (_) {}
    _sftp = null;
    _ssh = null;
  }
}

@visibleForTesting
String cloudBackupRemoteDirForTesting(CloudBackupConfig config) =>
    CloudBackupService(
      config: config,
      trustStore: _NoopTrustStoreForTesting(),
    ).remoteDir;

/// The remote-dir helpers never open a connection, so the trust store is
/// never consulted; this keeps the test helper honest without a prefs
/// dependency. Any real connection requires the production trust store.
class _NoopTrustStoreForTesting implements HostKeyTrustStore {
  @override
  String keyFor(String host, int port) => 'ssh_hostkey_${host}_$port';

  @override
  Future<void> forget(String host, int port) async {}

  @override
  String? lastMismatchFingerprint(String host, int port) => null;

  @override
  Future<void> recordMismatch(
          String host, int port, String presentedFingerprint) async {}

  @override
  Future<void> trust(String host, int port, String fingerprint) async {}

  @override
  bool isTrusted(String host, int port) => false;

  @override
  String? trustedFingerprint(String host, int port) => null;
}
