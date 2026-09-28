import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/utils/logger.dart';
import '../permissions/permission_service.dart';

/// Pure decision: may a failure notification for [key] be shown at [now]?
/// One notification per file per [window] — field reports showed endless
/// notification storms when dead-link tasks auto-retried across sessions
/// (every attempt re-fires 'download failed').
bool failureNotifAllowed(
  Map<String, DateTime> lastShown,
  String key,
  DateTime now, {
  Duration window = const Duration(minutes: 10),
}) {
  final last = lastShown[key];
  return last == null || now.difference(last) >= window;
}

/// Local notifications: download completion/failure and storage warnings.
/// Download progress notifications used to be rendered natively by
/// flutter_downloader — v1.14.7 disables those (every automatic retry
/// spawned a fresh native notification); completion/failure are surfaced
/// ONLY through these throttled local notifications.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Per-file last failure-notification time (see failureNotifAllowed).
  final Map<String, DateTime> _lastFailShown = {};

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _initTried = false;

  /// Whether the plugin initialized successfully (diagnostics surface).
  bool get isReady => _ready;

  /// Idempotent lazy initialization. NEVER throws to callers: a failure
  /// only keeps notifications disabled (silent degradation) — init no
  /// longer runs at app boot, so plugin problems can never abort startup.
  Future<void> init() async {
    if (_ready) return;
    if (_initTried) return; // one failed attempt: stay silent, no retry spam
    _initTried = true;
    try {
      const android = AndroidInitializationSettings('@mipmap/launcher_icon');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings);
      await _createChannels();
      _ready = true;
      AppLogger.instance.info('notif', 'initialized (lazy)');
    } catch (e, s) {
      AppLogger.instance.error('notif', 'lazy init failed (disabled)', e, s);
    }
  }

  Future<void> _createChannels() async {
    const dl = AndroidNotificationChannel(
      'drs.downloads',
      'Downloads',
      description: 'Download completion and failures',
      importance: Importance.high,
    );
    const general = AndroidNotificationChannel(
      'drs.general',
      'General',
      description: 'Storage warnings and app messages',
      importance: Importance.defaultImportance,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(dl);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(general);
  }

  Future<bool> _canNotify() async {
    if (!_ready) await init();
    if (!_ready) return false;
    if (!await PermissionService.instance.notificationsGranted()) {
      return false;
    }
    return true;
  }

  Future<void> showDownloadCompleted(String fileName) async {
    _lastFailShown.remove(fileName); // success clears the failure throttle
    if (!await _canNotify()) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'drs.downloads',
        'Downloads',
        channelDescription: 'Download completion and failures',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
      ),
    );
    await _plugin.show(
      fileName.hashCode & 0x7fffffff,
      'Download completed',
      fileName,
      details,
    );
  }

  Future<void> showDownloadFailed(String fileName, String reason) async {
    if (!await _canNotify()) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'drs.downloads',
        'Downloads',
        channelDescription: 'Download completion and failures',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.error,
      ),
    );
    await _plugin.show(
      (fileName.hashCode ^ reason.hashCode) & 0x7fffffff,
      'Download failed',
      '$fileName — $reason',
      details,
    );
  }

  /// Failure notification, throttled to one per file per 10 minutes.
  /// The dedupe decision is pure ([failureNotifAllowed]) and tested.
  Future<void> showDownloadFailedDeduped(String fileName, String reason) async {
    final now = DateTime.now();
    if (!failureNotifAllowed(_lastFailShown, fileName, now)) return;
    _lastFailShown[fileName] = now;
    await showDownloadFailed(fileName, reason);
  }

  Future<void> showStorageWarning() async {
    if (!await _canNotify()) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'drs.general',
        'General',
        channelDescription: 'Storage warnings and app messages',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    await _plugin.show(77001, 'Storage almost full',
        'Less than 300 MB free. Consider clearing space.', details);
  }
}
