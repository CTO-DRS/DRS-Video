import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/storage/cache_manager.dart';
import '../core/utils/logger.dart';
import '../data/models/media_item.dart';
import '../data/repositories/library_repository.dart';
import '../services/permissions/permission_service.dart';
import '../services/platform/native_channel.dart';

/// Scans on-device videos through MediaStore with thumbnail caching.
class LocalMediaController extends ChangeNotifier {
  LocalMediaController({
    required LibraryRepository library,
    required CacheManager cache,
  })  : _library = library,
        _cache = cache;

  final LibraryRepository _library;
  final CacheManager _cache;

  List<MediaItem> videos = [];
  bool loading = false;
  bool permissionNeeded = false;
  bool scannedOnce = false;

  Future<void> load() async {
    loading = true;
    permissionNeeded = false;
    notifyListeners();
    try {
      final perms = PermissionService.instance;
      if (!await perms.mediaGranted()) {
        permissionNeeded = true;
        videos = [];
        return;
      }
      final raw = await NativeChannel.instance.localVideos();
      videos = [
        for (final v in raw)
          MediaItem(
            id: 'ms_${v['id']}',
            title: '${v['title']}',
            uri: '${v['path']}',
            type: MediaItemType.local,
            sourceId: 'local',
            extension: null,
            durationMs: v['durationMs'] as int?,
            sizeBytes: v['sizeBytes'] as int?,
            width: v['width'] as int?,
            height: v['height'] as int?,
          ),
      ];
      scannedOnce = true;
      // Hydrate thumbnails progressively (cached after first run).
      for (final v in videos) {
        final msId = int.tryParse(v.id.substring(3));
        if (msId == null) continue;
        final cached = await _cache.get('ms_$msId');
        if (cached != null) {
          v.thumbPath = cached;
        } else {
          final thumb = await NativeChannel.instance.thumbnail(msId);
          if (thumb != null) {
            final bytes = await File(thumb).readAsBytes();
            v.thumbPath = await _cache.put('ms_$msId', bytes);
          }
        }
      }
      notifyListeners();
    } catch (e, s) {
      AppLogger.instance.error('local', 'scan failed', e, s);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Registers a MediaStore video into the library and returns it for play.
  Future<MediaItem?> registerForPlayback(MediaItem v) async {
    final existing = await _library.byUri(v.uri);
    if (existing != null) return existing;
    final item = MediaItem(
      id: 'ml_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      title: v.title,
      uri: v.uri,
      type: MediaItemType.local,
      sourceId: 'local',
      durationMs: v.durationMs,
      sizeBytes: v.sizeBytes,
      width: v.width,
      height: v.height,
      thumbPath: v.thumbPath,
    );
    await _library.upsert(item);
    return item;
  }

  Future<void> requestPermissionAndLoad() async {
    final granted = await PermissionService.instance.requestMedia();
    if (granted) {
      await load();
    } else {
      permissionNeeded = true;
      notifyListeners();
    }
  }
}
