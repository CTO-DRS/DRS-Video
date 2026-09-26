import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../core/utils/logger.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../data/models/media_item.dart';
import '../data/models/stream_models.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/stream_repositories.dart';
import '../services/network/nas_service.dart';
import '../services/network/smart_url.dart';
import '../services/network/social_resolver.dart';
import '../services/network/stream_source_factory.dart';
import '../services/network/tiktok_resolver.dart';
import '../services/network/youtube_resolver.dart';

/// Drives the المنصات (Platforms) tab: direct stream links, IPTV playlists
/// and NAS servers.
///
/// Every failure is captured into [error]/[lastErrorText] — the controller
/// never lets a stream/network problem take the rest of the app down.
class PlatformsController extends ChangeNotifier {
  PlatformsController({
    required StreamSourceFactory factory,
    required IptvRepository iptv,
    required NasRepository nasRepo,
    required NasService nas,
    required IptvImportService iptvImport,
    required HistoryRepository history,
    required LibraryRepository library,
  })  : _factory = factory,
        _iptv = iptv,
        _nasRepo = nasRepo,
        _nas = nas,
        _iptvImport = iptvImport,
        _history = history,
        _library = library {
    // Successful NAS browses mark the server as seen.
    _nas.onTouch = (serverId) => unawaitedNasTouch(serverId);
  }

  final StreamSourceFactory _factory;
  final IptvRepository _iptv;
  final NasRepository _nasRepo;
  final NasService _nas;
  final IptvImportService _iptvImport;
  final HistoryRepository _history;
  final LibraryRepository _library;

  // ---- direct links ----
  List<MediaItem> links = [];
  Map<String, WatchProgress> linkProgress = {};

  // ---- IPTV ----
  List<IptvPlaylist> playlists = [];
  bool importing = false;

  // ---- NAS ----
  List<NasServer> servers = [];

  AppException? error;
  bool loading = false;

  String? get lastErrorText =>
      error == null ? null : describeError(error!);

