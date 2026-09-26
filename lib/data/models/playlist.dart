import 'media_item.dart';

/// User playlist with ordered videos.
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static Playlist fromMap(Map<String, Object?> m) => Playlist(
        id: m['id'] as String,
        name: m['name'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

/// Playlist with its ordered items as returned by the repository.
class PlaylistWithItems {
  PlaylistWithItems({required this.playlist, required this.items});

  final Playlist playlist;
  final List<MediaItem> items;
}

/// A registered media source (adapter configuration).
class SourceInfo {
  SourceInfo({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.headerName,
    this.headerValue,
    this.enabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  String baseUrl;
  String? headerName;
  String? headerValue;
  bool enabled;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'base_url': baseUrl,
        'header_name': headerName,
        'header_value': headerValue,
        'enabled': enabled ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static SourceInfo fromMap(Map<String, Object?> m) => SourceInfo(
        id: m['id'] as String,
        name: m['name'] as String,
        baseUrl: m['base_url'] as String,
        headerName: m['header_name'] as String?,
        headerValue: m['header_value'] as String?,
        enabled: ((m['enabled'] as int?) ?? 1) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

/// Result of resolving a playable source through a [SourceAdapter].
class ResolvedMedia {
  const ResolvedMedia({
    required this.title,
    required this.streamUrl,
    this.headers,
    this.durationMs,
    this.sizeBytes,
    this.thumbnailUrl,
    this.resumable = false,
    this.contentType,
    this.introEndMs,
    this.outroStartMs,
  });

  final String title;
  final String streamUrl;
  final Map<String, String>? headers;
  final int? durationMs;
  final int? sizeBytes;
  final String? thumbnailUrl;
  final bool resumable; // server supports HTTP Range
  final String? contentType;

  /// Intro/outro metadata only when the source provides it.
  final int? introEndMs;
  final int? outroStartMs;
}
