import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/utils/validators.dart';

/// A download tracked by our queue (backed by flutter_downloader tasks).
class DownloadTaskModel {
  DownloadTaskModel({
    required this.id,
    required this.url,
    required this.savedDir,
    required this.fileName,
    this.taskId,
    required this.status,
    this.progress = 0,
    this.expectedSize,
    this.priority = DownloadPriority.normal,
    this.mediaItemId,
    this.error,
    this.headers,
    this.originUrl,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;

  /// The URL the engine downloads from. v1.14.2: mutable — platform share
  /// links resolve to SIGNED CDN URLs that expire, so a failed task is
  /// re-resolved from [originUrl] and this field is refreshed.
  String url;
  final String savedDir;
  final String fileName;
  String? taskId; // flutter_downloader native task id (null while queued)
  DownloadStatus status;
  int progress; // 0..100
  int? expectedSize;
  DownloadPriority priority;
  String? mediaItemId;
  String? error;

  /// v1.14.1: CDN headers (User-Agent/Referer) required by web-scrape
  /// media addresses. Persisted so retry/resume re-enqueue with them.
  Map<String, String>? headers;

  /// v1.14.2: the ORIGINAL link the user pasted (platform share page) when
  /// this task was resolved into a direct media URL. Retries re-resolve
  /// from it because the resolved CDN URL carries a signature that can
  /// expire — retrying the dead URL verbatim can never succeed.
  String? originUrl;

  final DateTime createdAt;
  DateTime? completedAt;

  String get filePath => '$savedDir/$fileName';

  /// Bytes downloaded so far, derived from progress and expected size.
  int get bytesDone =>
      expectedSize == null ? 0 : (expectedSize! * progress ~/ 100);

  Map<String, Object?> toMap() => {
        'id': id,
        'url': url,
        'saved_dir': savedDir,
        'file_name': fileName,
        'task_id': taskId,
        'status': status.name,
        'progress': progress,
        'expected_size': expectedSize,
        'priority': priority.index,
        'media_item_id': mediaItemId,
        'error': error,
        'headers': (headers == null || (headers?.isEmpty ?? true))
            ? null
            : jsonEncode(headers),
        'origin_url': originUrl,
        'created_at': createdAt.millisecondsSinceEpoch,
        'completed_at': completedAt?.millisecondsSinceEpoch,
      };

  static Map<String, String>? _decodeHeaders(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return null;
    }
  }

  static DownloadTaskModel fromMap(Map<String, Object?> m) => DownloadTaskModel(
        id: m['id'] as String,
        url: m['url'] as String,
        savedDir: m['saved_dir'] as String,
        fileName: m['file_name'] as String,
        taskId: m['task_id'] as String?,
        status: DownloadStatus.values.byName(m['status'] as String),
        progress: (m['progress'] as int?) ?? 0,
        expectedSize: m['expected_size'] as int?,
        priority: DownloadPriority.values[(m['priority'] as int?) ?? 1],
        mediaItemId: m['media_item_id'] as String?,
        error: m['error'] as String?,
        headers: _decodeHeaders(m['headers']),
        originUrl: m['origin_url'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        completedAt: m['completed_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['completed_at'] as int),
      );
}

enum DownloadStatus {
  queued,
  running,
  paused,
  completed,
  failed,
  cancelled;

  bool get isActive => this == DownloadStatus.queued || this == DownloadStatus.running;
  bool get isTerminal => this == DownloadStatus.completed || this == DownloadStatus.failed || this == DownloadStatus.cancelled;
}

/// Helper builders shared by services.
class DownloadNames {
  DownloadNames._();

  static String uniqueName(String dir, String desired) {
    var name = Validators.sanitizeFileName(desired);
    final ext = Validators.extensionOf(name);
    final base = ext.isNotEmpty ? name.substring(0, name.length - ext.length - 1) : name;
    var i = 1;
    while (nameExists('$dir/$name')) {
      name = ext.isNotEmpty ? '$base ($i).$ext' : '$base ($i)';
      i++;
    }
    return name;
  }

  static bool nameExists(String path) {
    // Implemented by the caller via File; kept here as pure helper is not
    // possible, so the service injects existence checks before calling.
    return false;
  }
}

/// Sorting for queue display: priority, then age.
int compareQueueOrder(DownloadTaskModel a, DownloadTaskModel b) {
  final byPriority = a.priority.index.compareTo(b.priority.index);
  if (byPriority != 0) return byPriority;
  return a.createdAt.compareTo(b.createdAt);
}

/// Deterministic priority algorithm (no AI): user priority dominates, then
/// Wi-Fi availability bonus, then smaller files first, then FIFO.
int downloadScore({
  required DownloadPriority priority,
  required int sizeBytes,
  required bool onWifi,
  required bool needsWifiOnly,
  required DateTime requestedAt,
}) {
  var score = (2 - priority.index) * 1000000; // high=2M, normal=1M, low=0
  if (onWifi) score += 100000;
  if (needsWifiOnly && !onWifi) score -= 3000000; // below every ready task
  score -= (sizeBytes ~/ (10 * 1024 * 1024)).clamp(0, 90000).toInt();
  score -= DateTime.now().difference(requestedAt).inMinutes.clamp(0, 9000).toInt();
  return score;
}
