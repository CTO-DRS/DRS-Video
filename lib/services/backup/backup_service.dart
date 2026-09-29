import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/storage/preferences_service.dart';
import '../../core/utils/logger.dart';
import '../../data/models/media_item.dart';
import '../../data/models/playlist.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/playlist_repository.dart';

/// Everything a backup file contains, in a versioned envelope.
class BackupPayload {
  const BackupPayload({
    required this.items,
    required this.playlists,
    required this.progress,
    required this.searches,
    required this.settings,
  });

  /// Raw `media_items` rows (JSON-safe maps).
  final List<Map<String, Object?>> items;

  /// One entry per playlist with its ordered item ids.
  final List<Map<String, Object?>> playlists;

  /// Raw `watch_progress` rows.
  final List<Map<String, Object?>> progress;

  /// Recent search queries (restored in order).
  final List<String> searches;

  /// Preferences snapshot (typed values).
  final Map<String, Object?> settings;

  Map<String, Object?> toJson() => {
        'items': items,
        'playlists': playlists,
        'progress': progress,
        'searches': searches,
        'settings': settings,
      };

  static BackupPayload fromJson(Map<String, Object?> json) => BackupPayload(
        items: _mapList(json['items']),
        playlists: _mapList(json['playlists']),
        progress: _mapList(json['progress']),
        searches: (json['searches'] as List<Object?>? ?? const [])
            .whereType<String>()
            .toList(),
        settings: (json['settings'] as Map<String, Object?>? ?? const {}),
      );

  static List<Map<String, Object?>> _mapList(Object? raw) =>
      (raw as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .toList();
}

/// Human-readable counts shown before export / after import.
class BackupSummary {
  const BackupSummary({
    required this.items,
    required this.playlists,
    required this.progressEntries,
    required this.searches,
  });

  final int items;
  final int playlists;
  final int progressEntries;
  final int searches;
}

/// Result of an import (merge) run.
class BackupImportResult {
  const BackupImportResult({
    required this.addedItems,
    required this.skippedItems,
    required this.addedPlaylists,
    required this.mergedPlaylists,
    required this.restoredProgress,
    required this.restoredSearches,
    required this.appliedSettings,
  });

  final int addedItems;
  final int skippedItems;
  final int addedPlaylists;
  final int mergedPlaylists;
  final int restoredProgress;
  final int restoredSearches;
  final int appliedSettings;

  @override
  String toString() => 'BackupImportResult(+items:$addedItems, '
      'skip:$skippedItems, +pl:$addedPlaylists, merge:$mergedPlaylists, '
      'prog:$restoredProgress, search:$restoredSearches, prefs:$appliedSettings)';
}

/// Thrown by [BackupCodec.decode] with a user-presentable reason key.
class BackupFormatException implements Exception {
  const BackupFormatException(this.reason);
  final String reason;

  @override
  String toString() => 'BackupFormatException($reason)';
}

/// Pure JSON codec for backup envelopes.
///
/// Envelope shape:
/// ```json
/// {
///   "format": "drs-video-backup",
///   "schema": 1,
///   "appVersion": "1.7.0",
///   "exportedAt": "2026-09-27T10:00:00.000Z",
///   "sha256": "<hex of UTF-8 jsonEncode(data)>",
///   "data": { "items": [...], "playlists": [...], "progress": [...],
///             "searches": [...], "settings": {...} }
/// }
/// ```
///
/// The checksum makes truncated/hand-edited files fail loudly on import
/// instead of corrupting the user's library halfway through the merge.
class BackupCodec {
  const BackupCodec();

  static const String format = 'drs-video-backup';
  static const int schema = 1;

