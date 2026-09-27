/// Audio enhancement for mpv: EQ presets + software gain boost.
///
/// Everything compiles down to a single mpv `af` (audio filter chain)
/// string built by [AudioEnhancer.buildAf] — a pure function that is
/// unit-tested. Presets use libavfilter's `equalizer` (always present in
/// mpv builds) and the boost uses `volume`, both stable across devices.
enum AudioPreset {
  /// No equalization.
  flat,

  /// Bass boost: +5 dB @ 80 Hz, +3 dB @ 150 Hz — movies and music on
  /// phone speakers.
  bass,

  /// Vocal/dialog presence: +4 dB @ 2.5 kHz, -2 dB @ 200 Hz — news,
  /// lectures, series with low dialog.
  vocal,

  /// Night mode: cuts rumble (-6 dB @ 60 Hz), lifts intelligibility
  /// (+3 dB @ 3 kHz) so low-volume night watching stays clear.
  night,

  /// Movie: mild V-curve — +3 dB @ 100 Hz, +2.5 dB @ 8 kHz, slight dip
  /// @ 1.5 kHz for room ambience.
  movie,
}

extension AudioPresetX on AudioPreset {
  /// Persisted token.
  String get id => name;

  static AudioPreset fromId(String? id) => AudioPreset.values
      .where((p) => p.name == id)
      .firstOrNull ?? AudioPreset.flat;
}

class AudioEnhancer {
  AudioEnhancer._();

  /// Maximum software boost (dB) — beyond this clipping artifacts
  /// dominate; mpv will hard-clip the signal.
  static const double maxBoostDb = 15;

  /// [preset] chain + optional [boostDb] (0..[maxBoostDb], clamped).
  /// Returns an mpv `af` value; empty string when nothing is applied
  /// (which also clears any previous filter chain).
  static String buildAf(AudioPreset preset, double boostDb) {
    final parts = <String>[];
    final boost = boostDb.clamp(0.0, maxBoostDb);
    if (boost > 0.01) {
      final db = boost.toStringAsFixed(1);
      parts.add('volume=$db');
    }
    final eq = switch (preset) {
      AudioPreset.flat => '',
      AudioPreset.bass =>
        'equalizer=f=80:t=q:w=1.2:g=5,equalizer=f=150:t=q:w=1.0:g=3',
      AudioPreset.vocal =>
        'equalizer=f=2500:t=q:w=1.0:g=4,equalizer=f=200:t=q:w=0.8:g=-2',
      AudioPreset.night =>
        'equalizer=f=60:t=q:w=0.8:g=-6,equalizer=f=3000:t=q:w=1.0:g=3',
      AudioPreset.movie =>
        'equalizer=f=100:t=q:w=1.0:g=3,equalizer=f=1500:t=q:w=1.0:g=-1.5,equalizer=f=8000:t=q:w=1.0:g=2.5',
    };
    if (eq.isNotEmpty) parts.add(eq);
    return parts.join(',');
  }

  /// True when the filter chain is effectively active.
  static bool isActive(AudioPreset preset, double boostDb) =>
      buildAf(preset, boostDb).isNotEmpty;
}
