/// A-B segment loop state machine (pure, no engine dependency).
///
/// Used by the player to loop a segment (Quran memorization, language
/// learning, re-watching a scene). The engine-agnostic rules live here
/// so they are unit-testable; [PlayerService] applies them to real
/// playback position updates.
class AbRepeat {
  AbRepeat({this.aMs, this.bMs});

  int? aMs;
  int? bMs;

  /// Minimum segment length — prevents A==B degenerate loops that would
  /// spin the decoder.
  static const int minSegmentMs = 500;

  bool get isActive => aMs != null && bMs != null && bMs! - aMs! >= minSegmentMs;

  /// Sets point A. If B is already set and [posMs] is at/after B, the
  /// old B is cleared first (starting a fresh segment).
  void setA(int posMs) {
    if (bMs != null && posMs >= bMs!) bMs = null;
    aMs = posMs;
  }

  /// Sets point B. When A is unset it defaults to 0 (loop from start).
  /// Returns false (and ignores) when [posMs] is not at least
  /// [minSegmentMs] past A.
  bool setB(int posMs) {
    final a = aMs ?? 0;
    if (posMs < a + minSegmentMs) return false;
    aMs = a;
    bMs = posMs;
    return true;
  }

  /// Where playback must jump when the position crosses B. Returns null
  /// when inactive or [posMs] is still inside the segment.
  int? rewindTargetMs(int posMs) {
    if (!isActive) return null;
    final a = aMs!;
    final b = bMs!;
    if (posMs >= b) return a;
    // A manual jump outside the segment (before A) breaks the loop so a
    // user seek never snaps them back.
    if (posMs < a - 1) return null;
    return null;
  }

  /// Clears both markers.
  void clear() {
    aMs = null;
    bMs = null;
  }

  /// Clears B only (keeps A as the start of a new segment).
  void clearB() {
    bMs = null;
  }
}
