import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../state/sources_controller.dart';
import '../../widgets/common/empty_state.dart';

/// Source Manager: shows the built-in adapters and user-registered sources.
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SourcesController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SourcesController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.sourcesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.smart_display_outlined),
              title: Text(l.sourcesLocalAdapter),
              subtitle: Text(l.sourcesLocalAdapterDesc),
              trailing: const Icon(Icons.lock, size: 18),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.link),
              title: Text(l.sourcesDirectAdapter),
              subtitle: Text(l.sourcesDirectAdapterDesc),
              trailing: const Icon(Icons.lock, size: 18),
            ),
          ),
          if (controller.sources.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.dns_outlined,
                title: l.sourcesAddTitle,
                body: l.sourcesPrivacyNote,
                actionLabel: l.sourcesAddTitle,
                onAction: () => _showAddSheet(context),
              ),
            )
          else
            for (final source in controller.sources)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: Icon(
                    Icons.dns_outlined,
                    color:
                        source.enabled ? theme.colorScheme.primary : theme.colorScheme.outline,
                  ),
                  title: Text(source.name),
                  subtitle: Text(
                    source.baseUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: source.enabled,
                        onChanged: (v) => controller.toggle(source.id, v),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (a) {
                          if (a == 'test') controller.testConnection(source.baseUrl);
                          if (a == 'delete') controller.delete(source.id);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'test', child: Text(l.sourcesTest)),
                          PopupMenuItem(value: 'delete', child: Text(l.delete)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          if (controller.testResult != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                controller.testResult == 'ok' ? l.sourcesTestOk : l.sourcesTestFail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: controller.testResult == 'ok'
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.privacy_tip_outlined,
                    size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.sourcesPrivacyNote,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context),
        icon: const Icon(Icons.add),
        label: Text(l.sourcesAddTitle),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    final controller = context.read<SourcesController>();
    final l = AppLocalizations.of(context)!;
    final name = TextEditingController();
    final baseUrl = TextEditingController();
    final headerName = TextEditingController();
    final headerValue = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheet).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 8,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.sourcesAddTitle,
                  style: Theme.of(sheet).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                decoration: InputDecoration(hintText: l.sourcesNameHint),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: baseUrl,
                keyboardType: TextInputType.url,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l.openUrlInvalid : null,
                decoration: InputDecoration(hintText: l.sourcesBaseUrlHint),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: headerName,
                      decoration:
                          InputDecoration(hintText: l.sourcesHeaderHint),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: headerValue,
                decoration:
                    const InputDecoration(hintText: 'Bearer xxx / token'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  await controller.add(
                    name: name.text,
                    baseUrl: baseUrl.text,
                    headerName: headerName.text,
                    headerValue: headerValue.text,
                  );
                  if (sheet.mounted) Navigator.of(sheet).pop();
                },
                icon: const Icon(Icons.add_link),
                label: Text(l.add),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
