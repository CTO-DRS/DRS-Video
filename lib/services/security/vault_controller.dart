import 'package:flutter/foundation.dart';
import 'pin_lock.dart';

/// Private vault gate (v1.10.0): a PIN lock dedicated to hidden media,
/// fully independent from the app-lock PIN.
///
/// Design notes:
/// - Reuses [PinHasher] (salted, iterated SHA-256) — the vault PIN is
///   never persisted, only `<salt>:<hash>`.
/// - Session-scoped unlock: [unlock] opens the vault until [lock] is
///   called (the vault screen locks when it is closed). There is no
///   lifecycle auto-lock here on purpose — the vault is a screen, not an
///   app-wide gate.
/// - 5 wrong attempts trigger the same 30s lockout as the app lock, so a
///   curious friend cannot brute-force 4 digits on the couch.
class VaultController extends ChangeNotifier {
  VaultController({
    required String? storedHash,
    DateTime Function()? clock,
  })  : _storedHash = storedHash,
        _now = clock ?? DateTime.now {
    // A configured vault boots locked; without a PIN the vault screen
    // shows the setup flow instead of the gate.
    _unlocked = false;
  }

  final DateTime Function() _now;
  String? _storedHash;

  bool _unlocked = false;
  int _attempts = 0;
  DateTime? _lockoutUntil;

  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(seconds: 30);

  /// True when a vault PIN is configured.
  bool get hasPin => _storedHash != null;

  /// True when the vault contents may be shown.
  bool get isUnlocked => _unlocked && _storedHash != null;

  /// True when no PIN exists yet (setup flow must run first).
  bool get needsSetup => _storedHash == null;

  /// Consecutive wrong PIN attempts (reset on success).
  int get attempts => _attempts;

  /// Remaining lockout time, or null when not locked out.
  Duration? get lockoutRemaining {
    final until = _lockoutUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    return left.isNegative ? null : left;
  }

  /// True while temporarily locked out after repeated failures.
  bool get isLockedOut => lockoutRemaining != null;

  /// Replaces the stored hash from persistence (startup wiring).
  void restore(String? storedHash) {
    _storedHash = storedHash;
    _unlocked = false;
    _attempts = 0;
    _lockoutUntil = null;
    notifyListeners();
  }

  /// Attempts to unlock the vault; never throws.
  UnlockResult unlock(String pin) {
    final stored = _storedHash;
    if (stored == null) return UnlockResult.success;
    if (isLockedOut) return UnlockResult.lockedOut;
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
    _unlocked = true;
    notifyListeners();
    return UnlockResult.success;
  }

  /// Creates the vault PIN. Returns the packed `<salt>:<hash>` string to
  /// persist, or null when the PIN is not 4+ digits. The vault opens on
  /// success so the user lands inside their fresh vault.
  String? setPin(String pin) {
    final trimmed = pin.trim();
    if (trimmed.length < 4 || int.tryParse(trimmed) == null) return null;
    final salt = PinHasher.newSalt();
    final hash = PinHasher.hash(trimmed, salt);
    _storedHash = PinHasher.pack(salt, hash);
    _attempts = 0;
    _lockoutUntil = null;
    _unlocked = true;
    notifyListeners();
    return _storedHash;
  }

  /// Changes the PIN after verifying the current one.
  /// Returns the new packed hash, or null on wrong current PIN / lockout.
  String? changePin(String currentPin, String newPin) {
    if (_storedHash == null) return null;
    if (isLockedOut) return null;
    if (!PinHasher.verify(currentPin, _storedHash!)) {
      _attempts += 1;
      notifyListeners();
      return null;
    }
    return setPin(newPin);
  }

  /// Removes the vault PIN (and thus the gate) after verifying.
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
    _unlocked = false;
    notifyListeners();
    return true;
  }

  /// Locks the vault again (vault screen close / explicit lock action).
  void lock() {
    if (!_unlocked && _storedHash == null) return;
    _unlocked = false;
    notifyListeners();
  }
}
