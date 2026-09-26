import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drs_video/core/constants/app_constants.dart';
import 'package:drs_video/core/storage/preferences_service.dart';
import 'package:drs_video/core/theme/theme_controller.dart';
import 'package:drs_video/services/player/sleep_timer.dart';
import 'package:drs_video/widgets/common/empty_state.dart';
import 'package:drs_video/widgets/common/offline_banner.dart';
import 'package:drs_video/widgets/common/stat_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController persistence', () {
    test('defaults and round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService(await SharedPreferences.getInstance());

      final theme = ThemeController(prefs.raw);
      expect(theme.mode, ThemeModeSetting.system);
      expect(theme.dynamicColor, isTrue);
      expect(theme.materialMode, ThemeMode.system);
      expect(theme.localeOverride, isNull);

      theme.setMode(ThemeModeSetting.dark);
      theme.setLanguage(LanguageSetting.arabic);
      expect(theme.materialMode, ThemeMode.dark);
      expect(theme.localeOverride, const Locale('ar'));

      // New instance reads persisted values.
      final prefs2 = PreferencesService(await SharedPreferences.getInstance());
      final theme2 = ThemeController(prefs2.raw);
      expect(theme2.mode, ThemeModeSetting.dark);
      expect(theme2.language, LanguageSetting.arabic);
    });
  });

  group('PreferencesService', () {
    test('settings round-trip with clamping', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService(await SharedPreferences.getInstance());

      expect(prefs.autoPlayNext, isTrue);
      expect(prefs.defaultSpeed, 1.0);
      expect(prefs.maxConcurrentDownloads, AppConstants.defaultMaxConcurrentDownloads);

      prefs.autoPlayNext = false;
      prefs.alwaysResume = true;
      prefs.wifiOnlyDownloads = true;
      prefs.maxConcurrentDownloads = 99; // clamped to hard max
      prefs.defaultSpeed = 1.5;

      final restored = PreferencesService(await SharedPreferences.getInstance());
      expect(restored.autoPlayNext, isFalse);
      expect(restored.alwaysResume, isTrue);
      expect(restored.wifiOnlyDownloads, isTrue);
      expect(restored.maxConcurrentDownloads, AppConstants.hardMaxConcurrentDownloads);
      expect(restored.defaultSpeed, 1.5);
    });
  });

  group('SleepTimer', () {
    test('fires after the duration and pauses playback', () async {
      var fired = false;
      final timer = SleepTimer(() => fired = true);
      addTearDown(timer.dispose);

      timer.start(const Duration(milliseconds: 100));
      expect(timer.isActive, isTrue);
      await Future.delayed(const Duration(milliseconds: 400));
      expect(fired, isTrue);
      expect(timer.isActive, isFalse);
    });

    test('end-of-video mode consumes once', () {
      var fired = false;
      final timer = SleepTimer(() => fired = true);
      addTearDown(timer.dispose);

      timer.startEndOfVideo();
      expect(timer.isEndOfVideo, isTrue);
      expect(timer.consumeEndOfVideo(), isTrue);
      expect(timer.consumeEndOfVideo(), isFalse);
      expect(fired, isFalse);
    });
  });

  group('Widgets', () {
    Widget wrap(Widget child) => MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar'), Locale('en')],
          home: Scaffold(body: child),
        );

    testWidgets('EmptyState shows title, body and action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(EmptyState(
        icon: Icons.download_outlined,
        title: 'No downloads',
        body: 'Start one now',
        actionLabel: 'Download',
        onAction: () => tapped = true,
      )));

      expect(find.text('No downloads'), findsOneWidget);
      expect(find.text('Start one now'), findsOneWidget);
      await tester.tap(find.text('Download'));
      expect(tapped, isTrue);
    });

    testWidgets('OfflineBanner renders message', (tester) async {
      await tester.pumpWidget(wrap(const OfflineBanner(visible: true)));
      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('StatTile shows value and handles taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(StatTile(
        icon: Icons.play_circle,
        label: 'Downloads',
        value: '12',
        onTap: () => taps++,
      )));
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
      await tester.tap(find.text('Downloads'));
      expect(taps, 1);
    });
  });
}
