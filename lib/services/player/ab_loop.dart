import 'dart:math' as math;
import 'dart:ui';

/// Pure A-B loop state machine (v1.1.0) — framework-free and unit tested.
///
/// Lifecycle: [AbLoopState.off] -> tap marks A -> [AbLoopState.aMarked] ->
/// tap marks B -> [AbLoopState.active] (position wraps from B back to A) ->
/// tap disables. A tap in [aMarked] that lands BEFORE the A point swaps
/// them so the loop is always valid.
enum AbLoopState { off, aMarked, active }

class AbLoop {
  AbLoop({this.a, this.b});

  Duration? a;
  Duration? b;

  AbLoopState get state => switch ((a, b)) {
        (null, _) => AbLoopState.off,
        (Duration(), null) => AbLoopState.aMarked,
        (Duration(), Duration()) => AbLoopState.active,
      };

  bool get isActive => state == AbLoopState.active;

  /// Marks the current position:
  /// * off -> becomes point A
  /// * aMarked -> becomes point B (activating the loop)
  /// * active -> clears the loop
  void mark(Duration position) {
    switch (state) {
      case AbLoopState.off:
        a = position;
        b = null;
      case AbLoopState.aMarked:
        final first = a!;
        if (position <= first) {
          // Second mark before A: the marks swap roles.
          a = position;
          b = first;
        } else {
          b = position;
        }
      case AbLoopState.active:
        clear();
    }
  }

  void clear() {
    a = null;
    b = null;
  }

  /// Returns the rewind target when [position] crossed point B, or null
  /// when no jump should happen.
  Duration? jumpFrom(Duration position) {
    if (!isActive) return null;
    if (position >= b!) return a;
    return null;
  }

  /// True when the current position is inside the active loop window
  /// (used to highlight the progress bar section).
  bool contains(Duration position) {
    if (!isActive) return false;
    return position >= a! && position <= b!;
  }
}

/// Smooths zoom/pan gesture math for the mpv-backed player (pure logic).
class ViewGestureTracker {
  ViewGestureTracker({required this.initialZoom, required this.initialPan});

  final double initialZoom;
  final Offset initialPan;

  /// Distance between the two fingers when the gesture started.
  double? startDistance;
  Offset? startMidpoint;

  /// Applies the first update of a two-finger gesture.
  void begin({required double distance, required Offset midpoint}) {
    startDistance = distance.clamp(1.0, double.infinity);
    startMidpoint = midpoint;
  }

  /// Converts live finger state into mpv video-zoom / video-pan values.
  ({double zoom, Offset pan}) update({
    required double distance,
    required Offset midpoint,
    required double viewportShortSide,
    required double maxZoom,
    required double maxPan,
  }) {
    final start = startDistance ?? distance;
    final scale = (distance / start).clamp(0.2, 8.0);
    // mpv zoom is logarithmic: +1.0 doubles the picture.
    final zoom = (initialZoom + (scale <= 0 ? 0.0 : math.log(scale) / math.ln2))
        .clamp(0.0, maxZoom);
    var pan = initialPan;
    final origin = startMidpoint ?? midpoint;
    if (viewportShortSide > 0) {
      final delta = midpoint - origin;
      pan = Offset(
        (initialPan.dx + delta.dx / viewportShortSide).clamp(-maxPan, maxPan),
        (initialPan.dy + delta.dy / viewportShortSide).clamp(-maxPan, maxPan),
      );
    }
    return (zoom: zoom, pan: pan);
  }
}
