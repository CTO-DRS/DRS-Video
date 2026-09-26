import '../../core/constants/app_constants.dart';
import '../../core/utils/validators.dart';

enum MediaItemType { local, network, download }

/// Central entity: any playable video known to the app.
class MediaItem {
  MediaItem({
    required this.id,
    required this.title,
    required this.uri,
    required this.type,
    this.thumbPath,
    this.sourceId,
    this.extension,
    this.durationMs,
    this.sizeBytes,
    this.width,
    this.height,
    DateTime? addedAt,
    this.lastPlayedAt,
    this.playCount = 0,
    this.isFavorite = false,
    this.introEndMs,
    this.outroStartMs,
    this.headers,
    this.playUri,
  }) : addedAt = addedAt ?? DateTime.now();

  final String id;
  String title;
  final String uri;
  final MediaItemType type;
  String? thumbPath;
  String? sourceId;
  final String? extension;
  int? durationMs;
  int? sizeBytes;
  int? width;
  int? height;
  final DateTime addedAt;
  DateTime? lastPlayedAt;
  int playCount;
  bool isFavorite;

  /// Provided only when the source exposes intro/outro data; the player
  /// shows Skip buttons exclusively when these are non-null.
  int? introEndMs;
  int? outroStartMs;

  /// Optional HTTP headers for network playback (private sources).
  Map<String, String>? headers;

  /// Per-session playback URL for streams whose playable address differs
  /// from the stable logical [uri] (e.g. SFTP proxy URL with token, FTP URL
  /// with credentials, WebDAV signed URL). Null for plain links.
  String? playUri;

  /// Runtime hint set for live IPTV channels: skips resume and progress
  /// saving. NOT persisted.
  bool liveHint = false;

  /// True when this row represents a streaming-platform asset (direct link,
  /// IPTV channel or NAS file). Tags use deterministic prefixes so old rows
  /// (custom sources) are unaffected.
  bool get isStream {
    if (type != MediaItemType.network) return false;
    final s = sourceId;
    if (s == null) return false;
    return s == AppConstants.streamSourceLink ||
        s.startsWith(AppConstants.streamSourceIptv) ||
        s.startsWith(AppConstants.streamSourceNas);
  }

  /// Address actually handed to the player: the per-session playback URL
  /// when present, otherwise the stable logical uri.
  String get playbackUrl => playUri ?? uri;

  bool get isLocalFile => type != MediaItemType.network;

  String get displayExtension =>
      extension ?? (isLocalFile ? Validators.extensionOf(uri) : '');

  static Map<String, String>? _decodeHeaders(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, Object?>.from(Uri.splitQueryString(raw));
      return map.cast<String, String>();
    } catch (_) {
      return null;
    }
  }

  static String _encodeHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '';
    return Uri(queryParameters: headers).query.replaceFirst('?', '');
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'uri': uri,
        'thumb_path': thumbPath,
        'source_id': sourceId,
        'type': type.name,
        'ext': extension,
        'duration_ms': durationMs,
        'size_bytes': sizeBytes,
        'width': width,
        'height': height,
        'added_at': addedAt.millisecondsSinceEpoch,
        'last_played_at': lastPlayedAt?.millisecondsSinceEpoch,
        'play_count': playCount,
        'is_favorite': isFavorite ? 1 : 0,
        'intro_end_ms': introEndMs,
        'outro_start_ms': outroStartMs,
        'headers': _encodeHeaders(headers),
        'play_uri': playUri,
      };

  static MediaItem fromMap(Map<String, Object?> m) => MediaItem(
        id: m['id'] as String,
        title: m['title'] as String,
        uri: m['uri'] as String,
        type: MediaItemType.values.byName(m['type'] as String),
        thumbPath: m['thumb_path'] as String?,
        sourceId: m['source_id'] as String?,
        extension: m['ext'] as String?,
        durationMs: m['duration_ms'] as int?,
        sizeBytes: m['size_bytes'] as int?,
        width: m['width'] as int?,
        height: m['height'] as int?,
        addedAt: DateTime.fromMillisecondsSinceEpoch(m['added_at'] as int),
        lastPlayedAt: m['last_played_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['last_played_at'] as int),
        playCount: (m['play_count'] as int?) ?? 0,
        isFavorite: ((m['is_favorite'] as int?) ?? 0) == 1,
        introEndMs: m['intro_end_ms'] as int?,
        outroStartMs: m['outro_start_ms'] as int?,
        headers: _decodeHeaders(m['headers'] as String?),
        playUri: m['play_uri'] as String?,
      );
}

/// Watch position snapshot for resumable playback.
class WatchProgress {
  const WatchProgress({
    required this.itemId,
    required this.positionMs,
    this.durationMs,
    this.completed = false,
    required this.updatedAt,
  });

  final String itemId;
  final int positionMs;
  final int? durationMs;
  final bool completed;
  final DateTime updatedAt;

  /// 0..1 fraction watched (used by UI progress bars and recommendations).
  double ratio() {
    if (durationMs == null || durationMs! <= 0) return 0;
    return (positionMs / durationMs!).clamp(0.0, 1.0);
  }

  Map<String, Object?> toMap() => {
        'item_id': itemId,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'completed': completed ? 1 : 0,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static WatchProgress fromMap(Map<String, Object?> m) => WatchProgress(
        itemId: m['item_id'] as String,
        positionMs: m['position_ms'] as int,
        durationMs: m['duration_ms'] as int?,
        completed: ((m['completed'] as int?) ?? 0) == 1,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );
}
