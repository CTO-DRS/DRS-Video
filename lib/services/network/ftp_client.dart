import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../data/models/stream_models.dart';

/// One FTP directory entry produced by the pure parsers below.
class FtpEntry {
  const FtpEntry({
    required this.name,
    required this.isDir,
    this.sizeBytes,
    this.modifiedAt,
  });

  final String name;
  final bool isDir;
  final int? sizeBytes;
  final DateTime? modifiedAt;
}

/// Parses a PASV reply like "227 Entering Passive Mode (192,168,1,5,10,24)".
({String host, int port})? parsePasv(String reply) {
  final m = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)').firstMatch(reply);
  if (m == null) return null;
  final host = [1, 2, 3, 4].map((i) => m.group(i)!).join('.');
  final port = int.parse(m.group(5)!) * 256 + int.parse(m.group(6)!);
  if (port <= 0 || port > 65535) return null;
  return (host: host, port: port);
}

/// Parses one MLSD fact line:
/// "type=dir;size=0;modify=20240101120000; subdir name".
/// Returns null for ./. .. and control entries.
FtpEntry? parseMlsdLine(String line) {
  final semi = line.lastIndexOf(';');
  if (semi < 0) return null;
  final factPart = line.substring(0, semi + 1);
  final name = line.substring(semi + 1).trim();
  if (name.isEmpty || name == '.' || name == '..') return null;

  String? type;
  int? size;
  DateTime? modified;
  for (final raw in factPart.split(';')) {
    final f = raw.trim();
    final eq = f.indexOf('=');
    if (eq <= 0) continue;
    final key = f.substring(0, eq).toLowerCase();
    final value = f.substring(eq + 1);
    switch (key) {
      case 'type':
        type = value.toLowerCase();
      case 'size':
        size = int.tryParse(value);
      case 'modify':
        if (value.length >= 14) {
          final y = int.tryParse(value.substring(0, 4));
          final mo = int.tryParse(value.substring(4, 6));
          final d = int.tryParse(value.substring(6, 8));
          final h = int.tryParse(value.substring(8, 10));
          final mi = int.tryParse(value.substring(10, 12));
          final s = int.tryParse(value.substring(12, 14));
          if (y != null && mo != null && d != null) {
            modified = DateTime.utc(y, mo, d, h ?? 0, mi ?? 0, s ?? 0);
          }
        }
    }
  }

  if (type == 'cdir' || type == 'pdir') return null;
  final isDir = type == 'dir';
  return FtpEntry(
    name: name,
    isDir: isDir,
    sizeBytes: isDir ? null : size,
    modifiedAt: modified,
  );
}

/// Parses one UNIX "ls -l" line:
/// "drwxr-xr-x 2 owner group 4096 Jan 1 12:00 file name".
/// Returns null for . / .. / malformed lines.
FtpEntry? parseUnixListLine(String line) {
  final parts = line.trim().split(RegExp(r'\s+'));
  if (parts.length < 9) return null;
  final perms = parts[0];
  if (perms.length < 10) return null;
  final isDir = perms.startsWith('d');
  // Columns: perms=0 links=1 owner=2 group=3 size=4 date(3) name(8+).
  final size = int.tryParse(parts[4]);
  final name = parts.sublist(8).join(' ');
  if (name.isEmpty || name == '.' || name == '..') return null;
  return FtpEntry(name: name, isDir: isDir, sizeBytes: size);
}

/// Builds an ftp:// URL for mpv/FFmpeg playback. Credentials are embedded by
/// the caller (per-session playUri), never persisted.
String buildFtpUrl({
  required String host,
  required int port,
  required String path,
  String? username,
  String? password,
}) {
  final portPart = port == AppConstants.ftpDefaultPort ? '' : ':$port';
  final p = path.startsWith('/') ? path : '/$path';
  final cred = (username != null && username.isNotEmpty)
      ? '${Uri.encodeComponent(username)}'
          '${password != null && password.isNotEmpty ? ':${Uri.encodeComponent(password)}' : ''}@'
      : '';
  return 'ftp://$cred$host$portPart$p';
}

/// Minimal read-only FTP client used ONLY for directory browsing.
///
/// Supports the classic command subset needed to list directories:
/// USER/PASS, TYPE I, PASV, CWD, MLSD (with LIST fallback) and QUIT.
/// Media playback does NOT go through this client — mpv/FFmpeg plays the
/// native ftp:// URL directly.
class MinimalFtpClient {
  MinimalFtpClient({
    this.connectTimeout = AppConstants.nasConnectTimeout,
  });

  final Duration connectTimeout;

