import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../smart/intel_v2.dart' show VersionCompare;

/// A GitHub release asset relevant to the updater.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, required this.sizeBytes});

  factory ReleaseAsset.fromMap(Map<Object?, Object?> m) => ReleaseAsset(
        name: (m['name'] as String?) ?? '',
        url: (m['browser_download_url'] as String?) ?? '',
        sizeBytes: (m['size'] as num?)?.toInt() ?? 0,
      );

  final String name;
  final String url;
  final int sizeBytes;

  bool get isApk => name.toLowerCase().endsWith('.apk');
  bool get isMd5 => name.toLowerCase().endsWith('.apk.md5');
}

/// A GitHub release (subset of fields the app uses).
class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAtMs,
    required this.prerelease,
    required this.assets,
  });

  factory GitHubRelease.fromMap(Map<Object?, Object?> m) {
    final assetsRaw = (m['assets'] as List?) ?? const [];
    final published = (m['published_at'] as String?);
    final ms = published == null
        ? 0
        : DateTime.tryParse(published)?.millisecondsSinceEpoch ?? 0;
    return GitHubRelease(
      tagName: (m['tag_name'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      body: (m['body'] as String?) ?? '',
      publishedAtMs: ms,
      prerelease: (m['prerelease'] as bool?) ?? false,
      assets: assetsRaw
          .whereType<Map>()
          .map(ReleaseAsset.fromMap)
          .where((a) => a.url.isNotEmpty)
          .toList(),
    );
  }

  final String tagName;
  final String name;
  final String body;
  final int publishedAtMs;
  final bool prerelease;
  final List<ReleaseAsset> assets;

  ReleaseAsset? get apkAsset =>
      assets.where((a) => a.isApk && !a.name.contains('split')).isEmpty
          ? null
          : assets.where((a) => a.isApk && !a.name.contains('split')).first;
  ReleaseAsset? get md5Asset => assets.where((a) => a.isMd5).isEmpty
      ? null
      : assets.where((a) => a.isMd5).first;
}

/// In-app self-update over GitHub Releases (v1.12.0).
///
/// Flow: [checkForUpdate] compares the latest non-draft release tag with
/// the running version → [downloadApk] streams the APK asset into the
/// app cache (with progress + optional md5 verification against the
/// sibling `.md5` asset) → the UI hands the file to the native installer
/// (NativeChannel.installApk). Check paths never throw; download errors
/// are surfaced as [UpdateException] for honest UI messaging.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const repo = AppConstants.githubRepo;

  Dio? _dio;
  Dio get _http => _dio ??= Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
        headers: {'Accept': 'application/vnd.github+json'},
      ));

  /// Release list (newest first). Offline/API errors → empty list.
  Future<List<GitHubRelease>> fetchReleases({int limit = 10}) async {
    try {
      final res = await _http.get<List<dynamic>>(
        'https://api.github.com/repos/$repo/releases?per_page=$limit',
      );
      return res.data
              ?.whereType<Map>()
              .map(GitHubRelease.fromMap)
              .where((r) => r.tagName.isNotEmpty)
              .toList() ??
          const [];
    } catch (e, s) {
      AppLogger.instance.error('update', 'fetchReleases failed: $e', e, s);
      return const [];
    }
  }

  /// The newest release whose APK is installable over the running version.
  /// null when up-to-date, offline, or no APK asset.
  Future<GitHubRelease?> checkForUpdate({
    String currentVersion = AppConstants.appVersion,
  }) async {
    final releases = await fetchReleases(limit: 5);
    for (final r in releases) {
      if (r.apkAsset == null) continue;
      if (VersionCompare.isNewer(r.tagName, currentVersion)) return r;
    }
    return null;
  }

  /// Directory where update APKs are staged (cache/update).
  Future<Directory> _stagingDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/update');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Streams the APK asset to cache and (when a sibling .md5 asset
  /// exists) verifies the digest. Returns the staged file path.
  /// Throws [UpdateException] on network/digest failures.
  Future<String> downloadApk(
    GitHubRelease release, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final apk = release.apkAsset;
    if (apk == null) {
      throw const UpdateException('release has no APK asset');
    }
    final dir = await _stagingDir();
    final target = File('${dir.path}/DRS-Video-${release.tagName}.apk');
    try {
      await _http.download(
        apk.url,
        target.path,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const UpdateException('cancelled');
      throw UpdateException('download failed: ${e.message ?? e.type.name}');
    } catch (e) {
      throw UpdateException('download failed: $e');
    }

    // Optional integrity check against the published .md5 asset.
    final md5Asset = release.md5Asset;
    if (md5Asset != null) {
      try {
        final res = await _http.get<String>(md5Asset.url);
        final expected =
            RegExp(r'([a-fA-F0-9]{32})').firstMatch(res.data ?? '')?.group(1);
        if (expected != null) {
          final actual = md5Hex(target.readAsBytesSync());
          if (actual != expected.toLowerCase()) {
            try {
              target.deleteSync();
            } catch (_) {}
            throw const UpdateException('md5 mismatch — file deleted');
          }
          AppLogger.instance.info('update', 'md5 verified: $actual');
        }
      } on UpdateException {
        rethrow;
      } catch (e) {
        // Digest asset unreachable — the download itself succeeded; the
        // system installer will still refuse a genuinely broken APK.
        AppLogger.instance.warning('update', 'md5 asset check skipped: $e');
      }
    }
    return target.path;
  }

  /// Deletes staged APKs (after successful install or user cancel).
  Future<void> clearStaged() async {
    try {
      final dir = await _stagingDir();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// MD5 (RFC 1321) over raw bytes — pure, deterministic, and covered by
/// unit tests against published vectors, so update integrity checks do
/// not depend on any third-party crypto package.
String md5Hex(List<int> message) => _MD5().process(message);

class _MD5 {
  static const _s = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  static const _k = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
    0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340,
    0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
    0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
    0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
    0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];

  int _a = 0x67452301, _b = 0xefcdab89, _c = 0x98badcfe, _d = 0x10325476;

  String process(List<int> msg) {
    final bitLen = msg.length * 8;
    final data = List<int>.of(msg)
      ..add(0x80)
      ..addAll(List.filled((56 - (msg.length + 1) % 64) % 64, 0));
    for (var i = 0; i < 8; i++) {
      data.add((bitLen >> (8 * i)) & 0xff);
    }

    for (var chunk = 0; chunk < data.length; chunk += 64) {
      final m = List<int>.filled(16, 0);
      for (var j = 0; j < 16; j++) {
        m[j] = data[chunk + j * 4] |
            (data[chunk + j * 4 + 1] << 8) |
            (data[chunk + j * 4 + 2] << 16) |
            (data[chunk + j * 4 + 3] << 24);
      }
      var a = _a, b = _b, c = _c, d = _d;
      for (var i = 0; i < 64; i++) {
        int f, g;
        if (i < 16) {
          f = (b & c) | (~b & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | (~d & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | ~d);
          g = (7 * i) % 16;
        }
        f = (f + a + _k[i] + m[g]) & 0xffffffff;
        a = d;
        d = c;
        c = b;
        b = (b + ((f << _s[i]) | (f >> (32 - _s[i])))) & 0xffffffff;
      }
      _a = (_a + a) & 0xffffffff;
      _b = (_b + b) & 0xffffffff;
      _c = (_c + c) & 0xffffffff;
      _d = (_d + d) & 0xffffffff;
    }

    String le(int v) => List.generate(
        4, (i) => ((v >> (8 * i)) & 0xff).toRadixString(16).padLeft(2, '0'))
        .join();
    return le(_a) + le(_b) + le(_c) + le(_d);
  }
}
