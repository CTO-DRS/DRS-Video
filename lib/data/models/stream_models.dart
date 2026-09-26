import '../../core/constants/app_constants.dart';

/// An imported M3U/M3U8 playlist (IPTV).
class IptvPlaylist {
  IptvPlaylist({
    required this.id,
    required this.name,
    this.sourceUrl,
    this.channelCount = 0,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  String name;

  /// Where the playlist was imported from (URL) — null for manual files.
  String? sourceUrl;
  int channelCount;
  final DateTime createdAt;
  DateTime? updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'source_url': sourceUrl,
        'channel_count': channelCount,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt?.millisecondsSinceEpoch,
      };

  static IptvPlaylist fromMap(Map<String, Object?> m) => IptvPlaylist(
        id: m['id'] as String,
        name: m['name'] as String,
        sourceUrl: m['source_url'] as String?,
        channelCount: (m['channel_count'] as int?) ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: m['updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}

/// A channel/entry inside an IPTV playlist.
class IptvChannel {
  IptvChannel({
    required this.id,
    required this.playlistId,
    required this.name,
    required this.url,
    this.logoUrl,
    this.groupName,
    this.kind = 'live',
    this.tvgId,
  });

  /// Same deterministic id used for the matching media_items row, so watch
  /// progress/history survive re-imports.
  final String id;
  final String playlistId;
  String name;
  final String url;
  String? logoUrl;
  String? groupName;

  /// 'live' for TV channels, 'vod' for on-demand entries.
  final String kind;
  String? tvgId;

  bool get isLive => kind == 'live';

  Map<String, Object?> toMap() => {
        'id': id,
        'playlist_id': playlistId,
        'name': name,
        'url': url,
        'logo_url': logoUrl,
        'group_name': groupName,
        'kind': kind,
        'tvg_id': tvgId,
      };

  static IptvChannel fromMap(Map<String, Object?> m) => IptvChannel(
        id: m['id'] as String,
        playlistId: m['playlist_id'] as String,
        name: m['name'] as String,
        url: m['url'] as String,
        logoUrl: m['logo_url'] as String?,
        groupName: m['group_name'] as String?,
        kind: (m['kind'] as String?) ?? 'live',
        tvgId: m['tvg_id'] as String?,
      );
}

/// A NAS server connection. Credentials are stored locally on the device
/// only — they are never included in exports or backups.
class NasServer {
  NasServer({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.basePath = '/',
    this.useTls = false,
    required this.createdAt,
    this.lastSeenAt,
  });

  final String id;
  String name;
  final NasProtocol protocol;
  final String host;
  final int port;

  /// Null for anonymous access.
  String? username;
  String? password;

  /// Root path browsed on connect.
  String? basePath;
  bool useTls;
  final DateTime createdAt;
  DateTime? lastSeenAt;

  /// Base URL without credentials (stable, used for WebDAV client + logs).
  String get scheme {
    switch (protocol) {
      case NasProtocol.webdav:
        return useTls ? 'https' : 'http';
      case NasProtocol.ftp:
        return useTls ? 'ftps' : 'ftp';
      case NasProtocol.sftp:
        return 'sftp';
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'base_path': basePath,
        'use_tls': useTls ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'last_seen_at': lastSeenAt?.millisecondsSinceEpoch,
      };

  static NasServer fromMap(Map<String, Object?> m) => NasServer(
        id: m['id'] as String,
        name: m['name'] as String,
        protocol: NasProtocol.values.byName(m['protocol'] as String),
        host: m['host'] as String,
        port: (m['port'] as int?) ?? 0,
        username: m['username'] as String?,
        password: m['password'] as String?,
        basePath: (m['base_path'] as String?) ?? '/',
        useTls: ((m['use_tls'] as int?) ?? 0) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        lastSeenAt: m['last_seen_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['last_seen_at'] as int),
      );
}

/// One entry in a NAS directory listing.
class NasEntry {
  const NasEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.sizeBytes,
    this.modifiedAt,
  });

  final String name;

  /// Absolute logical path on the server (slash separated, starts with /).
  final String path;
  final bool isDir;
  final int? sizeBytes;
  final DateTime? modifiedAt;

  bool get isVideo {
    if (isDir) return false;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return false;
    return AppConstants.videoExtensions
        .contains(name.substring(dot + 1).toLowerCase());
  }
}
