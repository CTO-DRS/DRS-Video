import 'dart:async';

import 'package:flutter/foundation.dart';

/// Sleep timer with two firing modes:
/// - fixed duration (presets or custom minutes)
/// - end-of-video (fires when the player reports completion)
///
/// v1.6.0 enhancement: exposes [fadeFactor] so the player can ramp volume
/// down smoothly during the final [fadeWindow] seconds instead of an abrupt
/// stop. Pure timing logic — no player coupling (the service subscribes).
class SleepTimer extends ChangeNotifier {
  SleepTimer(this._onFire);

  final VoidCallback _onFire;
  bool _disposed = false;

  Duration? _remaining;
  bool _endOfVideo = false;
  DateTime? _deadline;

  /// Volume ramps down during the last 10 seconds.
  static const Duration fadeWindow = Duration(seconds: 10);

  Duration? get remaining => _remaining;
  bool get isActive => _remaining != null && _remaining! > Duration.zero;
  bool get isEndOfVideo => _endOfVideo;

  /// 1.0 → fade just started, 0.0 → about to fire. Null when the timer is
  /// inactive or the fade window has not been entered yet.
  double? get fadeFactor {
    if (!isActive) return null;
    final left = _remaining!;
    if (left >= fadeWindow) return null;
    return (left.inMilliseconds / fadeWindow.inMilliseconds).clamp(0.0, 1.0);
  }

  void start(Duration duration) {
    _endOfVideo = false;
    _deadline = DateTime.now().add(duration);
    _remaining = duration;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      final left = _deadline!.difference(DateTime.now());
      if (left <= Duration.zero) {
        _remaining = Duration.zero;
        cancel(silent: true);
        _onFire();
      } else {
        _remaining = left;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// Fires at the end of the current video instead of a fixed duration.
  void startEndOfVideo() {
    cancel();
    _endOfVideo = true;
    notifyListeners();
  }

  /// [silent] keeps listeners notified via an explicit [notifyListeners]
  /// afterwards (used internally before _onFire so fade logic can restore
  /// volume in its own listener first).
  void cancel({bool silent = false}) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _remaining = null;
    _deadline = null;
    _endOfVideo = false;
    if (!silent) notifyListeners();
  }

  /// Called by the player when a video ends while end-of-video mode is on.
  bool consumeEndOfVideo() {
    if (!_endOfVideo) return false;
    cancel();
    return true;
  }

  Timer? _timer;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
