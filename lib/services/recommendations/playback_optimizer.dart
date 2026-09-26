import '../../core/constants/app_constants.dart';

/// Playback optimization: picks buffering/quality policy from connection,
/// device size and user preference. Deterministic rules, no AI.
class PlaybackPolicy {
  const PlaybackPolicy({
    required this.maxBufferSizeMb,
    required this.preferredQuality,
    required this.initialSpeed,
  });

  final int maxBufferSizeMb;
  final String preferredQuality; // auto|high|medium|low
  final double initialSpeed;
}

class PlaybackOptimizer {
  const PlaybackOptimizer();

  /// Shortest side of the main display in dp; used to cap quality on
  /// small/low-end devices.
  PlaybackPolicy optimize({
    required NetworkLevel connection,
    required String userQualitySetting, // auto|high|medium|low
    required double screenShortSideDp,
  }) {
    // Explicit user choice wins.
    switch (userQualitySetting) {
      case 'high':
        return const PlaybackPolicy(maxBufferSizeMb: 96, preferredQuality: 'high', initialSpeed: 1.0);
      case 'medium':
        return const PlaybackPolicy(maxBufferSizeMb: 48, preferredQuality: 'medium', initialSpeed: 1.0);
      case 'low':
        return const PlaybackPolicy(maxBufferSizeMb: 24, preferredQuality: 'low', initialSpeed: 1.0);
    }

    // 'auto': derive from connection + device.
    switch (connection) {
      case NetworkLevel.offline:
        return const PlaybackPolicy(maxBufferSizeMb: 8, preferredQuality: 'high', initialSpeed: 1.0);
      case NetworkLevel.verySlow:
        return const PlaybackPolicy(maxBufferSizeMb: 8, preferredQuality: 'low', initialSpeed: 1.0);
      case NetworkLevel.slow:
        return const PlaybackPolicy(maxBufferSizeMb: 16, preferredQuality: 'low', initialSpeed: 1.0);
      case NetworkLevel.medium:
        return PlaybackPolicy(
          maxBufferSizeMb: screenShortSideDp < 380 ? 32 : 48,
          preferredQuality: 'medium',
          initialSpeed: 1.0,
        );
      case NetworkLevel.fast:
        return PlaybackPolicy(
          maxBufferSizeMb: screenShortSideDp < 380 ? 64 : 96,
          preferredQuality: 'high',
          initialSpeed: 1.0,
        );
    }
  }
}

/// Maps a connection level from measured throughput (fallback when
/// connectivity type alone is not enough).
NetworkLevel levelFromThroughput(double bytesPerSecond) {
  final mbps = bytesPerSecond * 8 / (1024 * 1024);
  if (mbps <= 0.15) return NetworkLevel.verySlow;
  if (mbps <= 0.8) return NetworkLevel.slow;
  if (mbps <= 8) return NetworkLevel.medium;
  return NetworkLevel.fast;
}
