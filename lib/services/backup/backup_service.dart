import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/storage/preferences_service.dart';
import '../../core/utils/logger.dart';
import '../../data/models/media_item.dart';
import '../../data/models/playlist.dart';
import '../../data/repositories/bookmark_repository.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../platform/native_channel.dart';

/// Pure payload model for v1.1.0 full backup/restore. Everything is
/// validated before any write happens, so a corrupted or foreign file can
/// never damage the local database.
class BackupPayload {
  const BackupPayload({
    required this.items,
    required this.progress,
    required this.playlists,
    required this.memberships,
    required this.bookmarks,
    required this.watchDaily,
    required this.prefs,
  });

  final List<MediaItem> items;
  final List<Map<String, Object?>> progress;
  final List<Map<String, Object?>> playlists;
  final List<Map<String, Object?>> memberships;
  final List<Map<String, Object?>> bookmarks;
  final List<Map<String, Object?>> watchDaily;
  final Map<String, Object?> prefs;

  int get recordCount =>
      items.length + progress.length + playlists.length +
      memberships.length + bookmarks.length + watchDaily.length;
}

/// Pure serializer (no IO) — unit tested end to end.
class BackupCodec {
  /// Builds the export payload map from already-serialized rows.
  static Map<String, Object?> encode({
    required List<Map<String, Object?>> itemMaps,
    required List<Map<String, Object?>> progressMaps,
    required List<Map<String, Object?>> playlistMaps,
    required List<Map<String, Object?>> membershipMaps,
    required List<Map<String, Object?>> bookmarkMaps,
    required List<Map<String, Object?>> watchDailyMaps,
    required Map<String, Object?> prefs,
  }) {
    return {
      'app': AppConstants.backupAppTag,
      'schema': AppConstants.backupSchemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'mediaItems': itemMaps,
      'watchProgress': progressMaps,
      'playlists': playlistMaps,
      'playlistItems': membershipMaps,
      'bookmarks': bookmarkMaps,
      'watchDaily': watchDailyMaps,
      'prefs': prefs,
    };
  }

  /// Parses and validates a JSON string. Returns null for anything that
  /// is not a DRS Video backup of a known schema.
  static BackupPayload? decode(String raw) {
    try {
      final dynamic doc = jsonDecode(raw);
      if (doc is! Map<String, dynamic>) return null;
      if (doc['app'] != AppConstants.backupAppTag) return null;
      final schema = doc['schema'];
      if (schema is! int || schema > AppConstants.backupSchemaVersion) {
        return null;
      }
      List<Map<String, Object?>> listOfMaps(String key) {
        final v = doc[key];
        if (v is! List) return const [];
        return v
            .whereType<Map>()
            .map((e) => Map<String, Object?>.from(e))
            .toList();
      }

      final prefs = doc['prefs'];
      return BackupPayload(
        items: listOfMaps('mediaItems').map(MediaItem.fromMap).toList(),
        progress: listOfMaps('watchProgress'),
        playlists: listOfMaps('playlists'),
        memberships: listOfMaps('playlistItems'),
        bookmarks: listOfMaps('bookmarks'),
        watchDaily: listOfMaps('watchDaily'),
        prefs:
            prefs is Map ? Map<String, Object?>.from(prefs) : <String, Object?>{},
      );
    } catch (e) {
      AppLogger.instance.warning('backup', 'payload decode failed: $e');
      return null;
    }
  }
}

/// Orchestrates export/import through the SAF bridge (no storage
/// permission needed) and the repositories. All failures are reported as
/// false + logs; nothing ever throws to the UI.
class BackupService {
  BackupService({
    required LibraryRepository library,
    required HistoryRepository history,
    required PlaylistRepository playlists,
    required BookmarkRepository bookmarks,
    required PreferencesService prefs,
    NativeChannel? native,
  })  : _library = library,
        _history = history,
        _playlists = playlists,
        _bookmarks = bookmarks,
        _prefs = prefs,
        _native = native ?? NativeChannel.instance;

  final LibraryRepository _library;
  final HistoryRepository _history;
  final PlaylistRepository _playlists;
  final BookmarkRepository _bookmarks;
  final PreferencesService _prefs;
  final NativeChannel _native;

