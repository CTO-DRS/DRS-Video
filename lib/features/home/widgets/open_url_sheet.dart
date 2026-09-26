import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/media_actions.dart';
import '../../../widgets/common/error_view.dart';
import '../../player/play_helpers.dart';

/// Bottom sheet for opening a video URL (direct adapter resolve + play).
Future<void> showOpenUrlSheet(BuildContext context) async {
  final controller = TextEditingController();
  final l = AppLocalizations.of(context)!;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.openUrlTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l.openUrlHint,
              prefixIcon: const Icon(Icons.link),
            ),
            onSubmitted: (_) => _go(sheetContext, context, controller.text),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _go(sheetContext, context, controller.text),
            icon: const Icon(Icons.play_arrow),
            label: Text(l.play),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

void _go(BuildContext sheetContext, BuildContext context, String url) {
  final l = AppLocalizations.of(sheetContext)!;
  final actions = context.read<MediaActions>();
  Navigator.of(sheetContext).pop();
  Future(() async {
    final item = await actions.openUrl(url.trim());
    if (item == null) {
      final err = actions.lastError;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err == null
              ? l.playerErrorUnknown
              : ErrorView.messageFor(context, err.type)),
        ));
      }
      return;
    }
    if (!context.mounted) return;
    await openPlayerFromLibrary(context, item, [item]);
  });
}
