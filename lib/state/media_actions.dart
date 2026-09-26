import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/logger.dart';
import '../core/utils/validators.dart';
import '../data/models/media_item.dart';
import '../data/repositories/library_repository.dart';
import '../data/sources/source_adapter.dart';
import '../services/network/social_resolver.dart';
import '../services/network/stream_detector.dart';
import '../services/network/tiktok_resolver.dart';
import '../services/network/youtube_resolver.dart';
import '../services/player/player_service.dart';

/// Bridges user intents (open URL, open file, play item) to the player,
/// creating library entries on first play.
class MediaActions extends ChangeNotifier {
  MediaActions({
    required LibraryRepository library,
    required PlayerService player,
    required SourceRegistry registry,
  })  : _library = library,
        _player = player,
        _registry = registry;

  final LibraryRepository _library;
  final PlayerService _player;
  final SourceRegistry _registry;

  bool _resolving = false;
  AppException? _lastError;
  bool get resolving => _resolving;
  AppException? get lastError => _lastError;

  /// Resolves a URL through the matching adapter, stores it, plays it.
  Future<MediaItem?> openUrl(String rawUrl, {String? sourceId, Map<String, String>? headers}) async {
    _lastError = null;
    _resolving = true;
    notifyListeners();
    try {
      final adapter = _registry.adapterFor(rawUrl);
      if (adapter == null) {
        throw const AppException(AppErrorType.invalidInput);
      }
      final resolved = await adapter.resolve(rawUrl, extraHeaders: headers);
      final existing = await _library.byUri(resolved.streamUrl);
      final item = existing ??
          MediaItem(
            id: 'mn_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
            title: resolved.title,
            uri: resolved.streamUrl,
            type: MediaItemType.network,
            sourceId: sourceId ?? adapter.id,
            sizeBytes: resolved.sizeBytes,
            introEndMs: resolved.introEndMs,
            outroStartMs: resolved.outroStartMs,
            headers: resolved.headers,
          );
      // Live-stream detection (v1.7.0): HLS/DASH URLs that look live get
      // liveHint so the player skips resume + progress persistence and
      // shows the LIVE badge. Pure classification — no extra network I/O:
      // it reuses the probe results the adapter already gathered.
      item.liveHint = StreamDetector.isLiveLike(
        url: item.uri,
        contentType: resolved.contentType,
        sizeBytes: resolved.sizeBytes,
        resumable: resolved.resumable,
      );
      if (existing == null) {
        await _library.upsert(item);
      }
      final audioUrl = await _resolveSessionStream(item);
      await _player.open(item, audioFileUrl: audioUrl);
      return item;
    } catch (e, s) {
      _lastError = mapException(e, stack: s);
      AppLogger.instance.error('actions', 'openUrl failed', e, s);
      return null;
    } finally {
      _resolving = false;
      notifyListeners();
    }
  }

  /// Opens a picked local file (registers it as a library item).
  Future<MediaItem?> openLocalFile(String path) async {
    _lastError = null;
    try {
      if (!File(path).existsSync()) {
        throw const AppException(AppErrorType.notFound);
      }
      if (!Validators.isVideoFile(path)) {
        throw const AppException(AppErrorType.unsupported);
      }
      final existing = await _library.byUri(path);
      final item = existing ??
          MediaItem(
            id: 'ml_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
            title: Validators.cleanTitle(path.split('/').last
                .replaceAll(RegExp(r'\.[a-z0-9]+$', caseSensitive: false), '')),
            uri: path,
            type: MediaItemType.local,
            sourceId: 'local',
            sizeBytes: File(path).statSync().size,
          );
      if (existing == null) await _library.upsert(item);
      await _player.open(item);
      return item;
    } catch (e, s) {
      _lastError = mapException(e, stack: s);
      AppLogger.instance.error('actions', 'openLocalFile failed', e, s);
      return null;
    }
  }

  /// Plays a library item inside an optional queue (playlist / tab list).
  ///
  /// YouTube items are resolved HERE (single choke point), so every
  /// entry path — links tab, share intents, retry inside the player,
  /// mini player — gets a fresh per-session stream URL.
  Future<void> playItem(MediaItem item, {List<MediaItem>? queue}) async {
    final audioUrl = await _resolveSessionStream(item);
    final list = queue ?? [item];
    final index = list.indexWhere((m) => m.id == item.id);
    await _player.open(
      item,
      queue: list,
      startIndex: index < 0 ? 0 : index,
      audioFileUrl: audioUrl,
    );
  }

  /// Resolves a per-session play URL for platform items that need it
  /// (YouTube watch URLs, TikTok share links). Keeps the stable
  /// [MediaItem.uri] as the identity and stores the time-limited stream in
  /// [MediaItem.playUri]. Returns the external audio URL (YouTube
  /// high-quality), or null.
  Future<String?> _resolveSessionStream(MediaItem item) async {
    // Social links (Facebook video/reel, Twitter/X status) are HTML pages,
    // not media — resolve the real stream first (v1.6.0).
    if (SocialResolver.isSocialUrl(item.uri)) {
      final r = await SocialResolver.instance.resolve(item.uri);
      if (r == null) return null; // graceful: player reports the real error
      item.liveHint = false;
      item.playUri = r.playUrl;
      if (r.width != null) item.width = r.width;
      if (r.height != null) item.height = r.height;
      if (r.headers.isNotEmpty) {
        item.headers = {...?item.headers, ...r.headers};
      }
      return null;
    }
    // TikTok share links are HTML pages, not media — extract the real
    // MP4 first, otherwise mpv fails with an unknown playback error.
    if (TikTokResolver.isTikTokUrl(item.uri)) {
      final r = await TikTokResolver.instance.resolve(item.uri);
      if (r == null) return null; // graceful: player reports the real error
      item.liveHint = false;
      item.playUri = r.playUrl;
      if (r.width != null) item.width = r.width;
      if (r.height != null) item.height = r.height;
      if (r.headers != null && r.headers!.isNotEmpty) {
        item.headers = {...?item.headers, ...r.headers!};
      }
      return null;
    }
    if (!YouTubeResolver.isYouTubeUrl(item.uri)) return null;
    final r = await YouTubeResolver.instance.resolve(item.uri);
    if (r == null) return null; // graceful: player reports the real error
    item.liveHint = r.isLive;
    item.playUri = r.playUrl ?? item.uri;
    if (r.width != null && r.height != null) {
      item.width = r.width;
      item.height = r.height;
    }
    return r.audioUrl;
  }

  /// Registers an imported playlist entry without opening the player.
  Future<MediaItem?> registerExternal(String title, String uri, bool isLocal) async {
    try {
      final existing = await _library.byUri(uri);
      if (existing != null) return existing;
      final item = MediaItem(
        id: 'mx_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        title: Validators.cleanTitle(title),
        uri: uri,
        type: isLocal ? MediaItemType.local : MediaItemType.network,
        sourceId: isLocal ? 'local' : 'direct',
      );
      await _library.upsert(item);
      return item;
    } catch (e, s) {
      AppLogger.instance.error('actions', 'registerExternal failed', e, s);
      return null;
    }
  }
}
