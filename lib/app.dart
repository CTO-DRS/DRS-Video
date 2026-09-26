import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/network/connectivity_service.dart';
import 'core/storage/cache_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/crash_store.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/home/home_screen.dart';
import 'features/library/library_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/playlists/playlists_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/boot_screen.dart';
import 'features/splash/splash_screen.dart';
import 'data/repositories/history_repository.dart';
import 'data/repositories/library_repository.dart';
import 'l10n/app_localizations.dart';
import 'services/downloader/download_service.dart';
import 'services/files/file_manager_service.dart';
import 'services/player/player_service.dart';
import 'services/platform/native_channel.dart';
import 'services/sharing/share_service.dart';
import 'services/storage/storage_analyzer.dart';
import 'state/app_providers.dart';
import 'state/downloads_controller.dart';
import 'state/home_controller.dart';
import 'state/library_controller.dart';
import 'state/local_media_controller.dart';
import 'state/media_actions.dart';
import 'state/playlists_controller.dart';
import 'state/search_controller.dart' as search_ctrl;
import 'state/settings_controller.dart';
import 'state/sources_controller.dart';
import 'widgets/common/mini_player.dart';
import 'widgets/common/offline_banner.dart';

/// Root widget: boot gate -> providers + themed MaterialApp + shell.
///
/// Startup is failure-proof: [runApp] happens before any service init, so
/// the user always reaches a real UI. Boot shows a branded screen with
/// live stages; on failure it shows the actual error with Retry and a
/// Safe Mode that skips optional services.
class DrsApp extends StatefulWidget {
  const DrsApp({super.key, this.runBootstrap = bootstrap});

  final BootstrapFn runBootstrap;

  @override
  State<DrsApp> createState() => _DrsAppState();
}

class _DrsAppState extends State<DrsApp> {
  AppServices? _services;
  ThemeController? _theme;
  String? _stage;
  Object? _bootError;
  StackTrace? _bootStack;
  bool _minimal = false;
  bool _slow = false;
  int _attempt = 0;
  Timer? _watchdog;

  /// Crash/error records from the previous session (dart + native), or
  /// null when the last session was clean.
  String? _previousCrash;

  @override
  void initState() {
    super.initState();
    _loadPreviousCrash();
    _launch(minimal: false);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  /// Surfaces the reason of a previous hard kill directly on the boot
  /// screen — the user can see and copy it without any developer tools.
  Future<void> _loadPreviousCrash() async {
    final dart = await CrashStore.instance.readPrevious();
    final native = await NativeChannel.instance.nativeCrashLog();
    if (!mounted) return;
    final combined = <String>[
      if (dart != null && dart.isNotEmpty) 'Dart log:\n$dart',
      if (native != null && native.isNotEmpty) 'Native log:\n$native',
    ].join('\n\n');
    if (combined.isNotEmpty) {
      setState(() => _previousCrash = combined);
    }
  }

  /// A boot that reaches real services is considered healthy: previous
  /// crash records are no longer relevant.
  Future<void> _clearCrashHistory() async {
    await CrashStore.instance.clear();
    await NativeChannel.instance.clearNativeCrashLog();
  }

  Future<void> _launch({required bool minimal}) async {
    _watchdog?.cancel();
    final attempt = ++_attempt;
    setState(() {
      _services = null;
      _theme = null;
      _stage = null;
      _bootError = null;
      _bootStack = null;
      _minimal = minimal;
      _slow = false;
    });

    // Watchdog: first boot can be slow, but never leave the user hanging
    // without options.
    _watchdog = Timer(const Duration(seconds: 20), () {
      if (mounted && _attempt == attempt && _services == null && _bootError == null) {
        setState(() => _slow = true);
      }
    });

    try {
      final services = await widget.runBootstrap(
        minimal: minimal,
        onStage: (s) {
          if (mounted && _attempt == attempt) setState(() => _stage = s);
        },
      );
      if (!mounted || _attempt != attempt) return; // stale attempt
      setState(() {
        _services = services;
        _theme = ThemeController(services.prefs.raw);
      });
      unawaited(_clearCrashHistory());
    } catch (error, stack) {
      if (!mounted || _attempt != attempt) return; // stale attempt
      setState(() {
        _bootError = error;
        _bootStack = stack;
      });
    } finally {
      if (_attempt == attempt) _watchdog?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    final theme = _theme;

    // Boot phase: loading or recoverable error — always a real UI.
    if (services == null || theme == null) {
      return BootMaterialApp(
        stage: _stage,
        slow: _slow,
        minimal: _minimal,
        error: _bootError,
        stack: _bootStack,
        previousCrash: _previousCrash,
        onRetry: () => _launch(minimal: false),
        onSafeMode: () => _launch(minimal: true),
      );
    }

    // Ready phase: the full themed app.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<ConnectivityService>.value(value: services.connectivity),
        ChangeNotifierProvider<PlayerService>.value(value: services.player),
        ChangeNotifierProvider<DownloadService>.value(value: services.downloader),
        Provider<AppServices>.value(value: services),
        Provider<ShareService>.value(value: services.share),
        Provider<LibraryRepository>.value(value: services.library),
        Provider<HistoryRepository>.value(value: services.history),
        Provider<FileManagerService>.value(value: services.fileManager),
        Provider<StorageAnalyzer>.value(value: services.analyzer),
        ChangeNotifierProvider(
          create: (_) => SettingsController(
            prefs: services.prefs,
            db: services.db,
            connectivity: services.connectivity,
          ),
        ),
        ChangeNotifierProvider(create: (_) => MediaActions(
          library: services.library,
          player: services.player,
          registry: services.registry,
        )),
        ChangeNotifierProvider(
          create: (_) => HomeController(
            library: services.library,
            history: services.history,
            playlists: services.playlists,
            downloads: services.downloadsRepo,
            sources: services.sources,
            engine: services.engine,
          ),
        ),
        ChangeNotifierProvider(create: (_) => LibraryController(
          library: services.library,
          history: services.history,
          playlists: services.playlists,
        )),
        ChangeNotifierProvider(create: (_) => PlaylistsController(
          playlists: services.playlists,
          library: services.library,
        )),
        ChangeNotifierProvider(create: (_) => DownloadsController(
          service: services.downloader,
          connectivity: services.connectivity,
        )),
        ChangeNotifierProvider(create: (_) => search_ctrl.LibrarySearchController(
          library: services.library,
          history: services.history,
        )),
        ChangeNotifierProvider(create: (_) => LocalMediaController(
          library: services.library,
          cache: CacheManager.instance,
        )),
        ChangeNotifierProvider(create: (_) => SourcesController(repo: services.sources)),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) => MaterialApp(
            title: 'DRS Video',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(
                _resolveScheme(theme, lightDynamic, Brightness.light)),
            darkTheme: AppTheme.dark(
                _resolveScheme(theme, darkDynamic, Brightness.dark)),
            themeMode: theme.materialMode,
            locale: theme.localeOverride,
            localizationsDelegates: _l10nDelegates,
            localeResolutionCallback: _resolveLocale,
            supportedLocales: _supportedLocales,
            home: FirstRunGate(services: services),
          ),
        ),
      ),
    );
  }
}

