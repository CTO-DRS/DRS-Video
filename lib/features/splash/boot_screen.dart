import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../../core/utils/logger.dart';
import '../../l10n/app_localizations.dart';

/// Localized labels for the bootstrap stages emitted by [bootstrap].
String? bootStageLabel(BuildContext context, String? stage) {
  final l = AppLocalizations.of(context)!;
  return switch (stage) {
    'media' => l.bootStageCore,
    'prefs' => l.bootStagePrefs,
    'database' => l.bootStageDatabase,
    'repositories' => l.bootStageRepositories,
    'notifications' => l.bootStageNotifications,
    'player' => l.bootStagePlayer,
    'downloads' => l.bootStageDownloads,
    'sources' => l.bootStageSources,
    _ => null,
  };
}

/// Themed host app for the boot phase (before real services are ready).
class BootMaterialApp extends StatelessWidget {
  const BootMaterialApp({
    super.key,
    required this.stage,
    required this.slow,
    required this.minimal,
    required this.error,
    required this.stack,
    required this.previousCrash,
    required this.onRetry,
    required this.onSafeMode,
  });

  final String? stage;
  final bool slow;
  final bool minimal;
  final Object? error;
  final StackTrace? stack;
  final String? previousCrash;
  final VoidCallback onRetry;
  final VoidCallback onSafeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DRS Video',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      localeResolutionCallback: (locale, supported) {
        final system = locale?.languageCode ?? 'ar';
        return supported.contains(Locale(system)) ? Locale(system) : const Locale('ar');
      },
      home: BootScreen(
        stage: stage,
        slow: slow,
        minimal: minimal,
        error: error,
        stack: stack,
        previousCrash: previousCrash,
        onRetry: onRetry,
        onSafeMode: onSafeMode,
      ),
    );
  }
}

/// Boot UI: branded loading with live stages, or a real error screen with
/// the failure cause, technical details, retry and safe mode.
class BootScreen extends StatelessWidget {
  const BootScreen({
    super.key,
    required this.stage,
    required this.slow,
    required this.minimal,
    required this.error,
    required this.stack,
    required this.previousCrash,
    required this.onRetry,
    required this.onSafeMode,
  });

  final String? stage;
  final bool slow;
  final bool minimal;
  final Object? error;
  final StackTrace? stack;
  final String? previousCrash;
  final VoidCallback onRetry;
  final VoidCallback onSafeMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: error != null
              ? SingleChildScrollView(
                  child: _BootErrorView(
                    error: error!,
                    stack: stack,
                    previousCrash: previousCrash,
                    onRetry: onRetry,
                    onSafeMode: onSafeMode,
                  ),
                )
              : SingleChildScrollView(
                  child: _BootLoadingView(
                    stage: stage,
                    slow: slow,
                    minimal: minimal,
                    previousCrash: previousCrash,
                    onRetry: onRetry,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Card shown when the previous session died with recorded errors: the
/// user sees the actual reason (and can copy it) without adb or logs.
class _PreviousCrashCard extends StatelessWidget {
  const _PreviousCrashCard({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report_outlined,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.bootPrevCrashTitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l.bootErrorCopy,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: content));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.bootErrorCopied)),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l.bootPrevCrashBody, style: theme.textTheme.bodySmall),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(l.bootPrevCrashDetails, style: theme.textTheme.bodySmall),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  content,
                  maxLines: 24,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BootLoadingView extends StatelessWidget {
  const _BootLoadingView({
    required this.stage,
    required this.slow,
    required this.minimal,
    required this.previousCrash,
    required this.onRetry,
  });

  final String? stage;
  final bool slow;
  final bool minimal;
  final String? previousCrash;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final stageText = bootStageLabel(context, stage);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.tertiary,
                ],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.play_arrow_rounded, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text('DRS Video',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 16),
          Text(
            minimal ? l.bootSafeModePreparing : l.bootPreparing,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (stageText != null) ...[
            const SizedBox(height: 6),
            Text(
              stageText,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (slow) ...[
            const SizedBox(height: 20),
            Text(
              l.bootSlow,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('boot_retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l.bootRetry),
            ),
          ],
          if (previousCrash != null) _PreviousCrashCard(content: previousCrash!),
        ],
      ),
    );
  }
}

class _BootErrorView extends StatelessWidget {
  const _BootErrorView({
    required this.error,
    required this.stack,
    required this.previousCrash,
    required this.onRetry,
    required this.onSafeMode,
  });

  final Object error;
  final StackTrace? stack;
  final String? previousCrash;
  final VoidCallback onRetry;
  final VoidCallback onSafeMode;

  String _details() {
    final buffer = StringBuffer()
      ..writeln('Error: $error');
    if (stack != null) {
      buffer
        ..writeln()
        ..writeln('Stack (first 30 lines):');
      final lines = stack.toString().split('\n');
      buffer.writeln(lines.take(30).join('\n'));
    }
    try {
      final logs = AppLogger.instance.export();
      if (logs.isNotEmpty) {
        final logLines = logs.split('\n');
        buffer
          ..writeln()
          ..writeln('Recent logs:')
          ..writeln(logLines.length > 40 ? logLines.sublist(logLines.length - 40).join('\n') : logs);
      }
    } catch (e) {
      // Log export is best-effort; record instead of hiding.
      AppLogger.instance.warning('boot', 'log export failed: $e');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(l.bootErrorTitle,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l.bootErrorBody,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$error',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          ExpansionTile(
            title: Text(l.bootErrorDetails, style: theme.textTheme.bodySmall),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _details(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('boot_retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l.bootRetry),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('boot_safe_mode'),
            onPressed: onSafeMode,
            icon: const Icon(Icons.shield_outlined),
            label: Text(l.bootSafeMode),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _details()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.bootErrorCopied)),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: Text(l.bootErrorCopy),
          ),
          if (previousCrash != null) _PreviousCrashCard(content: previousCrash!),
        ],
      ),
    );
  }
}
