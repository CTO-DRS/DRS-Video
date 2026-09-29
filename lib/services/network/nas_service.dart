import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
import '../../data/models/stream_models.dart';
import '../security/host_key_trust_store.dart';
import 'ftp_client.dart';
import 'sftp_proxy.dart';

/// Everything the player needs to open a NAS file in this session.
class NasPlayback {
  const NasPlayback({
    required this.playUrl,
    required this.logicalUri,
    this.headers,
  });

  /// Per-session URL handed to mpv (SFTP proxy URL / ftp:// with
  /// credentials / direct WebDAV URL).
  final String playUrl;

  /// Stable credential-free logical identity stored in media_items.
  final String logicalUri;

  /// Extra HTTP headers (WebDAV Basic auth).
  final Map<String, String>? headers;
}

/// Browse + playback resolution for NAS servers over WebDAV, FTP and SFTP.
///
/// All failures are mapped to typed [AppException]s; nothing here throws raw
/// socket errors into the UI layer.
class NasService {
  /// [trustStore] pins SSH host keys (TOFU). P2 security fix (C3): this
  /// replaces the old `disableHostkeyVerification: true`, which accepted
  /// any server key and exposed SFTP credentials to MITM.
  NasService({required HostKeyTrustStore trustStore})
      : _trustStore = trustStore;

  final HostKeyTrustStore _trustStore;

  final Map<String, webdav.Client> _webdavClients = {};
  final Map<String, SSHClient> _sshClients = {};
  final Map<String, SftpClient> _sftpClients = {};
  final Map<String, MinimalFtpClient> _ftpClients = {};
  SftpStreamProxy? _proxy;

  // ---- browse ----

  Future<List<NasEntry>> browse(NasServer server, String path) async {
    final normalized = _normalizeDir(server, path);
    switch (server.protocol) {
      case NasProtocol.webdav:
        return _browseWebdav(server, normalized);
      case NasProtocol.ftp:
        return _browseFtp(server, normalized);
      case NasProtocol.sftp:
        return _browseSftp(server, normalized);
    }
  }

  /// Same as [browse] but maps every failure to a typed [AppException].
  Future<List<NasEntry>> browseGuarded(NasServer server, String path) async {
    try {
      final entries = await browse(server, path).timeout(
        AppConstants.nasConnectTimeout * 2,
      );
      unawaited(_touch(server.id));
      return entries;
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw AppException(AppErrorType.timeout,
          detail: 'NAS listing timed out (${server.host})');
    } on FtpAuthException {
      throw AppException(AppErrorType.forbidden,
          detail: 'FTP authentication failed');
    } on FtpException catch (e) {
      throw AppException(AppErrorType.network, detail: e.message);
    } on SSHAuthFailError {
      throw AppException(AppErrorType.forbidden,
          detail: 'SSH authentication failed');
    } on SSHHostkeyError {
      // P2 (C3): the pinned host key no longer matches — the connection
      // was rejected before any credential left the device.
      throw AppException(AppErrorType.forbidden,
          detail: 'SSH host key verification failed for ${server.host}:'
              '${server.port}. If the server key legitimately changed '
              '(reinstall/new hardware), remove and re-add the server to '
              're-trust it.');
    } on SSHError catch (e) {
      throw AppException(AppErrorType.network, detail: e.toString());
    } on DioException catch (e) {
      throw AppException(_dioErrorType(e), detail: e.message ?? 'WebDAV error');
    } on SocketException catch (e) {
      throw AppException(AppErrorType.network, detail: e.message);
    } on HandshakeException catch (e) {
      throw AppException(AppErrorType.network, detail: e.toString());
    } catch (e) {
      throw AppException(AppErrorType.network, detail: e.toString());
    }
  }

  AppErrorType _dioErrorType(DioException e) {
    final code = e.response?.statusCode ?? 0;
    if (code == 401 || code == 403) return AppErrorType.forbidden;
    if (code == 404) return AppErrorType.notFound;
    return AppErrorType.network;
  }

