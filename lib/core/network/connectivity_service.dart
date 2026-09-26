import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../utils/logger.dart';

/// Observes the device connection and exposes a typed level used by the
/// playback optimizer and the download gate.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService() {
    Connectivity().onConnectivityChanged.listen(_update, onError: (e) {
      AppLogger.instance.warning('net', 'connectivity stream error: $e');
    });
    // Prime the current value; stream may not emit immediately.
    Connectivity().checkConnectivity().then(_update).catchError((_) {});
  }

  NetworkLevel _level = NetworkLevel.medium;
  bool get isOnline => _level != NetworkLevel.offline;
  NetworkLevel get level => _level;
  bool get isWifi => _level == NetworkLevel.fast;

  void _update(List<ConnectivityResult> results) {
    final r = results.isEmpty ? ConnectivityResult.none : results.first;
    final level = switch (r) {
      ConnectivityResult.none => NetworkLevel.offline,
      ConnectivityResult.mobile => NetworkLevel.medium, // refined below
      ConnectivityResult.wifi ||
      ConnectivityResult.ethernet =>
        NetworkLevel.fast,
      ConnectivityResult.vpn ||
      ConnectivityResult.bluetooth ||
      ConnectivityResult.other ||
      ConnectivityResult.satellite =>
        NetworkLevel.medium,
    };
    if (level != _level) {
      _level = level;
      AppLogger.instance.info('net', 'connection -> ${level.name}');
      notifyListeners();
    }
  }

  /// Manual refinement (e.g. measured throughput) kept deterministic.
  void setMeasuredLevel(NetworkLevel level) {
    if (_level != NetworkLevel.offline && _level != level) {
      _level = level;
      notifyListeners();
    }
  }
}
