import 'package:flutter/material.dart';
import '../../core/errors/app_exception.dart';
import '../../l10n/app_localizations.dart';

/// Error display with retry + optional secondary action (e.g. open the
/// page in the built-in browser) + expandable technical details.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
    this.onOpenInBrowser,
  });

  final Object? error;
  final VoidCallback? onRetry;
  final bool compact;

  /// Shown as a secondary action for page links (TikTok/YouTube/social)
  /// that failed direct playback: the built-in browser can still play
  /// them in-app (v1.4.1).
  final VoidCallback? onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final appError = error is AppException ? error as AppException : null;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: compact ? 36 : 52, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              l.playerErrorTitle,
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            if (!compact && appError != null) ...[
              const SizedBox(height: 8),
              Text(messageFor(context, appError.type),
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center),
            ],
            if (appError?.detail != null && !compact) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(l.details, style: theme.textTheme.bodySmall),
                children: [
                  Text(
                    appError!.detail!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ],
            if (onRetry != null || onOpenInBrowser != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRetry != null)
                    FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(l.retry),
                    ),
                  if (onRetry != null && onOpenInBrowser != null)
                    const SizedBox(width: 12),
                  if (onOpenInBrowser != null)
                    OutlinedButton.icon(
                      onPressed: onOpenInBrowser,
                      icon: const Icon(Icons.public),
                      label: Text(l.openInBrowser),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String messageFor(BuildContext context, AppErrorType type) {
    final l = AppLocalizations.of(context)!;
    return switch (type) {
      AppErrorType.network => l.playerErrorNetwork,
      AppErrorType.timeout => l.playerErrorTimeout,
      AppErrorType.notFound => l.playerErrorNotFound,
      AppErrorType.forbidden => l.playerErrorForbidden,
      AppErrorType.unsupported => l.playerErrorUnsupported,
      AppErrorType.corrupted => l.playerErrorCorrupted,
      AppErrorType.storage => l.downloadsInsufficientSpace,
      AppErrorType.permission => l.localFilesPermissionNeeded,
      AppErrorType.cancelled => l.cancel,
      AppErrorType.invalidInput => l.openUrlInvalid,
      AppErrorType.unknown => l.playerErrorUnknown,
    };
  }
}