  String _normalizeDir(NasServer server, String path) {
    final base = server.basePath == null || server.basePath!.isEmpty
        ? '/'
        : (server.basePath!.startsWith('/')
            ? server.basePath!
            : '/${server.basePath}');
    var p = path.isEmpty ? base : (path.startsWith('/') ? path : '/$path');
    if (!p.startsWith(base) || p.length < base.length) p = base;
    if (p.length > 1 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  Future<List<NasEntry>> _browseWebdav(
      NasServer server, String path) async {
    final client = await _webdavFor(server);
    final files = await client.readDir(path == '/' ? '/' : path);
    final out = <NasEntry>[];
    for (final f in files) {
      final name = f.name ?? _lastSegment(f.path ?? '');
      if (name.isEmpty || name == '.' || name == '..') continue;
      final isDir = f.isDir ?? (f.path?.endsWith('/') ?? false);
      final fullPath = path == '/' ? '/$name' : '$path/$name';
      out.add(NasEntry(
        name: name,
        path: fullPath,
        isDir: isDir,
        sizeBytes: isDir ? null : f.size,
        modifiedAt: f.mTime,
      ));
    }
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  Future<List<NasEntry>> _browseFtp(NasServer server, String path) async {
    final client = MinimalFtpClient();
    try {
      await client.connect(
        host: server.host,
        port: server.port,
        username: server.username,
        password: server.password,
      );
      final entries = await client.list(path);
      final base = _normalizeDir(server, path);
      final out = <NasEntry>[];
      for (final e in entries) {
        final isParent = e.name == '..';
        if (isParent) continue;
        out.add(NasEntry(
          name: e.name,
          path: base == '/' ? '/${e.name}' : '$base/${e.name}',
          isDir: e.isDir,
          sizeBytes: e.sizeBytes,
          modifiedAt: e.modifiedAt,
        ));
      }
      out.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return out;
    } finally {
      await client.quit();
    }
  }

  Future<List<NasEntry>> _browseSftp(NasServer server, String path) async {
    final sftp = await _sftpFor(server);
    final names = await sftp.listdir(path);
    final out = <NasEntry>[];
    for (final n in names) {
      final name = n.filename;
      if (name.isEmpty || name == '.' || name == '..') continue;
      out.add(NasEntry(
        name: name,
        path: path == '/' ? '/$name' : '$path/$name',
        isDir: n.attr.isDirectory,
        sizeBytes: n.attr.isDirectory ? null : n.attr.size,
      ));
    }
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  // ---- playback resolution ----

  /// Resolves the per-session playback parameters for a NAS file.
  Future<NasPlayback> playbackFor(NasServer server, NasEntry entry) async {
    final logicalUri = StreamIdsNas.nasLogicalUri(server, entry.path);
    switch (server.protocol) {
      case NasProtocol.webdav:
        final scheme = server.useTls ? 'https' : 'http';
        final portPart = (server.useTls
                    ? AppConstants.webdavTlsDefaultPort
                    : AppConstants.webdavDefaultPort) ==
                server.port
            ? ''
            : ':${server.port}';
        final url = '$scheme://${server.host}$portPart'
            '${Uri.encodeFull(entry.path)}';
        final headers = <String, String>{
          if (server.username != null && server.username!.isNotEmpty)
            'Authorization':
                'Basic ${base64Encode(utf8.encode('${server.username}:${server.password ?? ''}'))}',
        };
        return NasPlayback(
          playUrl: url,
          logicalUri: logicalUri,
          headers: headers.isEmpty ? null : headers,
        );

      case NasProtocol.ftp:
        return NasPlayback(
          playUrl: buildFtpUrl(
            host: server.host,
            port: server.port,
            path: entry.path,
            username: server.username,
            password: server.password,
          ),
          logicalUri: logicalUri,
        );

      case NasProtocol.sftp:
        final sftp = await _sftpFor(server);
        int size = entry.sizeBytes ?? 0;
        if (size <= 0) {
          try {
            final f = await sftp.open(entry.path);
            try {
              size = (await f.stat()).size ?? 0;
            } finally {
              await f.close();
            }
          } catch (e) {
            AppLogger.instance.warning('nas', 'stat failed: $e');
          }
        }
        final proxy = _proxy ??= SftpStreamProxy();
        final url = await proxy.serveFile(
          sftp: sftp,
          remotePath: entry.path,
          fileSize: size,
        );
        return NasPlayback(playUrl: url, logicalUri: logicalUri);
    }
  }

  // ---- connection management ----

  Future<webdav.Client> _webdavFor(NasServer server) async {
    final existing = _webdavClients[server.id];
    if (existing != null) return existing;
    final scheme = server.useTls ? 'https' : 'http';
    final portPart = (server.useTls
                ? AppConstants.webdavTlsDefaultPort
                : AppConstants.webdavDefaultPort) ==
            server.port
        ? ''
        : ':${server.port}';
    final base = server.basePath == null || server.basePath!.isEmpty
        ? '/'
        : server.basePath!;
    final client = webdav.newClient(
      '$scheme://${server.host}$portPart$base',
      user: server.username ?? '',
      password: server.password ?? '',
    );
    client.setConnectTimeout(
        AppConstants.nasConnectTimeout.inMilliseconds);
    await client.ping();
    _webdavClients[server.id] = client;
    return client;
  }

  Future<SftpClient> _sftpFor(NasServer server) async {
    final existing = _sftpClients[server.id];
    if (existing != null) return existing;
    final ssh = _sshClients[server.id];
    if (ssh != null && !ssh.isClosed) return ssh.sftp();

    final socket = await SSHSocket.connect(
      server.host,
      server.port,
      timeout: AppConstants.nasConnectTimeout,
    );
    final client = SSHClient(
      socket,
      username: server.username ?? 'root',
      onPasswordRequest: () => server.password ?? '',
      // P2 security fix (C3): TOFU host-key pinning. First connect trusts
      // and remembers the server fingerprint; any later key change fails
      // the handshake BEFORE credentials are sent (see [browseGuarded]).
      onVerifyHostKey: SshTofuVerifier(
        _trustStore,
        server.host,
        server.port,
        label: 'nas',
      ).call,
      keepAliveInterval: const Duration(seconds: 15),
    );
    _sshClients[server.id] = client;
    unawaited(client.done.whenComplete(() {
      _sshClients.remove(server.id);
      _sftpClients.remove(server.id);
    }));
    final sftp = await client.sftp();
    _sftpClients[server.id] = sftp;
    return sftp;
  }

  /// Drops the pinned host key for [server] (explicit re-trust path:
  /// remove + re-add the server after a verified key change).
  Future<void> forgetHostKey(NasServer server) =>
      _trustStore.forget(server.host, server.port);

  /// Drops all cached connections for one server.
  Future<void> releaseServer(String serverId) async {
    _webdavClients.remove(serverId);
    _ftpClients.remove(serverId)?.quit();
    final sftp = _sftpClients.remove(serverId);
    final ssh = _sshClients.remove(serverId);
    try {
      await sftp?.close();
    } catch (_) {}
    try {
      ssh?.close();
    } catch (_) {}
    _proxy?.clearTargets();
  }

  Future<void> disposeAll() async {
    _webdavClients.clear();
    for (final f in _ftpClients.values) {
      await f.quit();
    }
    _ftpClients.clear();
    for (final s in _sftpClients.values) {
      try {
        await s.close();
      } catch (_) {}
    }
    _sftpClients.clear();
    for (final c in _sshClients.values) {
      try {
        c.close();
      } catch (_) {}
    }
    _sshClients.clear();
    await _proxy?.stop();
    _proxy = null;
  }

  Future<void> _touch(String serverId) async {
    // Marked by the repository layer; kept here to avoid a circular dep.
    onTouch?.call(serverId);
  }

  /// Hook wired by PlatformsController so successful browses update
  /// last_seen_at without NasService knowing about the database.
  void Function(String serverId)? onTouch;

  static String _lastSegment(String path) {
    final p = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final i = p.lastIndexOf('/');
    return i >= 0 ? p.substring(i + 1) : p;
  }
}

/// Indirection so NasService can build logical URIs without importing the
/// factory (and the factory importing this service).
class StreamIdsNas {
  StreamIdsNas._();

  static String nasLogicalUri(NasServer server, String path) {
    final defaultPort = switch (server.protocol) {
      NasProtocol.webdav => server.useTls
          ? AppConstants.webdavTlsDefaultPort
          : AppConstants.webdavDefaultPort,
      NasProtocol.ftp => AppConstants.ftpDefaultPort,
      NasProtocol.sftp => AppConstants.sftpDefaultPort,
    };
    final portPart = server.port == defaultPort ? '' : ':${server.port}';
    final p = path.startsWith('/') ? path : '/$path';
    return '${server.scheme}://${server.host}$portPart$p';
  }
}
