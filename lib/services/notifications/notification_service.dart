import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/utils/logger.dart';
import '../permissions/permission_service.dart';

/// Local notifications: download completion/failure and storage warnings.
/// (Download progress notifications are rendered natively by
/// flutter_downloader.)
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

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
