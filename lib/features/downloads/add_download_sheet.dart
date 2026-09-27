import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';
import '../../services/downloader/url_probe_service.dart';
import '../../services/smart/intel_v4.dart';
import '../../state/downloads_controller.dart';

/// v1.14.0 add-download sheet: paste link (manual or auto-detected from the
/// clipboard), preview it (probe), choose options, start the download.
/// Every capability is real — the probe is a genuine HEAD request.
class AddDownloadSheet extends StatefulWidget {
  const AddDownloadSheet({super.key});

  /// Static open helper (FAB / menus).
  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const AddDownloadSheet(),
      );

  @override
  State<AddDownloadSheet> createState() => _AddDownloadSheetState();
}

class _AddDownloadSheetState extends State<AddDownloadSheet> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _probe = UrlProbeService();
  ProbeSummary? _summary;
  bool _probing = false;
  bool _starting = false;
  String? _error;
  String? _clipboardSuggestion;
  bool _clipboardDismissed = false;
  DownloadPriority _priority = DownloadPriority.normal;

  @override
  void initState() {
    super.initState();
    _detectClipboard();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectClipboard() async {
    String? raw;
    try {
      raw = await Clipboard.getData('text/plain').then((d) => d?.text);
    } catch (_) {
      return; // clipboard unavailable — silent, honest (no fake suggestion)
    }
    final decision = ClipboardLinkGate.decide(raw, alreadyInField: _urlCtrl.text);
    if (decision == ClipboardDecision.accept && mounted) {
      setState(() => _clipboardSuggestion = raw!.trim());
    }
  }

  Future<void> _pasteManual() async {
    final data = await Clipboard.getData('text/plain');
    final text = (data?.text ?? '').trim();
    if (!mounted) return;
    if (ClipboardLinkGate.isHttpUrl(text)) {
      setState(() {
        _urlCtrl.text = text;
        _clipboardSuggestion = null;
        _summary = null;
        _error = null;
      });
    } else {
      setState(() => _error = AppLocalizations.of(context)!.dlAddInvalidUrl);
    }
  }

  void _applyClipboardSuggestion() {
    setState(() {
      _urlCtrl.text = _clipboardSuggestion!;
      _clipboardSuggestion = null;
      _summary = null;
      _error = null;
    });
  }

  Future<void> _runProbe() async {
    final url = _urlCtrl.text.trim();
    final l = AppLocalizations.of(context)!;
    if (!ClipboardLinkGate.isHttpUrl(url)) {
      setState(() {
        _error = l.dlAddInvalidUrl;
        _summary = null;
      });
      return;
    }
    setState(() {
      _probing = true;
      _error = null;
      _summary = null;
    });
    try {
      final s = await _probe.probe(url);
      if (!mounted) return;
      setState(() {
        _summary = s;
        // v1.14.1: prefer the platform-extracted title (human readable) over
        // the CDN hash name for the pre-filled file name.
        if (_nameCtrl.text.trim().isEmpty) {
          final rt = s.resolvedTitle?.trim();
          _nameCtrl.text =
              (rt != null && rt.isNotEmpty) ? rt : s.fileName;
        }
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(l, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l.dlAddProbeFailed);
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _start() async {
    final url = _urlCtrl.text.trim();
    final l = AppLocalizations.of(context)!;
    if (!ClipboardLinkGate.isHttpUrl(url)) {
      setState(() => _error = l.dlAddInvalidUrl);
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final name = _nameCtrl.text.trim().isNotEmpty
          ? FileNameSuggester.sanitize(_nameCtrl.text.trim())
          : _summary?.fileName ??
              FileNameSuggester.suggest(url: url, fallback: 'download');
      await context.read<DownloadsController>().startFromUrl(
            url: url,
            title: name,
            priority: _priority,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.dlAddStarted)),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(l, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l.dlAddProbeFailed);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  static String _errorText(AppLocalizations l, AppException e) => switch (e.type) {
        AppErrorType.network => l.playerErrorNetwork,
        AppErrorType.timeout => l.playerErrorTimeout,
        AppErrorType.notFound => l.dlAddNotFound,
        AppErrorType.forbidden => l.dlAddForbidden,
        AppErrorType.storage => l.dlAddStorage,
        // v1.14.1: the link is a web page (extraction failed) — honest,
        // actionable guidance instead of silently saving a .txt document.
        AppErrorType.invalidInput => l.dlAddPageNotMedia,
        _ => l.dlAddProbeFailed,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
          bottom: bottomInset, left: 16, right: 16, top: 8),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: Text(l.dlAddTitle, style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: MaterialLocalizations.of(context)
                    .closeButtonTooltip,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
            // لصق تلقائي من الحافظة: chip only when the gate accepted it.
            if (_clipboardSuggestion != null && !_clipboardDismissed)
              Card(
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.content_paste_go),
                  title: Text(l.dlAddClipboardFound,
                      style: theme.textTheme.bodySmall),
                  subtitle: Text(_clipboardSuggestion!,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: TextButton(
                    onPressed: _applyClipboardSuggestion,
                    child: Text(l.dlAddPaste),
                  ),
                ),
              ),
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              maxLines: 1,
              onChanged: (_) {
                if (_summary != null) setState(() => _summary = null);
              },
              decoration: InputDecoration(
                labelText: l.dlAddUrlLabel,
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  tooltip: l.dlAddPaste,
                  icon: const Icon(Icons.content_paste),
                  onPressed: _pasteManual,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.tonalIcon(
                onPressed: _probing ? null : _runProbe,
                icon: _probing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: Text(_probing ? l.dlAddProbing : l.dlAddProbe),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
            if (_summary != null) ...[
              const SizedBox(height: 12),
              // العرض — the preview card.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(_kindIcon(_summary!.kind),
                              size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(l.dlAddPreviewTitle,
                                style: theme.textTheme.titleSmall),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        _previewRow(l.dlAddName, _summary!.fileName),
                        _previewRow(l.dlAddKind, _kindLabel(l, _summary!.kind)),
                        _previewRow(
                            l.dlAddSize,
                            _summary!.sizeBytes >= 0
                                ? Formatters.bytes(_summary!.sizeBytes)
                                : l.dlAddUnknownSize),
                        _previewRow(
                            l.dlAddResumableQ,
                            _summary!.resumable
                                ? l.dlAddResumableYes
                                : l.dlAddResumableNo),
                      ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // خيارات التحميل
            Text(l.dlAddOptions, style: theme.textTheme.titleSmall),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: l.dlAddName,
                prefixIcon: const Icon(Icons.drive_file_rename_outline),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<DownloadPriority>(
              segments: [
                ButtonSegment(
                    value: DownloadPriority.high, label: Text(l.downloadsPriorityHigh)),
                ButtonSegment(
                    value: DownloadPriority.normal,
                    label: Text(l.downloadsPriorityNormal)),
                ButtonSegment(
                    value: DownloadPriority.low, label: Text(l.downloadsPriorityLow)),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _starting ? null : _start,
              icon: _starting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: Text(l.dlAddStart),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _previewRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
            child: Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  static IconData _kindIcon(DownloadKind k) => switch (k) {
        DownloadKind.video => Icons.movie_outlined,
        DownloadKind.audio => Icons.audiotrack_outlined,
        DownloadKind.image => Icons.image_outlined,
        DownloadKind.archive => Icons.folder_zip_outlined,
        DownloadKind.document => Icons.description_outlined,
        DownloadKind.app => Icons.android_outlined,
        DownloadKind.other => Icons.insert_drive_file_outlined,
      };

  static String _kindLabel(AppLocalizations l, DownloadKind k) => switch (k) {
        DownloadKind.video => l.kindVideo,
        DownloadKind.audio => l.kindAudio,
        DownloadKind.image => l.kindImage,
        DownloadKind.archive => l.kindArchive,
        DownloadKind.document => l.kindDocument,
        DownloadKind.app => l.kindApp,
        DownloadKind.other => l.kindOther,
      };
}
