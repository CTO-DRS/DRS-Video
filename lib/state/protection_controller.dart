import 'package:flutter/foundation.dart';

import '../../core/storage/preferences_service.dart';
import '../../services/browser/ad_block.dart';

/// In-memory state for the protection system (v1.4.0):
/// - ad-block on/off (persisted),
/// - lifetime blocked-request counter (persisted, debounced writes),
/// - incognito mode for the built-in browser (persisted).
class ProtectionController extends ChangeNotifier {
  ProtectionController({required PreferencesService prefs})
      : _prefs = prefs {
    _adBlock = _prefs.adBlockEnabled;
    _incognito = _prefs.browserIncognito;
    _blockedTotal = _prefs.blockedRequestsCount;
  }

  final PreferencesService _prefs;

  bool _adBlock = true;
  bool _incognito = false;
  int _blockedTotal = 0;
  int _unpersisted = 0;

  bool get adBlockEnabled => _adBlock;
  bool get incognito => _incognito;
  int get blockedTotal => _blockedTotal;
  bool get blocklistReady => AdBlockList.instance.isLoaded;

  /// Live count of domains in the loaded blocklist (0 before load).
  int get blocklistSize => AdBlockList.instance.domainCount;

  void setAdBlock(bool value) {
    _adBlock = value;
    _prefs.adBlockEnabled = value;
    notifyListeners();
  }

  void setIncognito(bool value) {
    _incognito = value;
    _prefs.browserIncognito = value;
    notifyListeners();
  }

  /// Called by the browser for every blocked request. Writes to prefs
  /// are coalesced (persist every 10th hit) to keep request handling fast.
  void registerBlocked(int n) {
    if (n <= 0) return;
    _blockedTotal += n;
    _unpersisted += n;
    if (_unpersisted >= 10) {
      _prefs.blockedRequestsCount = _blockedTotal;
      _unpersisted = 0;
    }
    notifyListeners();
  }

  /// Persists a pending counter delta (called when leaving the browser).
  Future<void> flush() async {
    if (_unpersisted > 0) {
      _prefs.blockedRequestsCount = _blockedTotal;
      _unpersisted = 0;
    }
  }

  /// Clears the lifetime counter (protection screen action).
  void resetCounter() {
    _blockedTotal = 0;
    _unpersisted = 0;
    _prefs.blockedRequestsCount = 0;
    notifyListeners();
  }
}
