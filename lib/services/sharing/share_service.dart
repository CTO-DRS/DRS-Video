import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/playlist.dart';

/// Sharing and "open with" integrations (all via system intents).
class ShareService {
  const ShareService();

  Future<void> shareLink(String url) => Share.share(url);

  Future<void> copyLink(String url) =>
      Clipboard.setData(ClipboardData(text: url));

  Future<void> shareFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    await Share.shareXFiles([XFile(path)]);
  }

  Future<void> openWith(String path) => OpenFilex.open(path);

  /// Exports a playlist as a JSON string for the share sheet / file save.
  String exportPlaylistJson(PlaylistWithItems pl) {
    final payload = {
      'format': 'drs-playlist',
      'version': 1,
      'name': pl.playlist.name,
      'exportedAt': DateTime.now().toIso8601String(),
      'items': [
        for (final m in pl.items)
          {'title': m.title, 'uri': m.uri, 'type': m.type.name},
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Imports a playlist from JSON. Returns (name, items) or throws FormatException.
  (String, List<({String title, String uri, String type})>) importPlaylistJson(
      String raw) {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['format'] != 'drs-playlist' ||
        data['items'] is! List) {
      throw const FormatException('not a drs playlist');
    }
    final name = (data['name'] as String?) ?? 'playlist';
    final items = <({String title, String uri, String type})>[];
    for (final e in data['items'] as List) {
      if (e is! Map<String, dynamic>) continue;
      final uri = e['uri'] as String?;
      if (uri == null || uri.isEmpty) continue;
      items.add((
        title: (e['title'] as String?) ?? uri,
        uri: uri,
        type: (e['type'] as String?) ?? 'network',
      ));
    }
    if (items.isEmpty) throw const FormatException('empty playlist');
    return (name, items);
  }

  /// Picks a previously exported playlist JSON file.
  Future<String?> pickPlaylistJson() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConstants.playlistExportExtension,
    );
    final path = res?.files.single.path;
    if (path == null) return null;
    return File(path).readAsString();
  }

  /// Picks a video file for local playback.
  Future<String?> pickVideo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    return res?.files.single.path;
  }

  /// Picks an external subtitle file (SRT / VTT).
  Future<String?> pickSubtitle() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConstants.subtitleExtensions,
    );
    return res?.files.single.path;
  }

  /// Picks a folder (used for a custom download directory).
  Future<String?> pickDirectory() => FilePicker.platform.getDirectoryPath();
}
