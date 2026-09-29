import 'package:dio/dio.dart';

import '../utils/logger.dart';

/// P3 — the one place that decides how plain-HTTP (cleartext) traffic is
/// treated, so every layer behaves identically instead of relying on
/// silent Android defaults.
///
/// Why a media app cannot just block cleartext: users add their OWN
/// sources — LAN NAS over WebDAV/HTTP, IPTV provider playlists, direct
/// video links — and many are legitimately plain HTTP (home LAN, older
/// providers). Blocking outright would break real, working setups.
/// Silently allowing it everywhere would, on the other hand, let the
/// app's own update/resolver APIs downgrade unnoticed (a hostile playlist
/// could even redirect the updater). So the policy is split:
///
///   * [appControlledHosts] — hosts the app itself calls (self-update,
///     VPN list, resolvers, subtitle translation). Cleartext to these is
///     a bug: [CleartextGuardInterceptor] rejects the request loudly in
///     every Dio instance, and network_security_config.xml blocks it in
///     the native stack too (defense in depth).
///
///   * everything else (user sources) — allowed, and the UI surfaces an
///     "unencrypted connection" disclosure when the user saves such a
///     source via [isInsecureUrl].
///
/// Keep in sync with android/app/src/main/res/xml/network_security_config.xml
/// (parity is guarded by test/p3_network_policy_test.dart).
abstract final class CleartextPolicy {
  /// Hosts the app calls for its own functionality — never user-typed
  /// media sources. Subdomains included (matches the XML domain-config).
  static const Set<String> appControlledHosts = {
    'api.github.com',
    'objects.githubusercontent.com',
    'vpngate.net',
    'tikwm.com',
    'api.fxtwitter.com',
    'cdn.syndication.twimg.com',
    'translate.googleapis.com',
  };

  /// True when [host] is an app-controlled endpoint. Case-insensitive,
  /// tolerates a fully-qualified trailing dot.
  static bool isAppControlledHost(String host) {
    var h = host.trim().toLowerCase();
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    for (final base in appControlledHosts) {
      if (h == base) return true;
      if (h.endsWith('.$base')) return true;
    }
    return false;
  }

  /// True when a request to [uri] must be rejected because it would send
  /// app-controlled traffic (update check, resolver API, ...) over an
  /// unencrypted channel.
  static bool mustReject(Uri uri) =>
      uri.scheme == 'http' && isAppControlledHost(uri.host);

  /// True when [url] is an http:// URL that would travel unencrypted.
  ///
  /// Loopback never counts — the SFTP proxy streams over a local
  /// 127.0.0.1 socket that never leaves the device (P3 keeps that
  /// working without nagging the user).
  static bool isInsecureUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    final loopback =
        host == 'localhost' || host.startsWith('127.') || host == '::1';
    return !loopback;
  }
}

/// Dio interceptor that fails any cleartext request to an app-controlled
/// host BEFORE a socket is opened. Wired into [DioClient] and the updater
/// so a refactor or hostile redirect can never silently downgrade the
/// app's own API traffic to HTTP.
class CleartextGuardInterceptor extends Interceptor {
  const CleartextGuardInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (CleartextPolicy.mustReject(options.uri)) {
      AppLogger.instance.warning(
        'security',
        'blocked cleartext request to app-controlled host: ${options.uri}',
      );
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badCertificate,
        error: CleartextViolationException(options.uri.toString()),
      ));
      return;
    }
    handler.next(options);
  }
}

/// The request would have sent app-controlled traffic over plain HTTP.
class CleartextViolationException implements Exception {
  const CleartextViolationException(this.url);
  final String url;

  @override
  String toString() =>
      'CleartextViolationException: $url must use https (app-controlled host)';
}