const _l10nDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

const _supportedLocales = [Locale('ar'), Locale('en')];

/// v1.1.0 palette resolution: fixed seed -> seeded scheme; otherwise the
/// system dynamic scheme (when available and enabled), else defaults.
ColorScheme? _resolveScheme(
    ThemeController t, ColorScheme? dynamicScheme, Brightness brightness) {
  final seed = t.fixedSeed;
  if (seed != null) {
    return ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  }
  return t.dynamicColor ? dynamicScheme : null;
}

Locale _resolveLocale(Locale? locale, Iterable<Locale> supported) {
  final system = locale?.languageCode ?? 'ar';
  return supported.contains(Locale(system)) ? Locale(system) : const Locale('ar');
}

/// Decides first-run flow: splash -> onboarding -> shell.
class FirstRunGate extends StatefulWidget {
  const FirstRunGate({super.key, required this.services});

  final AppServices services;

  @override
  State<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<FirstRunGate> {
  bool _splashDone = false;
  bool _firstRun = true;

  @override
  void initState() {
    super.initState();
    _firstRun = !widget.services.prefs.firstRunDone;
  }

  void _finishOnboarding() {
    widget.services.prefs.firstRunDone = true;
    setState(() => _firstRun = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return SplashScreen(onDone: () => setState(() => _splashDone = true));
    }
    if (_firstRun) {
      return OnboardingScreen(onFinish: _finishOnboarding);
    }
    return const RootShell();
  }
}

/// Main navigation shell: 5 tabs + mini player + offline banner.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<HomeController>().load();
      context.read<search_ctrl.LibrarySearchController>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final online = context.watch<ConnectivityService>().isOnline;
    final player = context.watch<PlayerService>();

    final pages = [
      const HomeScreen(),
      const LibraryScreen(),
      const PlaylistsScreen(),
      const DownloadsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Column(
        children: [
          OfflineBanner(visible: !online),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (player.hasMedia) const MiniPlayer(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              setState(() => _index = i);
              // Refresh section data when switching tabs.
              if (i == 0) context.read<HomeController>().load();
              if (i == 1) context.read<LibraryController>().load();
              if (i == 2) context.read<PlaylistsController>().load();
              if (i == 3) context.read<DownloadsController>().refresh();
            },
            destinations: [
              NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: l.navHome),
              NavigationDestination(icon: const Icon(Icons.video_library_outlined), selectedIcon: const Icon(Icons.video_library), label: l.navLibrary),
              NavigationDestination(icon: const Icon(Icons.playlist_play), selectedIcon: const Icon(Icons.playlist_add_check), label: l.navPlaylists),
              NavigationDestination(icon: const Icon(Icons.download_outlined), selectedIcon: const Icon(Icons.download), label: l.navDownloads),
              NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: l.navSettings),
            ],
          ),
        ],
      ),
    );
  }
}
