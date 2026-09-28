import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../smart/intel_v2.dart' show VersionCompare;
import '../../core/utils/md5.dart';
export '../../core/utils/md5.dart';

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

  /// The version the app is REALLY running, read from the platform
  /// package metadata (pubspec version baked at build time).
  ///
  /// v1.14.5 fix — the endless-update-prompt bug: comparison used to be
  /// fed the hand-maintained [AppConstants.appVersion] constant, which
  /// drifted (stayed '1.14.3' while release v1.14.4 shipped). The app
  /// then asked to update to the very release the user was running.
  /// Reading the live PackageInfo makes that drift impossible; the
  /// constant remains only as a last-resort fallback.
  static Future<String> runningVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (p.version.isNotEmpty) return p.version;
    } catch (_) {
      // Plugin unavailable (rare, e.g. unit-test env) — fall through.
    }
    return AppConstants.appVersion;
  }

  /// The newest release whose APK is installable over the running version.
  /// null when up-to-date, offline, or no APK asset.
  Future<GitHubRelease?> checkForUpdate({
    String? currentVersion,
  }) async {
    final current = currentVersion ?? await runningVersion();
    final releases = await fetchReleases(limit: 5);
    for (final r in releases) {
      if (r.apkAsset == null) continue;
      if (VersionCompare.isNewer(r.tagName, current)) return r;
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


