import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/stream_models.dart';

/// Deterministic identifiers for streaming items.
///
/// The same URL always maps to the same media_items row, so watch progress,
/// favorites and history survive app restarts and playlist re-imports.
class StreamIds {
  StreamIds._();

  static String _hash(String input) =>
      sha256.convert(utf8.encode(input)).toString().substring(0, 16);

  /// Direct link / IPTV channel row id: `net:<hash(url)>`.
  static String forUrl(String url) => 'net:${_hash(url)}';

  /// NAS file row id: `nas:<hash(serverId NUL path)>`.
  static String forNas(String serverId, String path) =>
      'nas:${_hash('$serverId\x00$path')}';

  /// Playlist id derived from its source URL (or name for manual imports).
  static String playlistId(String sourceOrName) =>
      'iptvpl:${_hash(sourceOrName)}';

  /// Stable logical uri for a NAS file (no credentials, globally unique).
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

/// source_id tags for media_items rows created from streaming platforms.
class StreamSourceTags {
  StreamSourceTags._();

  static String iptvOf(String playlistId) =>
      '${AppConstants.streamSourceIptv}$playlistId';

  static String nasOf(String serverId) =>
      '${AppConstants.streamSourceNas}$serverId';
}

/// One parsed M3U entry.
class M3uEntry {
  const M3uEntry({
    required this.name,
    required this.url,
    this.logoUrl,
    this.groupName,
    this.tvgId,
    this.kind = 'live',
  });

  final String name;
  final String url;
  final String? logoUrl;
  final String? groupName;
  final String? tvgId;

  /// 'live' for TV channels; 'vod' when the URL points at a video file.
  final String kind;
}

/// Parser for M3U / M3U8 playlists (IPTV format).
///
/// Handles BOM, CRLF, EXTINF attributes (`tvg-id` / `tvg-name` / `tvg-logo`
/// / `group-title`), `EXTGRP` group fallback and plain URL lists. Garbage
/// lines (broken EXTINF remnants, comments, HTML error pages) are skipped.
class M3uParser {
  M3uParser._();

  static final RegExp _attrRegex = RegExp('([\\w-]+)="([^"]*)"');
  static final RegExp _videoExtRegex = RegExp(
      r'\.(mp4|mkv|avi|mov|m4v|flv|wmv|ts|webm|mpg|mpeg|3gp)(\?|$)',
      caseSensitive: false);

  static List<M3uEntry> parse(String raw) {
    final text = _stripBom(raw).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final entries = <M3uEntry>[];

    String? pendingName;
    String? pendingLogo;
    String? pendingGroup;
    String? pendingTvgId;
    bool extended = false;

    for (var line in text.split('\n')) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF')) {
        // Only a well-formed directive (with the colon) opens a new entry;
        // broken remnants like "#EXTINFbroken" must not swallow the next
        // line as a URL.
        extended = line.contains(':');
        final body = line.replaceFirst(':', '');
        final comma = body.indexOf(',');
        final attrPart = comma >= 0 ? body.substring(0, comma) : body;
        pendingName = comma >= 0 ? body.substring(comma + 1).trim() : null;
        if (pendingName != null && pendingName.isEmpty) pendingName = null;
        pendingLogo = null;
        pendingGroup = null;
        pendingTvgId = null;
        for (final m in _attrRegex.allMatches(attrPart)) {
          final key = m.group(1)!.toLowerCase();
          final value = m.group(2)!;
          switch (key) {
            case 'tvg-logo':
              pendingLogo = value;
            case 'group-title':
              pendingGroup = value;
            case 'tvg-id':
              pendingTvgId = value;
            case 'tvg-name':
              pendingName ??= value;
          }
        }
        continue;
      }

      if (line.startsWith('#EXTGRP:')) {
        pendingGroup ??= line.replaceFirst('#EXTGRP:', '').trim();
        continue;
      }

      if (line.startsWith('#')) continue; // other directives/comments

      // A URL line: accept when an EXTINF preceded it, or the line itself
      // looks like a URL/path. Broken remnants like "#EXTINFbroken" are
      // caught by the '#' branch above and never parsed as URLs.
      if (!_looksLikeUrl(line, extended)) {
        extended = false;
        pendingName = null;
        continue;
      }

      final kind = _isVod(line) ? 'vod' : 'live';
      entries.add(M3uEntry(
        name: pendingName ?? _nameFromUrl(line),
        url: line,
        logoUrl: pendingLogo,
        groupName: pendingGroup,
        tvgId: pendingTvgId,
        kind: kind,
      ));
      extended = false;
      pendingName = null;
      pendingLogo = null;
      pendingGroup = null;
      pendingTvgId = null;
    }
    return entries;
  }

  static bool _looksLikeUrl(String line, bool extended) =>
      extended || line.contains('://') || line.startsWith('/');

  static bool _isVod(String url) =>
      _videoExtRegex.hasMatch(url) ||
      url.toLowerCase().contains('/movie/') ||
      url.toLowerCase().contains('/movies/');

  static String _nameFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final segments =
        path.split('/').where((s) => s.trim().isNotEmpty).toList();
    if (segments.isEmpty) return url;
    return Uri.decodeComponent(segments.last);
  }

  static String _stripBom(String s) =>
      s.startsWith('\uFEFF') ? s.substring(1) : s;
}