  Socket? _socket;
  StreamIterator<String>? _lines;
  bool _closed = false;

  Future<void> connect({
    required String host,
    required int port,
    String? username,
    String? password,
  }) async {
    _socket = await Socket.connect(host, port, timeout: connectTimeout);
    _lines = StreamIterator(
      _socket!.cast<List<int>>().transform(utf8.decoder).transform(
            const LineSplitter(),
          ),
    );
    final greeting = await _readReply();
    if (!greeting.startsWith('220')) {
      await quit();
      throw const FtpException('unexpected FTP greeting');
    }
    final user = await _command('USER ${username ?? 'anonymous'}');
    if (user.startsWith('331')) {
      final pass =
          await _command('PASS ${password ?? 'guest@example.com'}');
      if (!pass.startsWith('230') && !pass.startsWith('202')) {
        await quit();
        throw const FtpAuthException();
      }
    } else if (!user.startsWith('230') && !user.startsWith('202')) {
      await quit();
      throw const FtpAuthException();
    }
    final type = await _command('TYPE I');
    if (!type.startsWith('200')) {
      AppLogger.instance.warning('ftp', 'TYPE I rejected: $type');
    }
  }

  /// Lists [path]. Tries MLSD (machine readable) and falls back to LIST.
  Future<List<NasEntry>> list(String path) async {
    final pasvReply = await _command('PASV');
    if (!pasvReply.startsWith('227')) {
      throw FtpException('passive mode rejected: $pasvReply');
    }
    final pasv = parsePasv(pasvReply);
    if (pasv == null) throw const FtpException('bad PASV reply');

    final data = await Socket.connect(pasv.host, pasv.port,
        timeout: connectTimeout);

    var reply = await _command('MLSD $path');
    var useMlsd = !reply.startsWith('5');
    if (!useMlsd) {
      reply = await _command('LIST $path');
      if (!reply.startsWith('1')) {
        data.destroy();
        throw FtpException('listing rejected: $reply');
      }
    } else if (!reply.startsWith('1')) {
      data.destroy();
      throw FtpException('MLSD transfer not started: $reply');
    }

    final buffer = StringBuffer();
    final completer = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = data.listen(
      (chunk) => buffer.write(utf8.decode(chunk, allowMalformed: true)),
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    await completer.future.timeout(connectTimeout * 2);
    await sub.cancel();
    data.destroy();

    final transfer = await _readReply(); // 226 closing data connection
    if (!transfer.startsWith('226') && !transfer.startsWith('250')) {
      AppLogger.instance.warning('ftp', 'transfer reply: $transfer');
    }

    final text = buffer.toString().replaceAll('\r\n', '\n');
    final entries = <NasEntry>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parsed = useMlsd
          ? _toNasEntry(parseMlsdLine(line))
          : _toNasEntry(parseUnixListLine(line));
      if (parsed != null) entries.add(parsed);
    }
    return entries;
  }

  NasEntry? _toNasEntry(FtpEntry? e) {
    if (e == null) return null;
    return NasEntry(
      name: e.name,
      path: e.name,
      isDir: e.isDir,
      sizeBytes: e.sizeBytes,
      modifiedAt: e.modifiedAt,
    );
  }

  Future<void> quit() async {
    if (_closed) return;
    _closed = true;
    try {
      _socket?.writeln('QUIT');
      await _socket?.flush();
      await _socket?.close();
    } catch (_) {
      // Best effort — the socket is being discarded anyway.
    }
    _socket?.destroy();
    _socket = null;
    _lines = null;
  }

  Future<String> _command(String cmd) async {
    _socket!.writeln(cmd);
    await _socket!.flush();
    return _readReply();
  }

  /// Reads a (possibly multi-line) FTP reply, e.g.
  /// "220-Welcome\r\n220 ready" or "200 OK".
  Future<String> _readReply() async {
    final lines = _lines!;
    final buffer = StringBuffer();
    while (true) {
      final hasLine = await lines.moveNext().timeout(connectTimeout);
      if (!hasLine) {
        throw const FtpException('connection closed by server');
      }
      final line = lines.current;
      buffer.writeln(line);
      // Final line of a reply: 3 digits followed by a space (or alone).
      if (RegExp(r'^\d{3}( |$)').hasMatch(line)) break;
    }
    return buffer.toString().trim();
  }
}

class FtpException implements Exception {
  const FtpException(this.message);
  final String message;
  @override
  String toString() => 'FtpException: $message';
}

class FtpAuthException extends FtpException {
  const FtpAuthException() : super('FTP authentication failed');
}
