/// Input validation and sanitization helpers (URL safety, file names).
library;

import '../constants/app_constants.dart';

class Validators {
  Validators._();

  static final RegExp _urlRegex = RegExp(
    r'^https?://[a-zA-Z0-9.\-_~]+(:[0-9]{1,5})?(/.*)?(\?.*)?(#.*)?$',
    caseSensitive: false,
  );

  /// Validates a video/stream URL: must be http(s), have a host, and a
  /// reasonable length. Rejects credentials in URL, localhost and private IPs.
  static bool isValidVideoUrl(String input) {
    final url = input.trim();
    if (url.isEmpty || url.length > 2048) return false;
    if (!_urlRegex.hasMatch(url)) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.host == 'localhost' || uri.host.endsWith('.local')) return false;
    final ip = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').firstMatch(uri.host);
    if (ip != null) {
      final parts = uri.host.split('.').map(int.parse).toList();
      if (parts[0] == 10 || parts[0] == 127 || parts[0] == 0) return false;
      if (parts[0] == 192 && parts[1] == 168) return false;
      if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return false;
    }
    if (uri.userInfo.isNotEmpty) return false;
    return true;
  }

  /// Removes path separators and illegal filename characters and clamps length.
  static String sanitizeFileName(String name, {String fallback = 'video'}) {
    var n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    n = n.replaceAll(RegExp(r'\.{2,}'), '.');
    n = n.replaceAll(RegExp(r'^\.+'), '');
    if (n.isEmpty) n = fallback;
    if (n.length > 120) n = n.substring(0, 120);
    return n;
  }

  /// Lowercase extension without dot, or '' if none.
  static String extensionOf(String pathOrUrl) {
    final clean = pathOrUrl.split('?').first.split('#').first;
    final segment = clean.split('/').last;
    final dot = segment.lastIndexOf('.');
    if (dot < 0 || dot == segment.length - 1) return '';
    return segment.substring(dot + 1).toLowerCase();
  }

  static bool isVideoFile(String pathOrUrl) =>
      AppConstants.videoExtensions.contains(extensionOf(pathOrUrl));

  static bool isSubtitleFile(String pathOrUrl) =>
      AppConstants.subtitleExtensions.contains(extensionOf(pathOrUrl));

  static bool isPlaylistExportFile(String pathOrUrl) =>
      extensionOf(pathOrUrl) == 'json';

  /// Keeps only printable characters; used for titles.
  static String cleanTitle(String raw) {
    final t = raw.replaceAll(RegExp(r'[\x00-\x1f]'), ' ').trim();
    return t.isEmpty ? 'video' : t;
  }

  /// Derives a human title from a URL file name.
  static String titleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return uri.host;
      final file = Uri.decodeComponent(segments.last);
      var name = extensionOf(file).isNotEmpty
          ? file.substring(0, file.length - extensionOf(file).length - 1)
          : file;
      name = name.replaceAll('_', ' ').replaceAll('%20', ' ').trim();
      return cleanTitle(name.isEmpty ? uri.host : name);
    } catch (_) {
      return 'video';
    }
  }
}
