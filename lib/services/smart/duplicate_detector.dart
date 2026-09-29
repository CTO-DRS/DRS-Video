import '../smart/arabic_text_analyzer.dart';
import '../../data/models/media_item.dart';

/// One cluster of mutually-similar media items (≥2 entries). [keepId] is the
/// suggested survivor; everything else is a removable duplicate.
class DuplicateCluster {
  const DuplicateCluster({required this.items, required this.keepId});

  final List<MediaItem> items;
  final String keepId;

  List<MediaItem> get duplicates => items.where((m) => m.id != keepId).toList();
  MediaItem? get keep => items.where((m) => m.id == keepId).firstOrNull;
}

/// Deterministic duplicate detection for the local library.
///
/// Two items are considered the *same video* when:
/// - normalized titles are near-identical (similarity ≥ 0.85), AND
/// - durations agree within 5% (or one is unknown), AND
/// - sizes agree within 10% (or one is unknown).
/// Identical normalized titles with identical durations are always merged
/// (covers tiny files where size is missing).
///
/// Clusters are built with Union-Find so A≈B, B≈C merges A,B,C transitively.
/// The suggested survivor maximizes a keep-score (favorite, progress,
/// thumbnails, play stats, quality). Pure — unit-testable.
class DuplicateDetector {
  DuplicateDetector({ArabicTextAnalyzer? analyzer})
      : analyzer = analyzer ?? const ArabicTextAnalyzer();

  final ArabicTextAnalyzer analyzer;

  static const double _titleSimThreshold = 0.85;

  List<DuplicateCluster> detect(List<MediaItem> items) {
    if (items.length < 2) return const [];
    final list = List.of(items);

    // Union-Find over indices.
    final parent = List<int>.generate(list.length, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]]; // path halving
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    final precomputed = [
      for (final it in list)
        (
          norm: analyzer.normalize(it.title),
          duration: it.durationMs,
          size: it.sizeBytes,
        )
    ];

    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        if (_isPair(
          list[i],
          list[j],
          precomputed[i].norm,
          precomputed[j].norm,
          precomputed[i].duration,
          precomputed[j].duration,
          precomputed[i].size,
          precomputed[j].size,
        )) {
          union(i, j);
        }
      }
    }

    // Gather clusters.
    final groups = <int, List<int>>{};
    for (var i = 0; i < list.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(i);
    }

    final clusters = <DuplicateCluster>[];
    for (final g in groups.values) {
      if (g.length < 2) continue;
      final members = g.map((i) => list[i]).toList();
      final keep = members.reduce((a, b) => _keepScore(a) >= _keepScore(b) ? a : b);
      clusters.add(DuplicateCluster(items: members, keepId: keep.id));
    }

    // Deterministic order: keep title, then keepId.
    clusters.sort((a, b) {
      final c = (a.keep?.title ?? '').compareTo(b.keep?.title ?? '');
      if (c != 0) return c;
      return a.keepId.compareTo(b.keepId);
    });
    return clusters;
  }

  bool _isPair(
    MediaItem a,
    MediaItem b,
    String na,
    String nb,
    int? da,
    int? db,
    int? sa,
    int? sb,
  ) {
    if (a.id == b.id) return false;

    final sim = analyzer.similarity(na, nb);
    final identicalTitle = na == nb;
    if (!(sim >= _titleSimThreshold ||
        (identicalTitle && da != null && da == db))) {
      return false;
    }

    final durationOk = da == null ||
        db == null ||
        (da == db) ||
        _within(da, db, 0.05);
    if (!durationOk) return false;

    final sizeOk = sa == null || sb == null || _within(sa, sb, 0.10);
    return sizeOk;
  }

  bool _within(int a, int b, double tolerance) {
    final bigger = a > b ? a : b;
    final smaller = a > b ? b : a;
    if (bigger == 0) return true;
    return (bigger - smaller) / bigger <= tolerance;
  }

  /// Higher is more worthy of being kept. Deterministic tie-breaking by id
  /// happens at the call site via `reduce`.
  int _keepScore(MediaItem m) {
    var s = 0;
    if (m.isFavorite) s += 30;
    if (m.thumbPath != null && m.thumbPath!.isNotEmpty) s += 8;
    if (m.playCount > 0) s += 4 + m.playCount.clamp(1, 8);
    if ((m.sizeBytes ?? 0) > 0) s += (m.sizeBytes! / (256 * 1024 * 1024)).clamp(0, 6).round();
    if ((m.width ?? 0) >= 1920) s += 6; // prefer higher quality
    if ((m.width ?? 0) >= 1280) s += 3;
    return s;
  }
}
