import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/network/connectivity_service.dart';
import 'core/storage/cache_manager.dart';
import 'core/storage/preferences_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/crash_store.dart';
import 'data/repositories/browser_repository.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/home/home_screen.dart';
import 'features/library/library_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/playlists/playlists_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/github_screen.dart';
import 'features/security/lock_screen.dart';
import 'features/splash/boot_screen.dart';
import 'features/splash/splash_screen.dart';
import 'data/repositories/history_repository.dart';
import 'data/repositories/library_repository.dart';
import 'core/errors/app_exception.dart';
import 'features/player/player_screen.dart';
import 'l10n/app_localizations.dart';
import 'services/downloader/download_service.dart';
import 'services/files/file_manager_service.dart';
import 'services/player/player_service.dart';
import 'services/update/update_service.dart';
import 'services/platform/native_channel.dart';
import 'services/security/pin_lock.dart';
import 'services/security/vault_controller.dart';
import 'services/sharing/share_service.dart';
import 'services/storage/storage_analyzer.dart';
import 'state/app_providers.dart';
import 'state/downloads_controller.dart';
import 'state/floating_player_controller.dart';
import 'state/home_controller.dart';
import 'state/incoming_share.dart';
import 'state/library_controller.dart';
import 'state/local_media_controller.dart';
import 'state/media_actions.dart';
import 'state/platforms_controller.dart';
import 'state/playlists_controller.dart';
import 'state/protection_controller.dart';
import 'state/search_controller.dart' as search_ctrl;
import 'state/settings_controller.dart';
import 'state/sources_controller.dart';
import 'widgets/common/mini_player.dart';
import 'widgets/common/floating_video_window.dart';
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
  AppLockController? _lock;
  VaultController? _vault;
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
      _lock = null;
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
        // App lock (v1.9.0): cold start with a configured PIN boots locked.
        _lock = AppLockController(
          storedHash: services.prefs.appLockHash,
          delay: AppLockDelayX.fromId(services.prefs.appLockDelayId),
        );
        // Private vault (v1.10.0): separate PIN, locked until unlocked
        // inside the vault screen.
        _vault = VaultController(storedHash: services.prefs.vaultHash);
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
    final lock = _lock;
    final vault = _vault;

    // Boot phase: loading or recoverable error — always a real UI.
    if (services == null || theme == null || lock == null || vault == null) {
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
          prefs: services.prefs,
        )),
        // Floating video window (v1.3.0): hides itself automatically when
        // playback ends or a new item replaces the current one.
        ChangeNotifierProvider(create: (_) {
          final floating = FloatingPlayerController();
          floating.attach(services.player, () => services.player.hasMedia);
          return floating;
        }),
        // Incoming share/view intents (v1.3.0): "share to DRS Video" and
        // open-with on video links from any app.
        ChangeNotifierProvider(create: (_) => IncomingShareController()),
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
          prefs: services.prefs,
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
        // CRITICAL FIX (v1.2.1): PreferencesService was read via
        // context.read<PreferencesService>() inside PlayerScreen
        // (orientation, auto-PiP, top bar) but was never registered as a
        // provider — opening ANY video crashed with
        // "Provider<PreferencesService> not found for PlayerScreen".
        Provider<PreferencesService>.value(value: services.prefs),
        // App lock controller (v1.9.0) — shared by the gate and the
        // settings screen.
        ChangeNotifierProvider<AppLockController>.value(value: lock),
        // Private vault controller (v1.10.0) — gate + settings persistence.
        ChangeNotifierProvider<VaultController>.value(value: vault),
        ChangeNotifierProvider(
          create: (_) => PlatformsController(
            factory: services.streamFactory,
            iptv: services.iptv,
            nasRepo: services.nasRepo,
            nas: services.nas,
            iptvImport: services.iptvImport,
            history: services.history,
            library: services.library,
          ),
        ),
        // v1.4.0: protection system (ad-block counter, incognito) + free
        // VPN service (engine init stays lazy until first screen open).
        ChangeNotifierProvider(
          create: (_) => ProtectionController(prefs: services.prefs),
        ),
        ChangeNotifierProvider.value(value: services.vpn),
        Provider<BrowserRepository>.value(value: services.browser),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) => MaterialApp(
            title: 'DRS Video',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(theme.dynamicColor ? lightDynamic : null),
            darkTheme: AppTheme.dark(theme.dynamicColor ? darkDynamic : null),
            themeMode: theme.materialMode,
            locale: theme.localeOverride,
            localizationsDelegates: _l10nDelegates,
            localeResolutionCallback: _resolveLocale,
            supportedLocales: _supportedLocales,
            // App lock (v1.9.0): the gate wraps the NAVIGATOR (via builder)
            // so it covers every pushed route — including the player.
            builder: (context, child) => AppLockGate(
              controller: lock,
              child: child ?? const SizedBox.shrink(),
            ),
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
  bool _shareDialogScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<HomeController>().load();
      context.read<search_ctrl.LibrarySearchController>().init();
      // Share/view intents (v1.3.0): register listener + pull cold-start.
      context.read<IncomingShareController>().init();
      // v1.12.0: silent GitHub update check (once per session, only
      // when the user keeps auto-check enabled).
      unawaited(_autoUpdateCheck());
    });
  }

  static bool _updateCheckedThisSession = false;

  Future<void> _autoUpdateCheck() async {
    if (_updateCheckedThisSession) return;
    _updateCheckedThisSession = true;
    try {
      final prefs = context.read<PreferencesService>();
      if (!prefs.updateAutoCheck) return;
      final update = await UpdateService.instance
          .checkForUpdate()
          .timeout(const Duration(seconds: 20));
      if (update == null || !mounted) return;
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.ghUpdateAvailable(update.tagName)),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: l.ghOpen,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const GitHubScreen())),
        ),
      ));
    } catch (_) {
      // Updates are a bonus — a failed background check stays silent.
    }
  }

  /// Shows the incoming-link dialog once per URL, after the current
  /// frame completes (never during build). The scheduled flag prevents
  /// duplicate dialogs while the first one is open.
  void _maybeScheduleShareDialog(String? pending) {
    if (pending == null || _shareDialogScheduled) return;
    _shareDialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (mounted) await _showIncomingShareDialog();
      } finally {
        _shareDialogScheduled = false;
      }
    });
  }

  Future<void> _showIncomingShareDialog() async {
    final share = context.read<IncomingShareController>();
    final platforms = context.read<PlatformsController>();
    final actions = context.read<MediaActions>();
    final url = share.pending;
    if (url == null) return;
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final decision = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.ondemand_video),
        title: Text(l.shareOpenTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.shareOpenBody),
            const SizedBox(height: 8),
            Text(
              url,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop('cancel'),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop('save'),
            child: Text(l.shareSaveOnly),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop('play'),
            child: Text(l.sharePlayNow),
          ),
        ],
      ),
    );
    share.consume();
    if (decision == 'cancel' || decision == null) return;
    try {
      final item = await platforms.smartOpenUrl(url);
      if (decision == 'play') {
        await actions.playItem(item);
        navigator.push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PlayerScreen(item: item),
        ));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(l.linkSaved)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(PlatformsController.describeError(
            e is AppException ? e : AppException(AppErrorType.unknown, detail: e.toString()))),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final online = context.watch<ConnectivityService>().isOnline;
    final player = context.watch<PlayerService>();
    final floating = context.watch<FloatingPlayerController>();
    // Watching makes build re-run whenever a share/view intent arrives.
    final sharePending = context.watch<IncomingShareController>().pending;
    _maybeScheduleShareDialog(sharePending);

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
            child: Stack(
              children: [
                IndexedStack(
                  index: _index,
                  children: pages,
                ),
                // Floating video window (v1.3.0) floats above tab content,
                // below pushed routes (dialogs / the full player).
                const FloatingVideoWindow(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The compact audio bar is redundant while the video window is
          // floating on screen.
          if (player.hasMedia && !floating.visible) const MiniPlayer(),
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
