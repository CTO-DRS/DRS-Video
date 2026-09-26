import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/dio_client.dart';
import '../../data/models/media_item.dart';
import '../../data/models/stream_models.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/stream_repositories.dart';
import '../../services/network/m3u_parser.dart';

/// Creates/loads/deletes the media_items rows behind every streaming
/// platform (direct links, IPTV channels, NAS files).
///
/// All rows are deterministic (see [StreamIds]) and idempotent: saving the
/// same URL twice updates in place, so progress/favorites are never lost.
class StreamSourceFactory {
  StreamSourceFactory(this._library);

  final LibraryRepository _library;

  /// True when [url] parses and its scheme is supported by the player.
  static bool isSupportedUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return false;
    return AppConstants.streamUrlSchemes.contains(uri.scheme.toLowerCase());
  }

  /// Saves a direct stream link. Returns the existing row when the URL was
  /// already saved (idempotent upsert).
  Future<MediaItem> saveLink(String url, {String? title}) async {
    final clean = url.trim();
    if (!isSupportedUrl(clean)) {
      throw ArgumentError.value(url, 'url', 'unsupported stream URL');
    }
    final id = StreamIds.forUrl(clean);
    final existing = await _library.byId(id);
    if (existing != null) {
      if (title != null && title.trim().isNotEmpty && title != existing.title) {
        await _library.rename(id, title.trim());
        existing.title = title.trim();
      }
      return existing;
    }
    final item = MediaItem(
      id: id,
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : _titleFromUrl(clean),
      uri: clean,
      type: MediaItemType.network,
      sourceId: AppConstants.streamSourceLink,
      addedAt: DateTime.now(),
    );
    await _library.upsert(item);
    return item;
  }

  /// All saved direct links, newest first.
  Future<List<MediaItem>> savedLinks() async {
    final all = await _library.query(const LibraryQuery(
      type: MediaItemType.network,
      sourceId: AppConstants.streamSourceLink,
      sort: SortBy.dateAdded,
    ));
    return all;
  }

  Future<void> deleteLink(String id) => _library.delete(id);

  /// media_items row for an IPTV channel (live channels get [liveHint]).
  Future<MediaItem> itemForChannel(IptvChannel channel) async {
    final item = MediaItem(
      id: channel.id,
      title: channel.name,
      uri: channel.url,
      type: MediaItemType.network,
      sourceId: StreamSourceTags.iptvOf(channel.playlistId),
      addedAt: DateTime.now(),
    )..liveHint = channel.isLive;
    return item;
  }

  /// media_items row for a NAS file. [playUrl]/[headers] are per-session
  /// values resolved by NasService; the row keeps the stable logical uri.
  Future<MediaItem> itemForNasFile({
    required NasServer server,
    required NasEntry entry,
    required String playUrl,
    required String logicalUri,
    Map<String, String>? headers,
  }) async {
    final id = StreamIds.forNas(server.id, entry.path);
    final name = entry.name;
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : null;
    return MediaItem(
      id: id,
      title: name,
      uri: logicalUri,
      type: MediaItemType.network,
      sourceId: StreamSourceTags.nasOf(server.id),
      extension: ext,
      sizeBytes: entry.sizeBytes,
      headers: headers,
      addedAt: DateTime.now(),
    )..playUri = playUrl;
  }

  static String _titleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url;
    final segments =
        path.split('/').where((s) => s.trim().isNotEmpty).toList();
    if (segments.isEmpty) return uri?.host ?? url;
    var decoded = segments.last;
    try {
      decoded = Uri.decodeComponent(segments.last);
    } catch (_) {
      // Malformed percent-encoding — keep the raw segment.
    }
    return decoded.isEmpty ? (uri?.host ?? url) : decoded;
  }
}

/// Imports M3U/M3U8 playlists from a URL or a local file.
///
/// Re-importing the same source URL (or importing a file under the same
/// name) replaces that playlist's channels in place; channel ids hash the
/// URL so progress/history survive re-imports.
class IptvImportService {
  IptvImportService(this._iptv);

  final IptvRepository _iptv;

  Future<IptvPlaylist> importFromUrl(String url, {String? name}) async {
    final clean = url.trim();
    final response = await DioClient.instance.dio.get<String>(
      clean,
      options: Options(responseType: ResponseType.plain),
    );
    final body = response.data ?? '';
    if (!body.contains('#EXTM3U') && !body.contains('#EXTINF')) {
      throw const IptvImportException(
          'the response is not an M3U playlist');
    }
    return _import(
      key: clean,
      name: name,
      sourceUrl: clean,
      raw: body,
    );
  }

  Future<IptvPlaylist> importFromFile(String path, {String? name}) async {
    final raw = await File(path).readAsString();
    final fileName = path.split('/').last.split('\\').last;
    final baseName =
        fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
    return _import(
      key: 'file:$baseName',
      name: name ?? baseName,
      sourceUrl: null,
      raw: raw,
    );
  }

  /// Opens the system file picker and imports the chosen M3U/M3U8.
  Future<IptvPlaylist?> pickAndImport() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
    );
    final path = res?.files.single.path;
    if (path == null) return null;
    return importFromFile(path);
  }

  Future<IptvPlaylist> _import({
    required String key,
    required String? name,
    required String? sourceUrl,
    required String raw,
  }) async {
    final entries = M3uParser.parse(raw);
    if (entries.isEmpty) {
      throw const IptvImportException('no channels found in the playlist');
    }
    final id = StreamIds.playlistId(key);
    final existing = await _iptv.playlistById(id);
    final playlist = IptvPlaylist(
      id: id,
      name: (name != null && name.trim().isNotEmpty)
          ? name.trim()
          : (existing?.name ?? key),
      sourceUrl: sourceUrl ?? existing?.sourceUrl,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final channels = <IptvChannel>[];
    final seen = <String>{};
    for (final e in entries) {
      final channelId = StreamIds.forUrl(e.url);
      if (!seen.add(channelId)) continue; // dedupe identical URLs
      channels.add(IptvChannel(
        id: channelId,
        playlistId: id,
        name: e.name,
        url: e.url,
        logoUrl: e.logoUrl,
        groupName: e.groupName,
        kind: e.kind,
        tvgId: e.tvgId,
      ));
    }
    final unique = IptvPlaylist(
      id: playlist.id,
      name: playlist.name,
      sourceUrl: playlist.sourceUrl,
      channelCount: channels.length,
      createdAt: playlist.createdAt,
      updatedAt: playlist.updatedAt,
    );
    await _iptv.replacePlaylist(playlist: unique, channels: channels);
    return unique;
  }
}

class IptvImportException implements Exception {
  const IptvImportException(this.message);
  final String message;
  @override
  String toString() => message;
}
