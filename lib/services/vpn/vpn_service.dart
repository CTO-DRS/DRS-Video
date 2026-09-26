import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';

import '../../core/storage/preferences_service.dart';
import '../../core/utils/logger.dart';
import '../network/vpngate_service.dart';

/// UI-facing VPN connection states (decoupled from the plugin enum so a
/// plugin change can never ripple into screens).
enum VpnState { unsupported, disconnected, preparing, connecting, connected, disconnecting, error }

/// A VPN server selection: either a VPNGate row or an imported .ovpn.
class VpnTarget {
  VpnTarget({
    required this.name,
    required this.config,
    this.subtitle = '',
    this.isFromVpngate = false,
    this.serverJson,
  });

  factory VpnTarget.fromVpngate(VpngateServer s) => VpnTarget(
        name: s.countryLong.isEmpty ? s.hostName : s.countryLong,
        subtitle: '${(s.speedBps / 1000000).toStringAsFixed(1)} Mbps · '
            'ping ${s.ping} ms',
        config: s.config ?? '',
        isFromVpngate: true,
        serverJson: jsonEncode({
          'name': s.countryLong.isEmpty ? s.hostName : s.countryLong,
          'subtitle': '${(s.speedBps / 1000000).toStringAsFixed(1)} Mbps',
          'config': s.configBase64,
        }),
      );

  factory VpnTarget.fromStoredJson(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    // VPNGate targets store the base64 config; imported ones store raw.
    final stored = map['config'] as String? ?? '';
    final looksBase64 = !stored.contains('\n') && stored.length > 64;
    final config = looksBase64
        ? utf8.decode(base64.decode(stored.trim().replaceAll('\n', '')))
        : stored;
    return VpnTarget(
      name: map['name'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      config: config,
      isFromVpngate: true,
      serverJson: raw,
    );
  }

  final String name;
  final String subtitle;

  /// Full .ovpn config text.
  final String config;
  final bool isFromVpngate;

  /// Persistable JSON (null for ad-hoc imports).
  final String? serverJson;

  bool get isValid => config.contains('remote ');
}

/// Real OpenVPN client on top of the openvpn_flutter plugin
/// (ics-openvpn core). Free VPN = VPNGate public servers (no account,
/// no fees) + user-imported .ovpn files. Every plugin call is guarded:
/// a VPN failure degrades to an honest error state, never a crash.
class VpnService extends ChangeNotifier {
  VpnService({required PreferencesService prefs}) : _prefs = prefs;

  final PreferencesService _prefs;
  OpenVPN? _engine;
  bool _initializing = false;
  bool _pluginAvailable = true;

  VpnState _state = VpnState.disconnected;
  VpnTarget? _current;
  String? _lastError;
  String _stageText = '';

  VpnState get state => _state;
  VpnTarget? get current => _current;
  String? get lastError => _lastError;
  String get stageText => _stageText;

  /// Lifetime reconnect target persisted in prefs (name + config).
  VpnTarget? _remembered;
  VpnTarget? get remembered {
    _remembered ??= _loadRemembered();
    return _remembered;
  }

  VpnTarget? _loadRemembered() {
    final raw = _prefs.vpnLastServer;
    if (raw == null || raw.isEmpty) return null;
    try {
      final t = VpnTarget.fromStoredJson(raw);
      return t.isValid ? t : null;
    } catch (_) {
      return null;
    }
  }

  bool get isConnected => _state == VpnState.connected;
  bool get isBusy =>
      _state == VpnState.connecting ||
      _state == VpnState.preparing ||
      _state == VpnState.disconnecting;

  // ------------------------------------------------------------------

