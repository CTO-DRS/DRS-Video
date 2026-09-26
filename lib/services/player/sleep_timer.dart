import 'dart:async';
import 'package:flutter/material.dart';

/// Simple countdown that pauses playback when it fires.
class SleepTimer extends ChangeNotifier {
  SleepTimer(this._onFire);

  final VoidCallback _onFire;
  bool _disposed = false;

  Duration? _remaining;
  bool _endOfVideo = false;
  @Deprecated('internal')
  // ignore: unused_field
  DateTime? _deadline;

  Duration? get remaining => _remaining;
  bool get isActive => _remaining != null && _remaining! > Duration.zero;
  bool get isEndOfVideo => _endOfVideo;

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
        cancel();
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
    _remaining = null;
    notifyListeners();
  }

  void cancel() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _remaining = null;
    _deadline = null;
    _endOfVideo = false;
    notifyListeners();
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
