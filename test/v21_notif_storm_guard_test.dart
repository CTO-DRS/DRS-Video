import 'package:flutter_test/flutter_test.dart';

import 'package:drs_video/services/downloader/download_service.dart';
import 'package:drs_video/services/notifications/notification_service.dart';

/// v1.14.7 regression guards for the two field-reported download bugs:
///  1) 'download stays stuck forever' — engine tasks were excluded from
///     the watchdog; non-promotable native tasks were pause/resume-kicked
///     endlessly (each kick re-raising its native notification).
///  2) 'endless notifications after updating' — automatic recovery
///     re-attacked dead links on every launch/wifi flip, spawning fresh
///     native notifications per attempt (showNotification: true) plus an
///     unthrottled local failure notification per final failure.
void main() {
  group('v1.14.7 fail-chain (cross-session auto-restart gate)', () {
    test('pure gate semantics', () {
      expect(failChainBlocksAutoRestart(0), isFalse);
      expect(failChainBlocksAutoRestart(1), isFalse);
      expect(failChainBlocksAutoRestart(2), isTrue,
          reason: 'at the ceiling the task is parked');
      expect(failChainBlocksAutoRestart(10), isTrue);
      expect(failChainBlocksAutoRestart(1, max: 1), isTrue);
      // DownloadService.maxFailChain must match the pure default.
      expect(DownloadService.maxFailChain, 2);
    });
  });

  group('v1.14.7 failure-notification throttle', () {
    test('pure dedupe: one per file per window', () {
      final last = <String, DateTime>{};
      final t0 = DateTime(2026, 1, 1, 12);
      expect(failureNotifAllowed(last, 'a.mp4', t0), isTrue);
      last['a.mp4'] = t0;
      // Within the 10-minute window: suppressed.
      expect(failureNotifAllowed(last, 'a.mp4', t0.add(const Duration(minutes: 9))), isFalse);
      // After the window: allowed again.
      expect(failureNotifAllowed(last, 'a.mp4', t0.add(const Duration(minutes: 10))), isTrue);
      // A different file is never suppressed by another file's entry.
      expect(failureNotifAllowed(last, 'b.mp4', t0), isTrue);
      // Empty map: always allowed.
      expect(failureNotifAllowed(const {}, 'a.mp4', t0), isTrue);
    });
  });
}
