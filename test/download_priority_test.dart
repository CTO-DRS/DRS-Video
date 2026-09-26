import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/data/models/download_task.dart';

void main() {
  group('downloadScore (deterministic priority algorithm)', () {
    test('user priority dominates', () {
      final now = DateTime.now();
      final high = downloadScore(
        priority: DownloadPriority.high,
        sizeBytes: 1000000000,
        onWifi: true,
        needsWifiOnly: false,
        requestedAt: now,
      );
      final low = downloadScore(
        priority: DownloadPriority.low,
        sizeBytes: 1000,
        onWifi: true,
        needsWifiOnly: false,
        requestedAt: now,
      );
      expect(high, greaterThan(low));
    });

    test('wifi bonus helps on wifi', () {
      final now = DateTime.now();
      final onWifi = downloadScore(
        priority: DownloadPriority.normal,
        sizeBytes: 0,
        onWifi: true,
        needsWifiOnly: false,
        requestedAt: now,
      );
      final onCellular = downloadScore(
        priority: DownloadPriority.normal,
        sizeBytes: 0,
        onWifi: false,
        needsWifiOnly: false,
        requestedAt: now,
      );
      expect(onWifi, greaterThan(onCellular));
    });

    test('wifi-only tasks are strongly deprioritized without wifi', () {
      final now = DateTime.now();
      final blocked = downloadScore(
        priority: DownloadPriority.high,
        sizeBytes: 0,
        onWifi: false,
        needsWifiOnly: true,
        requestedAt: now,
      );
      final normal = downloadScore(
        priority: DownloadPriority.low,
        sizeBytes: 0,
        onWifi: false,
        needsWifiOnly: false,
        requestedAt: now,
      );
      expect(blocked, lessThan(normal));
    });

    test('smaller files preferred within same priority', () {
      final now = DateTime.now();
      final small = downloadScore(
        priority: DownloadPriority.normal,
        sizeBytes: 10 * 1024 * 1024,
        onWifi: true,
        needsWifiOnly: false,
        requestedAt: now,
      );
      final big = downloadScore(
        priority: DownloadPriority.normal,
        sizeBytes: 1000 * 1024 * 1024,
        onWifi: true,
        needsWifiOnly: false,
        requestedAt: now,
      );
      expect(small, greaterThan(big));
    });

    test('is deterministic', () {
      final now = DateTime.now();
      final args = (
        priority: DownloadPriority.normal,
        sizeBytes: 500,
        onWifi: true,
        needsWifiOnly: false,
        requestedAt: now,
      );
      final a = downloadScore(
        priority: args.priority,
        sizeBytes: args.sizeBytes,
        onWifi: args.onWifi,
        needsWifiOnly: args.needsWifiOnly,
        requestedAt: args.requestedAt,
      );
      final b = downloadScore(
        priority: args.priority,
        sizeBytes: args.sizeBytes,
        onWifi: args.onWifi,
        needsWifiOnly: args.needsWifiOnly,
        requestedAt: args.requestedAt,
      );
      expect(a, b);
    });
  });

  group('compareQueueOrder', () {
    DownloadTaskModel task(String id, DownloadPriority p, DateTime at) =>
        DownloadTaskModel(
          id: id,
          url: 'https://a.com/$id.mp4',
          savedDir: '/tmp',
          fileName: '$id.mp4',
          status: DownloadStatus.queued,
          priority: p,
          createdAt: at,
        );

    test('high priority first, then FIFO', () {
      final t0 = DateTime(2024, 1, 1, 10);
      final t1 = DateTime(2024, 1, 1, 11);
      final tasks = [
        task('normalOld', DownloadPriority.normal, t0),
        task('highNew', DownloadPriority.high, t1),
        task('lowMid', DownloadPriority.low, t0),
      ]..sort(compareQueueOrder);
      expect(tasks.map((t) => t.id).toList(),
          ['highNew', 'normalOld', 'lowMid']);
    });
  });

  test('DownloadTaskModel maps through the database schema', () {
    final t = DownloadTaskModel(
      id: 'dl_x',
      url: 'https://a.com/v.mp4',
      savedDir: '/data/downloads',
      fileName: 'v.mp4',
      status: DownloadStatus.running,
      progress: 42,
      expectedSize: 1000,
      priority: DownloadPriority.high,
    );
    final restored = DownloadTaskModel.fromMap(t.toMap());
    expect(restored.id, 'dl_x');
    expect(restored.status, DownloadStatus.running);
    expect(restored.progress, 42);
    expect(restored.priority, DownloadPriority.high);
    expect(restored.bytesDone, 420);
    expect(restored.filePath, '/data/downloads/v.mp4');
  });

  test('status helpers', () {
    expect(DownloadStatus.queued.isActive, isTrue);
    expect(DownloadStatus.completed.isActive, isFalse);
    expect(DownloadStatus.failed.isTerminal, isTrue);
    expect(AppConstants.defaultMaxConcurrentDownloads, greaterThanOrEqualTo(1));
  });
}
