import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/services/smart/intel_v2.dart' show VersionCompare;
import 'package:drs_video/services/update/update_service.dart';

/// v1.14.5 regression guards for the endless-update-prompt bug.
///
/// Real incident: release v1.14.4 shipped while [AppConstants.appVersion]
/// still said '1.14.3'. Every freshly-installed build compared itself
/// against the latest GitHub tag and concluded "update available" —
/// forever, even after installing that very release from GitHub.
void main() {
  group('v1.14.5 version-guard (endless update prompt)', () {
    test('AppConstants.appVersion mirrors pubspec.yaml', () {
      // flutter test runs from the package root, so pubspec.yaml is cwd.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(m, isNotNull,
          reason: 'pubspec.yaml must declare version: x.y.z+N');
      expect(AppConstants.appVersion, m!.group(1),
          reason: 'AppConstants.appVersion drifted from pubspec version. '
              'This exact drift caused the app to prompt an update to the '
              'release the user was already running. Bump BOTH (or rely on '
              'UpdateService.runningVersion which reads live PackageInfo).');
    });

    test('runningVersion() never throws and returns a non-empty version',
        () async {
      final v = await UpdateService.runningVersion();
      expect(v, isNotEmpty);
      expect(RegExp(r'^\d+\.\d+\.\d+').hasMatch(v), isTrue,
          reason: 'version must look like x.y.z…, got "$v"');
    });

    test('no self-update prompt: tag == running version is never "newer"',
        () {
      // The incident, replayed: release tag v1.14.5 vs running 1.14.5.
      expect(VersionCompare.isNewer('v1.14.5', '1.14.5'), isFalse);
      // And the drifted state that caused the bug: v1.14.4 tag vs the
      // stale '1.14.3' constant WAS newer — documented, not desired.
      expect(VersionCompare.isNewer('v1.14.4', '1.14.3'), isTrue);
      // Downgrade / same-version releases must not prompt either.
      expect(VersionCompare.isNewer('v1.14.4', '1.14.5'), isFalse);
      expect(VersionCompare.isNewer('v1.14.5+27', '1.14.5'), isFalse);
    });
  });
}