  String encode(BackupPayload payload, {DateTime? exportedAt}) {
    final data = payload.toJson();
    final checksum = sha256.convert(utf8.encode(jsonEncode(data))).toString();
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'schema': schema,
      'appVersion': AppConstants.appVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'sha256': checksum,
      'data': data,
    });
  }

  /// Validates and decodes. Throws [BackupFormatException] with a stable
  /// reason string: `empty`, `json`, `format`, `schema`, `checksum`,
  /// `structure`.
  ({BackupPayload payload, String appVersion, DateTime exportedAt}) decode(
      String raw) {
    if (raw.trim().isEmpty) {
      throw const BackupFormatException('empty');
    }
    Object? root;
    try {
      root = jsonDecode(raw);
    } on FormatException {
      throw const BackupFormatException('json');
    }
    if (root is! Map<String, Object?>) {
      throw const BackupFormatException('format');
    }
    if (root['format'] != format) {
      throw const BackupFormatException('format');
    }
    final fileSchema = root['schema'];
    if (fileSchema is! int || fileSchema > schema) {
      throw const BackupFormatException('schema');
    }
    final data = root['data'];
    if (data is! Map<String, Object?>) {
      throw const BackupFormatException('structure');
    }
    final expected = root['sha256'];
    if (expected is! String ||
        expected !=
            sha256.convert(utf8.encode(jsonEncode(data))).toString()) {
      throw const BackupFormatException('checksum');
    }
    final exportedAtRaw = root['exportedAt'];
    final exportedAt = exportedAtRaw is String
        ? DateTime.tryParse(exportedAtRaw)?.toUtc() ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();
    return (
      payload: BackupPayload.fromJson(data),
      appVersion:
          root['appVersion'] is String ? root['appVersion'] as String : '?',
      exportedAt: exportedAt,
    );
  }

  /// jsonEncode round-trips bools as bools while the DB layer stores
  /// integers; normalize any bool value (recursively) to 0/1 so
  /// `MediaItem.fromMap` / `WatchProgress.fromMap` keep working.
  static Map<String, Object?> normalize(Map<String, Object?> map) {
    final out = <String, Object?>{};
    map.forEach((k, v) {
      out[k] = switch (v) {
        bool b => b ? 1 : 0,
        Map<String, Object?> m => normalize(m),
        _ => v,
      };
    });
    return out;
  }
}

/// Gathers app data into a shareable JSON file and restores it back.
///
/// Export writes under the app documents directory and opens the system
/// share sheet (user picks Drive/local network/anything). Import opens the
/// file picker limited to .json and MERGES into the existing library —
/// nothing is ever deleted, duplicates (by id or uri) are skipped.
class BackupService {
  BackupService({
    required LibraryRepository library,
    required PlaylistRepository playlists,
    required HistoryRepository history,
    required PreferencesService prefs,
  })  : _library = library,
        _playlists = playlists,
        _history = history,
        _prefs = prefs;

  final LibraryRepository _library;
  final PlaylistRepository _playlists;
  final HistoryRepository _history;
  final PreferencesService _prefs;

  final BackupCodec _codec = BackupCodec();

  // ---------------------------------------------------------------- export

  /// Collects a summary (counts) for the backup screen. Vaulted items are
  /// counted too: backups must be complete (v1.10.0).
  Future<BackupSummary> summarize() async {
    final items = await _library
        .query(const LibraryQuery(limit: 100000, includeHidden: true));
    final pl = await _playlists.list();
    final progress = await _history.progressMap();
    final searches = await _history.recentSearches(limit: 500);
    return BackupSummary(
      items: items.length,
      playlists: pl.length,
      progressEntries: progress.length,
      searches: searches.length,
    );
  }

  /// Builds the backup JSON, writes it under the app documents dir and
  /// returns the written file path.
  Future<String> buildBackupFile() async {
    final payload = await _collect();
    final json = _codec.encode(payload);
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'backups'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final stamp = DateTime.now();
    final name = 'drs-video-backup'
        '-${stamp.year}${_two(stamp.month)}${_two(stamp.day)}'
        '-${_two(stamp.hour)}${_two(stamp.minute)}.json';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(json, flush: true);
    AppLogger.instance.info('backup', 'built ${file.path}');
    return file.path;
  }

