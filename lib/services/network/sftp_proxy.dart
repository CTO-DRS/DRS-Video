import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

/// Pure parser for an HTTP Range header against a known content length.
///
/// Handles `bytes=a-b`, `bytes=a-` and suffix `bytes=-n`; clamps the end to
/// `contentLength - 1`. Returns null when the header is absent/malformed or
/// unsatisfiable (caller answers 416).
({int start, int end})? parseHttpRange(String? header, int contentLength) {
  if (header == null || contentLength <= 0) return null;
  final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (m == null) return null;
  final a = m.group(1)!;
  final b = m.group(2)!;
  if (a.isEmpty && b.isEmpty) return null;

  if (a.isEmpty) {
    // Suffix range: last N bytes.
    final n = int.parse(b);
    if (n <= 0) return null;
    final len = min(n, contentLength);
    return (start: contentLength - len, end: contentLength - 1);
  }

  final start = int.parse(a);
  if (start >= contentLength) return null; // unsatisfiable
  if (b.isEmpty) return (start: start, end: contentLength - 1);
  final end = int.parse(b);
  if (end < start) return null;
  return (start: start, end: min(end, contentLength - 1));
}

/// A file registered for streaming through the local proxy.
class _StreamTarget {
  _StreamTarget({
    required this.openFile,
    required this.fileSize,
  });

  /// Opens a fresh remote file handle per request so concurrent Range
  /// requests never share one sequential cursor.
  final Future<SftpFile> Function() openFile;
  final int fileSize;
}

/// Local HTTP server that bridges mpv's HTTP Range requests to SFTP offset
/// reads.
///
/// Why: mpv has no SFTP credential mechanism of its own, so playback goes
/// through `http://127.0.0.1:<port>/stream/<token>/<fileId>` while real
/// bytes are pulled from the NAS via dartssh2 pipelined reads. Binds to
/// loopback only; every URL carries a per-session random token.
class SftpStreamProxy {
  HttpServer? _server;
  String _token = '';
  final Map<String, _StreamTarget> _targets = {};
  int _counter = 0;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;

  /// Starts the loopback server (idempotent).
  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _token = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        _server!.port.toRadixString(36);
    unawaited(_serve());
    AppLogger.instance.info('sftp-proxy', 'listening on 127.0.0.1:$port');
  }

  /// Registers a remote file and returns its local playback URL.
  Future<String> serveFile({
    required SftpClient sftp,
    required String remotePath,
    required int fileSize,
  }) async {
    await start();
    final id = 'f${_counter++}';
    _targets[id] = _StreamTarget(
      openFile: () => sftp.open(remotePath),
      fileSize: fileSize,
    );
    return 'http://127.0.0.1:$port/stream/$_token/$id';
  }

  /// Drops registered targets (called when playback ends or server changes).
  void clearTargets() => _targets.clear();

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _targets.clear();
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      // Handle each request defensively: one bad request must never take
      // the proxy (or the app) down.
      try {
        await _handle(request);
      } catch (e, s) {
        AppLogger.instance.warning('sftp-proxy', 'request failed: $e / $s');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {
          // Response already gone — nothing more to do.
        }
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final parts = request.uri.pathSegments;
    final okShape = parts.length == 3 &&
        parts[0] == 'stream' &&
        parts[1] == _token &&
        _targets.containsKey(parts[2]);
    if (!okShape) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final target = _targets[parts[2]]!;
    final size = target.fileSize;
    final range = parseHttpRange(
        request.headers.value(HttpHeaders.rangeHeader), size);

    if (request.method == 'HEAD') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentLengthHeader, size);
      await request.response.close();
      return;
    }

    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    if (request.headers.value(HttpHeaders.rangeHeader) != null && range == null) {
      request.response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
      await request.response.close();
      return;
    }

    final start = range?.start ?? 0;
    final end = range?.end ?? size - 1;
    final length = end - start + 1;

    request.response.statusCode =
        range != null ? HttpStatus.partialContent : HttpStatus.ok;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.set(HttpHeaders.contentTypeHeader,
        'application/octet-stream');
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/$size',
    );
    request.response.contentLength = length;

    SftpFile? file;
    try {
      file = await target.openFile();
      await file.downloadTo(
        request.response,
        length: length,
        offset: start,
        chunkSize: AppConstants.streamChunkBytes,
      );
      await request.response.close();
    } catch (e, s) {
      AppLogger.instance.warning('sftp-proxy', 'stream aborted: $e / $s');
      try {
        await request.response.close();
      } catch (_) {}
    } finally {
      try {
        await file?.close();
      } catch (_) {}
    }
  }
}
