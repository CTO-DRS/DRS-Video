import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';

/// A free public OpenVPN server from the VPNGate project
/// (https://www.vpngate.net — University of Tsukuba, public service,
/// no registration required). Configs ship inside the CSV itself.
class VpngateServer {
  VpngateServer({
    required this.hostName,
    required this.ip,
    required this.score,
    required this.ping,
    required this.speedBps,
    required this.countryLong,
    required this.countryCode,
    required this.sessions,
    required this.tcpPort,
    required this.udpPort,
    required this.configBase64,
  });

  final String hostName;
  final String ip;
  final int score;
  final int ping;
  final int speedBps;
  final String countryLong;
  final String countryCode;
  final int sessions;
  final int tcpPort;
  final int udpPort;

  /// Base64 OpenVPN config (includes the CA block and remote line).
  final String configBase64;

  /// Decoded .ovpn config text (null when the row is malformed).
  String? get config {
    try {
      final cleaned = configBase64.trim().replaceAll('\n', '');
      final decoded = utf8.decode(base64.decode(cleaned));
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return null;
    }
  }

  bool get hasConfig => config != null;

  static VpngateServer? fromRow(List<String> row) {
    // CSV columns (vpngate /api/iphone/):
    // 0 #HostName, 1 IP, 2 Score, 3 Ping, 4 Speed, 5 CountryLong,
    // 6 ShortName(code), 7 #VPNSessions, 8 Udp, 9 Tcp,
    // 10-... logs/descriptions, OpenVPN_ConfigData_Base64 is LAST.
    if (row.length < 10) return null;
    int? parseInt(String? s) => int.tryParse((s ?? '').trim());
    final speed = parseInt(row[4]) ?? 0;
    final config = row.length > 10 ? row.last : '';
    if (config.trim().isEmpty) return null;
    return VpngateServer(
      hostName: (row[0]).trim(),
      ip: (row[1]).trim(),
      score: parseInt(row[2]) ?? 0,
      ping: parseInt(row[3]) ?? 0,
      speedBps: speed,
      countryLong: (row[5]).trim(),
      countryCode: (row[6]).trim(),
      sessions: parseInt(row[7]) ?? 0,
      udpPort: parseInt(row[8]) ?? 0,
      tcpPort: parseInt(row[9]) ?? 443,
      configBase64: config.trim(),
    );
  }
}

/// Pure CSV parser (testable without network). Returns servers that
/// carry a usable OpenVPN config, sorted by score (best first).
List<VpngateServer> parseVpngateCsv(String body, {int? minSpeedBps}) {
  final lines =
      body.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  // File starts with a # comment line, then a header row starting with '#'.
  final dataRows = lines
      .where((l) => !l.startsWith('#'))
      .map((l) => _splitCsvLine(l))
      .where((r) => r.length >= 11)
      .toList();
  final servers = <VpngateServer>[];
  for (final row in dataRows) {
    final s = VpngateServer.fromRow(row);
    if (s == null || !s.hasConfig) continue;
    if (minSpeedBps != null && s.speedBps < minSpeedBps) continue;
    servers.add(s);
  }
  servers.sort((a, b) => b.score.compareTo(a.score));
  return servers;
}

/// Minimal CSV splitter: VPNGate rows are simple comma-separated values
/// without quoted fields, but be defensive about stray commas in the
/// trailing base64 config (base64 never contains commas, so a plain
/// split is safe — kept explicit for clarity).
List<String> _splitCsvLine(String line) => line.split(',');

/// Fetches + caches the free server list. Network errors map to typed
/// [AppException] so the UI can show an honest retry state.
class VpngateService {
  VpngateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  List<VpngateServer>? _cache;
  DateTime? _fetchedAt;

  static const _cacheTtl = Duration(minutes: 30);

  bool get hasFreshCache =>
      _cache != null &&
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!) < _cacheTtl;

  /// Cached list (possibly stale) — used for instant UI.
  List<VpngateServer> get cached => _cache ?? const [];

  Future<List<VpngateServer>> fetch({bool force = false}) async {
    if (!force && hasFreshCache) return _cache!;
    try {
      final res = await _dio.get<String>(
        AppConstants.vpngateApiUrl,
        options: Options(
          sendTimeout: AppConstants.vpngateFetchTimeout,
          receiveTimeout: AppConstants.vpngateFetchTimeout,
          responseType: ResponseType.plain,
        ),
      );
      final body = res.data ?? '';
      if (body.isEmpty) {
        throw const AppException(AppErrorType.network);
      }
      final servers = parseVpngateCsv(body);
      _cache = servers;
      _fetchedAt = DateTime.now();
      AppLogger.instance
          .info('vpngate', 'fetched ${servers.length} free servers');
      return servers;
    } on DioException catch (e) {
      AppLogger.instance.warning('vpngate', 'fetch failed: ${e.message}');
      throw AppException(AppErrorType.network, detail: e.message);
    }
  }
}
