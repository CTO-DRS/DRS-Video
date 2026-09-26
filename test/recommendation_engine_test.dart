import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/services/recommendations/recommendation_engine.dart';

void main() {
  final engine = const RecommendationEngine();

  MediaItem item(String id, {bool fav = false, DateTime? lastPlayed, String? source}) =>
      MediaItem(
        id: id,
        title: 'Video $id',
        uri: 'https://example.com/$id.mp4',
        type: MediaItemType.network,
        isFavorite: fav,
        lastPlayedAt: lastPlayed,
        sourceId: source,
      );

  test('favorites and unfinished items rank higher', () {
    final now = DateTime.now();
    final candidates = [
      item('plain'),
      item('fav', fav: true, lastPlayed: now.subtract(const Duration(days: 1))),
    ];
    final scored = engine.recommend(
      candidates: candidates,
      progressByItem: {},
      recentHistory: const [],
    );
    expect(scored.first.item.id, 'fav');
    expect(scored.first.reasons, contains(ReasonKind.favorite));
  });

  test('unfinished (in-progress) videos are boosted', () {
    final candidates = [item('a'), item('b')];
    final progress = <String, WatchProgress?>{
      'a': WatchProgress(
        itemId: 'a',
        positionMs: 300000,
        durationMs: 600000,
        updatedAt: DateTime.now(),
      ),
      'b': null,
    };
    final scored = engine.recommend(
      candidates: candidates,
      progressByItem: progress,
      recentHistory: const [],
    );
    expect(scored.first.item.id, 'a');
    expect(scored.first.reasons, contains(ReasonKind.unfinished));
  });

  test('completed items are penalized', () {
    final candidates = [item('done'), item('new')];
    final progress = <String, WatchProgress?>{
      'done': WatchProgress(
        itemId: 'done',
        positionMs: 590000,
        durationMs: 600000,
        completed: true,
        updatedAt: DateTime.now(),
      ),
      'new': null,
    };
    final scored = engine.recommend(
      candidates: candidates,
      progressByItem: progress,
      recentHistory: const [],
    );
    expect(scored.first.item.id, 'new');
  });

  test('deterministic: same input yields same order', () {
    final now = DateTime.now();
    final candidates = [
      item('x', fav: true, lastPlayed: now),
      item('y', lastPlayed: now.subtract(const Duration(hours: 2))),
      item('z'),
    ];
    final r1 = engine.recommend(candidates: candidates, progressByItem: {}, recentHistory: const []);
    final r2 = engine.recommend(candidates: candidates, progressByItem: {}, recentHistory: const []);
    expect(r1.map((s) => s.item.id).toList(), r2.map((s) => s.item.id).toList());
  });

  test('respects limit', () {
    final candidates = List.generate(30, (i) => item('i$i'));
    final scored = engine.recommend(
      candidates: candidates,
      progressByItem: {},
      recentHistory: const [],
      limit: 5,
    );
    expect(scored.length, 5);
  });
}
