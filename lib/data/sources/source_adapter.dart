import '../../data/models/playlist.dart';

/// Every media source plugs in through this interface:
///   SourceAdapter -> Resolver -> ResolvedMedia -> Player/DownloadManager
///
/// Adapters are pure resolvers: they never bypass DRM or platform terms;
/// they only handle sources that officially allow direct access.
abstract class SourceAdapter {
  String get id; // unique adapter key, e.g. 'direct'
  String get name; // display name
  bool get supportsDownload;

  /// Whether this adapter can attempt to resolve [url].
  bool canHandle(String url);

  /// Resolves a user-provided URL into a playable/downloadable object.
  Future<ResolvedMedia> resolve(String url, {Map<String, String>? extraHeaders});
}

/// Registry of adapters; new sources are added here without touching
/// the player or download layers.
class SourceRegistry {
  SourceRegistry({required List<SourceAdapter> adapters}) : _adapters = adapters;

  final List<SourceAdapter> _adapters;
  List<SourceAdapter> get adapters => List.unmodifiable(_adapters);

  SourceAdapter? find(String id) {
    for (final a in _adapters) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// First adapter that claims it can handle the URL.
  SourceAdapter? adapterFor(String url) {
    for (final a in _adapters) {
      if (a.canHandle(url)) return a;
    }
    return null;
  }
}