  // ---- loading ----

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      links = await _factory.savedLinks();
      playlists = await _iptv.playlists();
      servers = await _nasRepo.servers();
      linkProgress = await _history.progressMap();
    } catch (e, s) {
      AppLogger.instance.error('platforms', 'load failed', e, s);
      error = mapException(e, stack: s);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ---- direct links ----

  /// Adds (or updates) a link. Returns the row so callers can play it.
  Future<MediaItem> addLink(String url, {String? title}) async {
    if (!StreamSourceFactory.isSupportedUrl(url)) {
      throw AppException(AppErrorType.invalidInput,
          detail: 'unsupported or malformed stream URL');
    }
    final item = await _factory.saveLink(url, title: title);
    await load();
    return item;
  }

  /// Smart open for URLs arriving from share intents, the clipboard or
  /// the add-link dialog (v1.3.0).
  ///
  /// Extracts the URL from arbitrary text, accepts YouTube and TikTok
  /// links in addition to every supported protocol, and fetches the real
  /// video title for YouTube/TikTok when the network allows (short
  /// timeout, best effort — a failed lookup never blocks saving/playing).
  Future<MediaItem> smartOpenUrl(String raw, {String? title}) async {
    final url = SmartUrl.extractUrlFromText(raw) ?? raw.trim();
    final isYouTube = YouTubeResolver.isYouTubeUrl(url);
    final isTikTok = TikTokResolver.isTikTokUrl(url);
    final isSocial = SocialResolver.isSocialUrl(url);
    if (!StreamSourceFactory.isSupportedUrl(url) && !isYouTube) {
      throw AppException(AppErrorType.invalidInput,
          detail: 'unsupported or malformed stream URL');
    }
    var resolvedTitle = title;
    if (resolvedTitle == null && isYouTube) {
      resolvedTitle = await YouTubeResolver.instance.fetchTitle(url);
    } else if (resolvedTitle == null && isTikTok) {
      resolvedTitle = await TikTokResolver.instance.fetchTitle(url);
    } else if (resolvedTitle == null && isSocial) {
      resolvedTitle = await SocialResolver.instance.fetchTitle(url) ??
          SocialResolver.fallbackTitle(url);
    }
    final item = await _factory.saveLink(url, title: resolvedTitle);
    await load();
    return item;
  }

  Future<void> deleteLink(String id) async {
    await _factory.deleteLink(id);
    await load();
  }

  Future<void> toggleFavorite(String id) async {
    final item = links.firstWhere((m) => m.id == id);
    await _library.setFavorite(item.id, !item.isFavorite);
    await load();
  }

  // ---- IPTV ----

  Future<IptvPlaylist> importFromUrl(String url, {String? name}) async {
    importing = true;
    notifyListeners();
    try {
      final pl = await _iptvImport.importFromUrl(url, name: name);
      await load();
      return pl;
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  Future<IptvPlaylist> importFromFile(String path, {String? name}) async {
    importing = true;
    notifyListeners();
    try {
      final pl = await _iptvImport.importFromFile(path, name: name);
      await load();
      return pl;
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  /// File-picker import flow; returns null when the user cancels.
  Future<IptvPlaylist?> pickAndImportPlaylist() async {
    importing = true;
    notifyListeners();
    try {
      final pl = await _iptvImport.pickAndImport();
      if (pl != null) await load();
      return pl;
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  Future<void> deletePlaylist(String id) async {
    await _iptv.delete(id);
    await load();
  }

  Future<List<IptvChannel>> channelsOf(String playlistId,
      {String? group, String? search}) {
    return _iptv.channelsOf(playlistId, group: group, search: search);
  }

  Future<List<String>> groupsOf(String playlistId) =>
      _iptv.groupsOf(playlistId);

  /// Playback item for a channel; live channels skip resume/progress.
  Future<MediaItem> playItemForChannel(IptvChannel channel) =>
      _factory.itemForChannel(channel);

  // ---- NAS ----

  Future<void> addServer({
    required String name,
    required NasProtocol protocol,
    required String host,
    required int port,
    String? username,
    String? password,
    bool useTls = false,
  }) async {
    final id = StreamIdsForServer.of(protocol, host, port, username);
    final server = NasServer(
      id: id,
      name: name.trim().isEmpty ? host : name.trim(),
      protocol: protocol,
      host: host.trim(),
      port: port,
      username: (username?.trim().isEmpty ?? true) ? null : username!.trim(),
      password: password,
      basePath: '/',
      useTls: useTls,
      createdAt: DateTime.now(),
    );
    // Verify before saving: browse the root (throws typed on failure).
    await _nas.browseGuarded(server, '/');
    await _nasRepo.save(server);
    await load();
  }

  Future<void> deleteServer(String id) async {
    await _nas.releaseServer(id);
    await _nasRepo.delete(id);
    await load();
  }

  Future<List<NasEntry>> browse(NasServer server, String path) =>
      _nas.browseGuarded(server, path);

  /// Playback item for a NAS video file (resolves per-session play URL).
  Future<MediaItem> playItemForNasFile(
      NasServer server, NasEntry entry) async {
    final playback = await _nas.playbackFor(server, entry);
    return _factory.itemForNasFile(
      server: server,
      entry: entry,
      playUrl: playback.playUrl,
      logicalUri: playback.logicalUri,
      headers: playback.headers,
    );
  }

  void releaseServerConnections(String serverId) =>
      _nas.releaseServer(serverId);

  @override
  void dispose() {
    _nas.disposeAll();
    super.dispose();
  }

  // plumbing

  Future<void> unawaitedNasTouch(String serverId) async {
    try {
      await _nasRepo.touch(serverId);
    } catch (_) {
      // last_seen_at is cosmetic — never surface this.
    }
  }

  static String describeError(AppException e) {
    switch (e.type) {
      case AppErrorType.timeout:
        return 'timeout: ${e.detail ?? ''}';
      case AppErrorType.forbidden:
        return 'auth failed: ${e.detail ?? ''}';
      case AppErrorType.network:
        return 'network: ${e.detail ?? ''}';
      case AppErrorType.notFound:
        return 'not found: ${e.detail ?? ''}';
      case AppErrorType.invalidInput:
        return e.detail ?? 'invalid input';
      default:
        return e.detail ?? e.type.name;
    }
  }
}

/// Stable server ids derived from identity fields, so re-adding the same
/// server updates it instead of duplicating.
class StreamIdsForServer {
  StreamIdsForServer._();

  static String of(
      NasProtocol protocol, String host, int port, String? username) {
    final raw =
        '${protocol.name}\x00$host\x00$port\x00${username ?? ''}';
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return 'nassrv:${digest.substring(0, 16)}';
  }
}
