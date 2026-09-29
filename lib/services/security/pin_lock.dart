import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// How long after leaving the app the PIN is asked again.
enum AppLockDelay { immediate, oneMinute, fiveMinutes }

extension AppLockDelayX on AppLockDelay {
  /// Persisted token.
  String get id => switch (this) {
        AppLockDelay.immediate => 'immediate',
        AppLockDelay.oneMinute => '1m',
        AppLockDelay.fiveMinutes => '5m',
      };

  static AppLockDelay fromId(String? id) => switch (id) {
        '1m' => AppLockDelay.oneMinute,
        '5m' => AppLockDelay.fiveMinutes,
        _ => AppLockDelay.immediate,
      };

  /// Wall-clock gap that must elapse before re-locking.
  Duration get duration => switch (this) {
        AppLockDelay.immediate => Duration.zero,
        AppLockDelay.oneMinute => const Duration(minutes: 1),
        AppLockDelay.fiveMinutes => const Duration(minutes: 5),
      };
}

/// PIN hashing: iterated salted SHA-256 (key-stretching lite).
///
/// The stored format is `<saltHex>:<hashHex>` — a single string that can
/// live inside SharedPreferences and is trivially versionable later.
/// The PIN itself is never persisted anywhere.
class PinHasher {
  PinHasher._();

  /// Iteration count: cheap enough for phones, expensive enough that a
  /// 4-digit PIN cannot be brute-forced from a leaked record instantly
  /// (10^4 combos x 5000 hashes each).
  static const int iterations = 5000;

  static final Random _random = Random.secure();

  /// 16 random bytes as hex — unique per installation.
  static String newSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Iterated hash of [pin] with [saltHex].
  static String hash(String pin, String saltHex) {
    List<int> digest = utf8.encode('$saltHex:$pin');
    for (var i = 0; i < iterations; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Packs salt+hash into the storage format.
  static String pack(String saltHex, String hashHex) => '$saltHex:$hashHex';

  /// Unpacks the storage format; null when malformed.
  static ({String salt, String hash})? unpack(String? stored) {
    if (stored == null) return null;
    final parts = stored.split(':');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return (salt: parts[0], hash: parts[1]);
  }

  /// True when [pin] matches the stored `<salt>:<hash>` record.
  static bool verify(String pin, String stored) {
    final rec = unpack(stored);
    if (rec == null) return false;
    // Constant-ish time: always hash before comparing.
    final candidate = hash(pin, rec.salt);
    var diff = 0;
    for (var i = 0; i < candidate.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ rec.hash.codeUnitAt(i);
    }
    return diff == 0 && candidate.length == rec.hash.length;
  }
}

/// Outcome of an unlock attempt.
enum UnlockResult { success, wrongPin, lockedOut }

/// Lifecycle-aware app-lock brain (pure Dart, no widgets).
///
/// Rules:
/// - If no PIN is configured the gate is always open.
/// - Cold start with a PIN: locked.
/// - Leaving the app (paused) marks the moment; coming back locks when
///   the configured [AppLockDelay] has elapsed.
/// - 5 consecutive wrong PINs trigger a 30-second lockout with a live
///   countdown; a successful unlock resets the counter.
class AppLockController extends ChangeNotifier {
  AppLockController({
    required String? storedHash,
    AppLockDelay delay = AppLockDelay.immediate,
    DateTime Function()? clock,
  })  : _storedHash = storedHash,
        delay = delay,
        _now = clock ?? DateTime.now,
        _locked = storedHash != null;

  final DateTime Function() _now;
  String? _storedHash;
  AppLockDelay delay;

  bool _locked;
  int _attempts = 0;
  DateTime? _lockoutUntil;
  DateTime? _pausedAt;

  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(seconds: 30);

  /// True when a PIN is configured.
  bool get hasPin => _storedHash != null;

  /// True when the gate must be shown.
  bool get isLocked => _locked;

  /// Consecutive wrong PIN attempts (reset on success).
  int get attempts => _attempts;

  /// Remaining lockout time, or null when not locked out.
  Duration? get lockoutRemaining {
    final until = _lockoutUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    return left.isNegative ? null : left;
  }

  /// True while the user is temporarily locked out after repeated
  /// failures.
  bool get isLockedOut => lockoutRemaining != null;

  /// Updates the configured delay (settings screen).
  set delaySetting(AppLockDelay d) {
    delay = d;
    notifyListeners();
  }

  /// Called by the lifecycle observer when the app goes to background.
  void onPaused() {
    if (!hasPin) return;
    _pausedAt = _now();
  }

  /// Called when the app becomes visible again: locks when enough time
  /// has passed since [onPaused].
  void onResumed() {
    final paused = _pausedAt;
    _pausedAt = null;
    if (!hasPin) return;
    if (paused == null) return;
    if (_now().difference(paused) >= delay.duration) {
      _locked = true;
      notifyListeners();
    }
  }

  /// Re-lock immediately (used by tests and by the settings screen).
  void lock() {
    if (!hasPin) return;
    _locked = true;
    notifyListeners();
  }

  /// Attempts an unlock; never throws.
  UnlockResult unlock(String pin) {
    final stored = _storedHash;
    if (stored == null) return UnlockResult.success;
    final remaining = lockoutRemaining;
    if (remaining != null) return UnlockResult.lockedOut;
    final ok = PinHasher.verify(pin, stored);
    if (!ok) {
      _attempts += 1;
      if (_attempts >= maxAttempts) {
        _lockoutUntil = _now().add(lockoutDuration);
        _attempts = 0;
      }
      notifyListeners();
      return UnlockResult.wrongPin;
    }
    _attempts = 0;
    _lockoutUntil = null;
    _locked = false;
    notifyListeners();
    return UnlockResult.success;
  }

  /// Sets a new PIN (returns the packed storage string to persist).
  /// A 4+ digit PIN is required; returns null otherwise.
  String? setPin(String pin) {
    final trimmed = pin.trim();
    if (trimmed.length < 4 || int.tryParse(trimmed) == null) return null;
    final salt = PinHasher.newSalt();
    final hash = PinHasher.hash(trimmed, salt);
    _storedHash = PinHasher.pack(salt, hash);
    _locked = false;
    _attempts = 0;
    _lockoutUntil = null;
    notifyListeners();
    return _storedHash;
  }

  /// Removes the PIN after verifying the current one.
  bool removePin(String currentPin) {
    if (_storedHash == null) return true;
    if (isLockedOut) return false;
    if (!PinHasher.verify(currentPin, _storedHash!)) {
      _attempts += 1;
      notifyListeners();
      return false;
    }
    _storedHash = null;
    _attempts = 0;
    _lockoutUntil = null;
    _locked = false;
    notifyListeners();
    return true;
  }

  /// Replaces the stored hash (app restart restore path).
  void restore(String? storedHash, AppLockDelay delay) {
    _storedHash = storedHash;
    this.delay = delay;
    _locked = storedHash != null && _locked;
    notifyListeners();
  }
}
