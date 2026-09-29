import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/logger.dart';

/// Trust-On-First-Use (TOFU) store for SSH host keys — the same trust
/// model OpenSSH uses for a brand-new `known_hosts` entry.
///
/// P2 security fix (C3): both SFTP call sites used to pass
/// `disableHostkeyVerification: true`, which made every SFTP connection
/// silently accept ANY server key — a machine-in-the-middle could
/// impersonate the user's NAS or backup target and harvest credentials.
///
/// Fingerprints are OpenSSH-style `SHA256:<base64>` strings of the raw
/// host key, keyed by lowercase `host:port`. They are public trust
/// anchors (not secrets) but stay device-local: they are excluded from
/// backup exports so trust decisions are never transplanted.
class HostKeyTrustStore {
  HostKeyTrustStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _keyPrefix = 'ssh_hostkey_';
  static const String _mismatchPrefix = 'ssh_hostkey_mm_';

  String keyFor(String host, int port) =>
      '$_keyPrefix${host.toLowerCase()}_$port';

  String _mismatchKeyFor(String host, int port) =>
      '$_mismatchPrefix${host.toLowerCase()}_$port';

  /// The stored fingerprint for `host:port`, or null when never seen.
  String? trustedFingerprint(String host, int port) =>
      _prefs.getString(keyFor(host, port));

  bool isTrusted(String host, int port) =>
      _prefs.getString(keyFor(host, port)) != null;

  /// Records/overwrites the trusted fingerprint. Called on first use, and
  /// by an explicit user re-trust action after a verified server change
  /// (which also clears any pending mismatch record).
  Future<void> trust(String host, int port, String fingerprint) async {
    await _prefs.setString(keyFor(host, port), fingerprint);
    await _prefs.remove(_mismatchKeyFor(host, port));
  }

  /// The fingerprint the host presented during the most recent rejected
  /// handshake (null = no pending mismatch). Shown in the re-trust
  /// prompt so the user can compare it with their server admin's record.
  String? lastMismatchFingerprint(String host, int port) =>
      _prefs.getString(_mismatchKeyFor(host, port));

  /// Called by [SshTofuVerifier] right before rejecting a connection.
  Future<void> recordMismatch(
          String host, int port, String presentedFingerprint) =>
      _prefs.setString(_mismatchKeyFor(host, port), presentedFingerprint);

  /// Drops the trust anchor (e.g. user re-configured the host, or removed
  /// the server). The next connect re-runs TOFU.
  Future<void> forget(String host, int port) async {
    await _prefs.remove(keyFor(host, port));
    await _prefs.remove(_mismatchKeyFor(host, port));
  }
}

/// The per-connection decision callback handed to dartssh2's
/// `SSHClient(onVerifyHostKey: ...)`.
///
/// dartssh2 already validates the SSH transport signature; this handler
/// additionally pins the fingerprint:
///  - first sight of the host → trust and remember (TOFU, logged);
///  - matching fingerprint   → accept;
///  - mismatch               → REJECT + log loudly (potential MITM or a
///    re-imaged server — the user must re-trust explicitly).
///
/// Returning false makes dartssh2 fail the handshake with
/// [SSHHostkeyError]; [NasService.browseGuarded] maps that to a typed
/// network error whose detail names the host so the UI can explain it.
class SshTofuVerifier {
  SshTofuVerifier(
    this._trust,
    this._host,
    this._port, {
    this.label = 'ssh',
  });

  final HostKeyTrustStore _trust;
  final String _host;
  final int _port;

  /// Log tag ('nas' | 'cloud-backup').
  final String label;

  /// dartssh2 4.1.0 `SSHHostkeyVerifyHandler` shape.
  FutureOr<bool> call(String keyType, Uint8List fingerprintBytes) async {
    final fingerprint =
        utf8.decode(fingerprintBytes, allowMalformed: false);
    final stored = _trust.trustedFingerprint(_host, _port);
    if (stored == null) {
      await _trust.trust(_host, _port, fingerprint);
      AppLogger.instance.info(
          label,
          'TOFU: trusting new host key for $_host:$_port '
          '($keyType ${fingerprint.replaceAll('SHA256:', '')})');
      return true;
    }
    if (stored == fingerprint) return true;
    AppLogger.instance.warning(
        label,
        'SSH HOST KEY CHANGED for $_host:$_port — stored '
        '${stored.replaceAll('SHA256:', '')}, presented '
        '${fingerprint.replaceAll('SHA256:', '')} ($keyType). '
        'Connection rejected (possible MITM or server rebuild); '
        're-save the host to re-trust.');
    // Persist the presented fingerprint so the UI can offer an informed
    // re-trust decision (OpenSSH-style prompt).
    await _trust.recordMismatch(_host, _port, fingerprint);
    return false;
  }
}
