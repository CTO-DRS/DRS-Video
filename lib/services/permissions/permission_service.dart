import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/utils/logger.dart';

/// Modern Android permission model wrapper. Requests only what is needed,
/// when it is needed.
class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  int _sdkInt = 34;

  Future<void> init() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _sdkInt = info.version.sdkInt;
      AppLogger.instance.info('perm', 'sdk=$_sdkInt');
    } catch (e) {
      AppLogger.instance.warning('perm', 'deviceInfo failed: $e');
    }
  }

  /// Media read permission for listing device videos.
  Permission get _mediaPermission => _sdkInt >= 33
      ? Permission.videos
      : Permission.storage;

  Future<bool> mediaGranted() async => _mediaPermission.isGranted;

  /// Returns true when granted; false when denied (never permanently blocks).
  Future<bool> requestMedia() async {
    final status = await _mediaPermission.request();
    _log('media', status);
    return status.isGranted;
  }

  /// Notifications (Android 13+); below 13 always true.
  Future<bool> requestNotifications() async {
    if (_sdkInt < 33) return true;
    final status = await Permission.notification.request();
    _log('notifications', status);
    return status.isGranted;
  }

  Future<bool> notificationsGranted() async {
    if (_sdkInt < 33) return true;
    return Permission.notification.isGranted;
  }

  /// "All files access" for optional custom download folder (Android 11+).
  Future<bool> allFilesGranted() async {
    if (_sdkInt < 30) {
      return (await Permission.storage.status).isGranted;
    }
    return await Permission.manageExternalStorage.status.isGranted;
  }

  Future<bool> requestAllFiles() async {
    if (_sdkInt < 30) {
      final s = await Permission.storage.request();
      _log('storage', s);
      return s.isGranted;
    }
    final s = await Permission.manageExternalStorage.request();
    _log('allFiles', s);
    return s.isGranted;
  }

  Future<bool> openAppSettingsPage() => openAppSettings();

  void _log(String what, PermissionStatus s) =>
      AppLogger.instance.info('perm', '$what -> ${s.name}');
}
