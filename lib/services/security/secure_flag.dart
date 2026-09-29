import '../platform/native_channel.dart';

/// Holder keys used with [SecureFlagKeeper].
class SecureFlagKeys {
  SecureFlagKeys._();

  /// Player while a vaulted item is on screen.
  static String player(String itemId) => 'player:$itemId';

  /// The vault grid screen itself.
  static const String vault = 'vault';
}

/// Reference-counted FLAG_SECURE owner (v1.10.0).
///
/// Two screens need screen-capture protection and they can overlap
/// (the vault grid sits under a player pushed on top of it):
/// - the private vault screen (its grid must never leak into recents,
///   screenshots or screen recordings), and
/// - the player while it plays a vaulted item.
///
/// The native flag itself is a boolean, so the LAST release would decide
/// the state of everyone. A tiny holder registry keeps it deterministic:
/// the flag is cleared only when the last holder lets go.
class SecureFlagKeeper {
  SecureFlagKeeper._();

  /// Holder keys currently demanding protection (test-visible).
  static final Set<String> holders = <String>{};

  /// Injectable applier — production uses the real native channel; tests
  /// replace it and record the calls.
  static Future<void> Function(bool secure) apply =
      (secure) => NativeChannel.instance.setSecureFlag(secure);

  /// Registers a holder and turns the flag on.
  static Future<void> acquire(String key) async {
    holders.add(key);
    await apply(true);
  }

  /// Drops a holder; the flag goes off only when none remain. Never
  /// throws — a missing holder is treated as already released.
  static Future<void> release(String key) async {
    holders.remove(key);
    await apply(holders.isNotEmpty);
  }

  /// Drops every holder (app teardown / tests). The flag goes off.
  static Future<void> releaseAll() async {
    holders.clear();
    await apply(false);
  }
}