  /// Lazily initializes the plugin engine (first open of the protection
  /// screen). Never throws: engine failure -> honest unsupported state.
  Future<bool> ensureInitialized() async {
    if (kIsWeb ||
        (!kIsWeb &&
            defaultTargetPlatform != TargetPlatform.android)) {
      _pluginAvailable = false;
      _state = VpnState.unsupported;
      notifyListeners();
      return false;
    }
    if (_engine != null) return _pluginAvailable;
    if (_initializing) return false;
    _initializing = true;
    try {
      final engine = OpenVPN(
        onVpnStatusChanged: (_) {},
        onVpnStageChanged: _onStage,
      );
      await engine.initialize(
        localizedDescription: 'DRS Video VPN',
        lastStage: (stage) {},
      );
      _engine = engine;
      _pluginAvailable = true;
      // Re-sync in case the tunnel survives from a previous session.
      final s = await engine.isConnected();
      if (s && _state == VpnState.disconnected) {
        _state = VpnState.connected;
      }
      AppLogger.instance.info('vpn', 'openvpn engine ready');
    } catch (e, s) {
      _pluginAvailable = false;
      _state = VpnState.unsupported;
      _lastError = e.toString();
      AppLogger.instance.error('vpn', 'engine init failed', e, s);
    } finally {
      _initializing = false;
      notifyListeners();
    }
    return _pluginAvailable;
  }

  void _onStage(VPNStage stage, String raw) {
    _stageText = raw;
    switch (stage) {
      case VPNStage.connected:
        _state = VpnState.connected;
        _lastError = null;
        break;
      case VPNStage.disconnected:
      case VPNStage.exiting:
        if (_state != VpnState.error) _state = VpnState.disconnected;
        break;
      case VPNStage.disconnecting:
        _state = VpnState.disconnecting;
        break;
      case VPNStage.denied:
        _state = VpnState.disconnected;
        _lastError = 'permission-denied';
        break;
      case VPNStage.error:
        _state = VpnState.error;
        break;
      default:
        if (_state != VpnState.error) {
          _state = VpnState.connecting;
        }
    }
    notifyListeners();
  }

  /// Android VPN consent (system dialog). Returns true when granted.
  Future<bool> requestPermission() async {
    final engine = _engine;
    if (engine == null) return false;
    try {
      return await engine.requestPermissionAndroid();
    } catch (e) {
      AppLogger.instance.warning('vpn', 'permission request failed: $e');
      return false;
    }
  }

  /// Connects to a VPNGate row or an imported config. Keeps ONE remote
  /// line (the plugin's own filter throws with single-remote files).
  Future<bool> connect(VpnTarget target) async {
    if (!await ensureInitialized()) return false;
    if (isBusy) return false;
    if (!target.isValid) {
      _lastError = 'invalid-config';
      _state = VpnState.error;
      notifyListeners();
      return false;
    }
    _lastError = null;
    _state = VpnState.preparing;
    _stageText = '';
    notifyListeners();
    try {
      final granted = await requestPermission();
      if (!granted) {
        _state = VpnState.disconnected;
        notifyListeners();
        return false;
      }
      _current = target;
      _state = VpnState.connecting;
      notifyListeners();
      final reduced = singleRemoteConfig(target.config);
      await _engine!.connect(
        reduced,
        'DRS Video — ${target.name}',
        certIsRequired: target.config.contains('<cert>'),
      );
      // Persist for one-tap reconnect.
      if (target.serverJson != null) {
        _prefs.vpnLastServer = target.serverJson;
        _remembered = null; // reload lazily
      }
      return true;
    } catch (e, s) {
      _state = VpnState.error;
      _lastError = e.toString();
      AppLogger.instance.error('vpn', 'connect failed', e, s);
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    final engine = _engine;
    if (engine == null) return;
    _state = VpnState.disconnecting;
    notifyListeners();
    try {
      engine.disconnect();
    } catch (e) {
      AppLogger.instance.warning('vpn', 'disconnect failed: $e');
      _state = VpnState.disconnected;
    }
    // The stage listener finalizes the state; add a watchdog anyway.
    Future.delayed(const Duration(seconds: 4), () {
      if (_state == VpnState.disconnecting) {
        _state = VpnState.disconnected;
        notifyListeners();
      }
    });
  }

  // ------------------------------------------------------------------

  /// Pure config reducer (unit-tested): keeps a single `remote` line to
  /// avoid the plugin's multi-remote UI-freeze, and strips `auth-user-pass`
  /// file references that would block unattended connections.
  static String singleRemoteConfig(String config) {
    final lines = config.split('\n');
    final remoteIndexes = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().toLowerCase().startsWith('remote ')) {
        remoteIndexes.add(i);
      }
    }
    for (var k = 1; k < remoteIndexes.length; k++) {
      lines[remoteIndexes[k]] = '# DRS: extra remote disabled';
    }
    return lines.join('\n');
  }
}
