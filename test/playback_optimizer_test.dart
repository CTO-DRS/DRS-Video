import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/services/recommendations/playback_optimizer.dart';

void main() {
  group('PlaybackOptimizer (deterministic, no AI)', () {
    const optimizer = PlaybackOptimizer();

    test('explicit user quality always wins', () {
      for (final conn in NetworkLevel.values) {
        final p = optimizer.optimize(
          connection: conn,
          userQualitySetting: 'low',
          screenShortSideDp: 800,
        );
        expect(p.preferredQuality, 'low');
        expect(p.maxBufferSizeMb, 24);
      }
    });

    test('auto on fast connection yields high quality and big buffer', () {
      final p = optimizer.optimize(
        connection: NetworkLevel.fast,
        userQualitySetting: 'auto',
        screenShortSideDp: 800,
      );
      expect(p.preferredQuality, 'high');
      expect(p.maxBufferSizeMb, 96);
    });

    test('auto on slow connection yields data saver', () {
      final p = optimizer.optimize(
        connection: NetworkLevel.slow,
        userQualitySetting: 'auto',
        screenShortSideDp: 400,
      );
      expect(p.preferredQuality, 'low');
      expect(p.maxBufferSizeMb, 16);
    });

    test('small devices get smaller buffers', () {
      final small = optimizer.optimize(
        connection: NetworkLevel.medium,
        userQualitySetting: 'auto',
        screenShortSideDp: 340,
      );
      final big = optimizer.optimize(
        connection: NetworkLevel.medium,
        userQualitySetting: 'auto',
        screenShortSideDp: 900,
      );
      expect(small.maxBufferSizeMb, lessThan(big.maxBufferSizeMb));
    });

    test('offline still allows local playback with minimal buffer', () {
      final p = optimizer.optimize(
        connection: NetworkLevel.offline,
        userQualitySetting: 'auto',
        screenShortSideDp: 400,
      );
      expect(p.preferredQuality, 'high');
      expect(p.maxBufferSizeMb, 8);
    });
  });

  group('levelFromThroughput', () {
    test('maps throughput thresholds', () {
      expect(levelFromThroughput(10 * 1024), NetworkLevel.verySlow);
      expect(levelFromThroughput(100 * 1024), NetworkLevel.slow);
      expect(levelFromThroughput(1024 * 1024), NetworkLevel.medium);
      expect(levelFromThroughput(4 * 1024 * 1024), NetworkLevel.fast);
    });
  });
}