  /// Keys backed up with the payload (appearance + playback + downloads
  /// toggles). Deliberately excludes private/source credentials.
  static const Set<String> _prefKeys = {
    'theme_mode', 'dynamic_color', 'palette', 'animations_enabled',
    'layout_mode', 'language_code', 'default_quality', 'default_speed',
    'auto_play_next', 'always_resume', 'enable_pip', 'auto_pip',
    'background_playback', 'prefer_fullscreen', 'max_concurrent_downloads',
    'wifi_only_downloads', 'history_enabled',
  };

  /// Exports everything into a user-chosen JSON document.
  /// Returns the number of restored rows, or -1 on failure/cancel.
  Future<int> exportAll() async {
    try {
      final items = await _library.listAll();
      final progress = (await _history.allProgress()).map((p) => p.toMap()).toList();
      final playlists = (await _playlists.list()).map((p) => p.toMap()).toList();
      final memberships = await _playlists.exportMemberships();
      final bookmarks = (await _bookmarks.all()).map((b) => b.toMap()).toList();
      final daily = (await _history.allWatchDaily()).map((d) => d.toMap()).toList();
      final count = items.length +
          progress.length +
          playlists.length +
          memberships.length +
          bookmarks.length +
          daily.length;
      final rawPrefs = _prefs.raw;
      final prefs = <String, Object?>{
        for (final k in _prefKeys)
          if (rawPrefs.get(k) != null) k: rawPrefs.get(k),
      };

      final payload = BackupCodec.encode(
        itemMaps: items.map((m) => m.toMap()).toList(),
        progressMaps: progress,
        playlistMaps: playlists,
        membershipMaps: memberships,
        bookmarkMaps: bookmarks,
        watchDailyMaps: daily,
        prefs: prefs,
      );
      final json = const JsonEncoder.withIndent('  ').convert(payload);

      final name =
          'drs-video-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json';
      final uri = await _native.createJsonForSave(name);
      if (uri == null) return -1; // user cancelled
      final ok = await _native.writeCreatedTextFile(uri, json);
      if (!ok) {
        AppLogger.instance.error('backup', 'write to $uri failed');
        return -1;
      }
      AppLogger.instance.info('backup', 'exported $count rows');
      return count;
    } catch (e, s) {
      AppLogger.instance.error('backup', 'export failed', e, s);
      return -1;
    }
  }

  /// Restores from a user-picked JSON document.
  /// Returns the number of applied rows, or -1 on failure/cancel.
  Future<int> importAll() async {
    try {
      final uri = await _native.pickJsonForRestore();
      if (uri == null) return -1; // user cancelled
      final raw = await _native.readPickedTextFile(uri);
      if (raw == null) {
        AppLogger.instance.error('backup', 'could not read $uri');
        return -1;
      }
      final payload = BackupCodec.decode(raw);
      if (payload == null) return -1; // invalid file (logged inside)

      await _library.upsertAll(payload.items);
      await _history.upsertProgressAll(payload.progress
          .map((m) => WatchProgress.fromMap(m))
          .toList());
      await _playlists.upsertAll(payload.playlists
          .map((m) => Playlist.fromMap(m))
          .toList());
      await _playlists.importMemberships(payload.memberships);
      await _bookmarks.upsertAll(payload.bookmarks
          .map((m) => VideoBookmark.fromMap(m))
          .toList());
      for (final d in payload.watchDaily) {
        final day = d['day'] as String?;
        final watched = (d['watched_ms'] as int?) ?? 0;
        final sessions = (d['sessions'] as int?) ?? 0;
        if (day == null || day.isEmpty) continue;
        await _history.mergeWatchDay(
          day: day,
          watchedMs: watched,
          sessions: sessions,
        );
      }
      _applyPrefs(payload.prefs);
      AppLogger.instance
          .info('backup', 'imported ${payload.recordCount} rows');
      return payload.recordCount;
    } catch (e, s) {
      AppLogger.instance.error('backup', 'import failed', e, s);
      return -1;
    }
  }

  void _applyPrefs(Map<String, Object?> prefs) {
    final raw = _prefs.raw;
    for (final entry in prefs.entries) {
      if (!_prefKeys.contains(entry.key)) continue;
      final v = entry.value;
      if (v is bool) raw.setBool(entry.key, v);
      if (v is int) raw.setInt(entry.key, v);
      if (v is double) raw.setDouble(entry.key, v);
      if (v is String) raw.setString(entry.key, v);
    }
  }
}
