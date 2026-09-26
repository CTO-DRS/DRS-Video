import '../../data/models/media_item.dart';
import 'arabic_text_analyzer.dart';

/// Kinds of auto-generated (virtual) playlists. All generators are
/// deterministic, fully local and never touch the database — the caller
/// supplies the library pool + progress map.
enum SmartPlaylistKind { continueWatching, unwatched, mostPlayed, recentlyPlayed, favorites, becauseYouWatched }

/// One generated playlist. [anchorTitle] is set only for
/// [SmartPlaylistKind.becauseYouWatched] (the watched title it derives from).
class SmartPlaylist {
  const SmartPlaylist({
    required this.kind,
    required this.items,
    this.anchorTitle,
  });

  final SmartPlaylistKind kind;
  final List<MediaItem> items;

  /// Only for becauseYouWatched playlists.
  final String? anchorTitle;
}

/// Builds all smart playlist candidates for the user in one call, using
/// the same normalization/keyword machinery as the rest of the v1.5-1.6
/// smart layer. Playlists with <2 items are omitted (nothing useful to show).
class SmartPlaylistGenerator {
  SmartPlaylistGenerator({ArabicTextAnalyzer? analyzer})
      : analyzer = analyzer ?? const ArabicTextAnalyzer();

  final ArabicTextAnalyzer analyzer;

  static const int _maxPerPlaylist = 25;
  static const int _maxBecauseYouWatched = 4;

  /// Returns the standard set: continue watching, unwatched discoveries,
  /// most played, recently played, favorites + up to
  /// [_maxBecauseYouWatched] "because you watched …" lists.
  List<SmartPlaylist> generate({
    required List<MediaItem> library,
    required Map<String, WatchProgress?> progressByItem,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final out = <SmartPlaylist>[];

    // ---- continue watching --------------------------------------------
    final inProgress = <MediaItem>[];
    for (final item in library) {
      final p = progressByItem[item.id];
      if (p == null || p.completed) continue;
      final r = p.ratio();
      if (r > 0.05 && r < 0.9) inProgress.add(item);
    }
    inProgress.sort((a, b) {
      final pa = progressByItem[a.id]!;
      final pb = progressByItem[b.id]!;
      final c = pb.updatedAt.compareTo(pa.updatedAt);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });
    out.add(SmartPlaylist(
        kind: SmartPlaylistKind.continueWatching, items: inProgress.take(_maxPerPlaylist).toList()));

    // ---- unwatched discoveries ----------------------------------------
    final fresh = library
        .where((m) => m.playCount == 0 && progressByItem[m.id] == null)
        .toList()
      ..sort((a, b) {
        final c = b.addedAt.compareTo(a.addedAt);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    out.add(SmartPlaylist(
        kind: SmartPlaylistKind.unwatched, items: fresh.take(_maxPerPlaylist).toList()));

    // ---- most played ----------------------------------------------------
    final played = library.where((m) => m.playCount > 0).toList()
      ..sort((a, b) {
        final c = b.playCount.compareTo(a.playCount);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    out.add(SmartPlaylist(
        kind: SmartPlaylistKind.mostPlayed, items: played.take(_maxPerPlaylist).toList()));

    // ---- recently played (last 14 days) --------------------------------
    final recent = library
        .where((m) =>
            m.lastPlayedAt != null &&
            at.difference(m.lastPlayedAt!).inDays <= 14)
        .toList()
      ..sort((a, b) {
        final c = b.lastPlayedAt!.compareTo(a.lastPlayedAt!);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    out.add(SmartPlaylist(
        kind: SmartPlaylistKind.recentlyPlayed, items: recent.take(_maxPerPlaylist).toList()));

    // ---- favorites -------------------------------------------------------
    final favs = library.where((m) => m.isFavorite).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    out.add(SmartPlaylist(
        kind: SmartPlaylistKind.favorites, items: favs.take(_maxPerPlaylist).toList()));

    // ---- because you watched -------------------------------------------
    final watchedWithTitles = library
        .where((m) => m.playCount > 0 && m.lastPlayedAt != null)
        .toList()
      ..sort((a, b) {
        final c = b.lastPlayedAt!.compareTo(a.lastPlayedAt!);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });

    final emittedAnchors = <String>{};
    var emitted = 0;
    for (final anchor in watchedWithTitles) {
      if (emitted >= _maxBecauseYouWatched) break;
      if (emittedAnchors.contains(anchor.title)) continue;
      emittedAnchors.add(anchor.title);

      final anchorKw = analyzer
          .tokenize(anchor.title, dropStopwords: true)
          .where((w) => w.length >= 3)
          .toSet();
      if (anchorKw.isEmpty) continue;

      final similar = <MediaItem, int>{};
      for (final cand in library) {
        if (cand.id == anchor.id) continue;
        final candKw = analyzer
            .tokenize(cand.title, dropStopwords: true)
            .where((w) => w.length >= 3)
            .toSet();
        final shared = anchorKw.intersection(candKw).length;
        if (shared > 0) similar[cand] = shared;
      }
      if (similar.isEmpty) continue;

      final items = similar.keys.toList()
        ..sort((a, b) {
          final c = similar[b]!.compareTo(similar[a]!);
          if (c != 0) return c;
          return a.id.compareTo(b.id);
        });
      out.add(SmartPlaylist(
          kind: SmartPlaylistKind.becauseYouWatched,
          items: items.take(_maxPerPlaylist).toList(),
          anchorTitle: anchor.title));
      emitted++;
    }

    // Keep only lists with something to show.
    return out.where((p) => p.items.length >= 2).toList();
  }
}
