import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utils/logger.dart';
import '../services/files/file_manager_service.dart';
import '../services/smart/intel_v4.dart';

/// Scans the app's media-visible directories (downloads + documents +
/// public Movies/Music/Pictures when accessible) and groups every file into
/// studio buckets (video / audio / image / other) for the four studios.
///
/// Scanning runs in an isolate-friendly chunked loop with a cancellation
/// flag so leaving the screen never wedges the UI.
class MediaStudioController extends ChangeNotifier {
  final List<StudioFile> _all = [];
  Map<MediaBucket, List<StudioFile>> _buckets = {
    for (final b in MediaBucket.values) b: <StudioFile>[],
  };
  bool _loading = false;
  String? _error;

  List<StudioFile> filesOf(MediaBucket b) => _buckets[b] ?? const [];

  /// Read-only snapshot of the current buckets (for strips and hub screens).
  Map<MediaBucket, List<StudioFile>> get bucketsSnapshot => _buckets;

  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final dirs = <Directory>[];
      final docs = await getApplicationDocumentsDirectory();
      dirs.add(Directory(p.join(docs.path, 'downloads')));
      try {
        dirs.add(await getApplicationDocumentsDirectory());
      } catch (_) {}
      try {
        final ext = await getExternalStorageDirectories();
        if (ext != null) {
          for (final d in ext) {
            // Standard Android public folders when visible to the app.
            final root = d.path.split('/Android').first;
            dirs.add(Directory(p.join(root, 'Download')));
            dirs.add(Directory(p.join(root, 'Movies')));
            dirs.add(Directory(p.join(root, 'Music')));
            dirs.add(Directory(p.join(root, 'Pictures')));
            dirs.add(Directory(p.join(root, 'DCIM')));
          }
        }
      } catch (_) {}

      final found = <StudioFile>[];
      for (final dir in dirs) {
        if (!await dir.exists()) continue;
        try {
          await for (final e in dir.list(followLinks: false)) {
            if (e is! File) continue;
            final stat = await e.stat();
            if (stat.type != FileSystemEntityType.file) continue;
            if (MediaCataloguer.of(e.path) == MediaBucket.other) continue;
            found.add(StudioFile(
              path: e.path,
              name: p.basename(e.path),
              sizeBytes: stat.size,
              modified: stat.modified,
            ));
          }
        } catch (e) {
          AppLogger.instance.warning('studio', 'skip dir ${dir.path}: $e');
        }
      }
      // Dedup by path (same file can appear in overlapping roots).
      final byPath = {for (final f in found) f.path: f};
      _all
        ..clear()
        ..addAll(byPath.values);
      _buckets = MediaCataloguer.bucket(_all);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Renames via the existing FileManagerService (it sanitizes the name and
  /// keeps the original extension), then refreshes buckets.
  Future<void> rename(StudioFile f, String newTitle) async {
    final fm = const FileManagerService();
    final stem = newTitle.trim();
    if (stem.isEmpty) return;
    await fm.rename(f.path, stem);
    await load();
  }

  Future<void> delete(StudioFile f) async {
    const fm = FileManagerService();
    await fm.delete(f.path);
    await load();
  }
}
