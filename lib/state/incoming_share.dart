import 'package:flutter/foundation.dart';

import '../core/utils/logger.dart';
import '../services/network/smart_url.dart';
import '../services/platform/native_channel.dart';

/// Receives video URLs coming into the app from OUTSIDE (v1.3.0):
///  - Android share sheet ("مشاركة" → DRS Video) — ACTION_SEND text
///  - "Open with" on video/http links — ACTION_VIEW
///  - rtsp/rtmp/ftp deep links
///
/// [pending] holds the latest extracted URL; the shell shows a real
/// dialog (play now / save only / cancel). Nothing here can crash the
/// app: malformed intent payloads are logged and dropped.
class IncomingShareController extends ChangeNotifier {
  String? _pending;
  bool _nativeHooked = false;

  /// URL waiting for the user's decision, or null.
  String? get pending => _pending;

  /// Registers the native intent listener and pulls a cold-start URL.
  /// Called once from the root shell after boot.
  Future<void> init() async {
    if (_nativeHooked) return;
    _nativeHooked = true;
    NativeChannel.instance.handleIntentUrls((url) => push(url));
    try {
      final initial = await NativeChannel.instance.initialIntentUrl();
      if (initial != null) push(initial);
    } catch (e) {
      AppLogger.instance.warning('share', 'initial intent pull failed: $e');
    }
  }

  /// Accepts raw intent text: extracts the first URL inside it.
  /// Ignores non-URL payloads silently (share sheets often send extra
  /// text like the app name).
  void push(String raw) {
    final url = SmartUrl.extractUrlFromText(raw) ??
        (SmartUrl.hasSupportedScheme(raw.trim()) ? raw.trim() : null);
    if (url == null) {
      AppLogger.instance.info('share', 'ignored non-URL share payload');
      return;
    }
    if (url == _pending) return;
    _pending = url;
    notifyListeners();
  }

  /// Clears the pending URL after the user decided (or canceled).
  void consume() {
    _pending = null;
    notifyListeners();
  }
}