  /// Shares the generated file through the system share sheet.
  Future<void> shareBackupFile(String path) async {
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/json')],
      subject: 'DRS Video backup',
    );
  }

  Future<BackupPayload> _collect() async {
    // includeHidden: the vault is part of the library — a backup that
    // silently drops hidden rows would lose them on restore.
    final items = await _library
        .query(const LibraryQuery(limit: 100000, includeHidden: true));
    final playlists = await _playlists.list();
    final plMaps = <Map<String, Object?>>[];
    for (final pl in playlists) {
      final itemIds =
          (await _playlists.items(pl.id)).map((m) => m.id).toList();
      plMaps.add({
        'id': pl.id,
        'name': pl.name,
        'createdAt': pl.createdAt.millisecondsSinceEpoch,
        'itemIds': itemIds,
      });
    }
    final progress =
        (await _history.progressMap()).values.map((w) => w.toMap()).toList();
    final searches = await _history.recentSearches(limit: 500);
    return BackupPayload(
      items: items.map((m) => m.toMap()).toList(),
      playlists: plMaps,
      progress: progress,
      searches: searches,
      settings: _prefs.exportSnapshot(),
    );
  }

  // ---------------------------------------------------------------- import

  /// Opens the system file picker (JSON only) and returns the file content,
  /// or null when the user cancelled.
  Future<String?> pickBackupFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final file = res?.files.single;
    if (file == null) return null;
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return utf8.decode(file.bytes!, allowMalformed: true);
    }
    final path = file.path;
    if (path == null) return null;
    return File(path).readAsString();
  }

  /// Decodes (validating) without touching the database — lets the UI show
  /// a confirm step before merging.
  ({BackupPayload payload, String appVersion, DateTime exportedAt})
      parseBackup(String raw) {
    return _codec.decode(raw);
  }

  /// Merges a validated payload into the live stores. Never deletes.
  Future<BackupImportResult> mergeInto(BackupPayload payload) async {
    // ---- media items -----------------------------------------------------
    var addedItems = 0;
    var skippedItems = 0;
    final knownIds = <String>{};
    for (final raw in payload.items) {
      if (raw['id'] is! String || raw['uri'] is! String) {
        skippedItems++;
        continue;
      }
      final map = BackupCodec.normalize(raw);
      final id = map['id'] as String;
      final uri = map['uri'] as String;
      knownIds.add(id);
      final byId = await _library.byId(id);
      final byUri = await _library.byUri(uri);
      if (byId != null || byUri != null) {
        skippedItems++;
        continue;
      }
      try {
        await _library.upsert(MediaItem.fromMap(map));
        addedItems++;
      } catch (e) {
        skippedItems++;
        AppLogger.instance.warning('backup', 'item import failed: $e');
      }
    }

    // ---- playlists -------------------------------------------------------
    var addedPlaylists = 0;
    var mergedPlaylists = 0;
    final existingPlaylists = await _playlists.list();
    Playlist? byName(String name) {
      for (final pl in existingPlaylists) {
        if (pl.name == name) return pl;
      }
      return null;
    }

    for (final raw in payload.playlists) {
      final name = raw['name'];
      if (name is! String || name.trim().isEmpty) continue;
      // An item id is usable when it was imported in THIS run OR it already
      // exists in the local library (e.g. imported by an earlier backup or
      // matched by uri). Anything else would dangle in playlist_items.
      final usable = <String>[];
      for (final itemId in raw['itemIds'] as List<Object?>? ?? const []) {
        if (itemId is! String) continue;
        if (knownIds.contains(itemId) || await _library.byId(itemId) != null) {
          usable.add(itemId);
        }
      }
      if (usable.isEmpty) continue;
      var target = byName(name);
      if (target == null) {
        target = await _playlists.create(name);
        addedPlaylists++;
      } else {
        mergedPlaylists++;
      }
      await _playlists.addItems(target.id, usable);
    }

    // ---- watch progress --------------------------------------------------
    var restoredProgress = 0;
    for (final raw in payload.progress) {
      if (raw['item_id'] is! String) continue;
      final map = BackupCodec.normalize(raw);
      final incoming = WatchProgress.fromMap(map);
      final current = await _history.progressFor(incoming.itemId);
      if (current != null && current.updatedAt.isAfter(incoming.updatedAt)) {
        continue; // keep the newer local position
      }
      await _history.upsertProgress(incoming);
      restoredProgress++;
    }

    // ---- searches --------------------------------------------------------
    var restoredSearches = 0;
    final seen = <String>{};
    for (final q in payload.searches) {
      final query = q.trim();
      if (query.isEmpty || !seen.add(query.toLowerCase())) continue;
      await _history.addSearch(query);
      restoredSearches++;
    }

    // ---- settings --------------------------------------------------------
    final appliedSettings = await _prefs.applySnapshot(payload.settings);

    final result = BackupImportResult(
      addedItems: addedItems,
      skippedItems: skippedItems,
      addedPlaylists: addedPlaylists,
      mergedPlaylists: mergedPlaylists,
      restoredProgress: restoredProgress,
      restoredSearches: restoredSearches,
      appliedSettings: appliedSettings,
    );
    AppLogger.instance.info('backup', 'merged $result');
    return result;
  }

  // ---------------------------------------------------------------- helpers

  static String _two(int n) => n.toString().padLeft(2, '0');
}
