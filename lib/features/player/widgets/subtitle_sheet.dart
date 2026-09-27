import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/player/player_service.dart';
import '../../../services/player/subtitle_charset.dart';
import '../../../services/sharing/share_service.dart';
import '../../../services/subtitles/subtitle_translator.dart';

/// Subtitle toolkit sheet (v1.10.0): per-media sync delay, legacy encoding
/// conversion (Windows-1256 / ISO-8859-6 → UTF-8) and external subtitle
/// loading with a live preview of the decoded text.
Future<void> showSubtitleSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => const _SubtitleSheet(),
  );
}

class _SubtitleSheet extends StatefulWidget {
  const _SubtitleSheet();

  @override
  State<_SubtitleSheet> createState() => _SubtitleSheetState();
}

class _SubtitleSheetState extends State<_SubtitleSheet> {
  /// Chosen encoding for the NEXT external file (null = auto).
  SubtitleEncoding? _manualEncoding;

  /// Preview of the decoded external file (first line(s)).
  String? _preview;

  bool _working = false;

  /// Translation state (v1.13.0).
  String _targetLang = 'ar';
  double _translateProgress = 0;
  bool _translating = false;

  static const double _range = 10.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final player = context.read<PlayerService>();

    return SafeArea(
      child: AnimatedBuilder(
        animation: player,
        builder: (sheet, _) {
          final delay = player.subtitleDelay;
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              ListTile(
                leading: const Icon(Icons.subtitles),
                title: Text(l.subtitleToolsTitle,
                    style: theme.textTheme.titleMedium),
              ),
              // ---- sync delay ---------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Text(l.subtitleDelayTitle,
                    style: theme.textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l.subtitleDelayEarlier,
                      icon: const Icon(Icons.remove),
                      onPressed: () async =>
                          await player.setSubtitleDelay(delay - 0.5),
                    ),
                    Expanded(
                      child: Slider(
                        value: delay.clamp(-_range, _range).toDouble(),
                        min: -_range,
                        max: _range,
                        divisions: (_range * 2 * 10).round(), // 0.1s steps
                        label:
                            '${delay >= 0 ? '+' : ''}${delay.toStringAsFixed(1)}s',
                        onChanged: (v) async =>
                            await player.setSubtitleDelay(v),
                      ),
                    ),
                    IconButton(
                      tooltip: l.subtitleDelayLater,
                      icon: const Icon(Icons.add),
                      onPressed: () async =>
                          await player.setSubtitleDelay(delay + 0.5),
                    ),
                  ],
                ),
              ),
              Center(
                child: Text(
                  delay == 0
                      ? l.subtitleDelayNone
                      : (delay > 0
                          ? l.subtitleDelayShownLater(
                              delay.toStringAsFixed(1))
                          : l.subtitleDelayShownEarlier(
                              delay.abs().toStringAsFixed(1))),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.center,
                child: TextButton.icon(
                  onPressed:
                      delay == 0 ? null : () => player.resetSubtitleDelay(),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: Text(l.subtitleDelayReset),
                ),
              ),
              const Divider(),
              // ---- legacy encoding + external file -------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(l.subtitleEncodingTitle,
                    style: theme.textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l.subtitleEncodingHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              for (final enc in SubtitleEncoding.values)
                RadioListTile<SubtitleEncoding?>(
                  dense: true,
                  value: enc,
                  groupValue: _manualEncoding,
                  title: Text(_encodingLabel(l, enc)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  onChanged: (v) => setState(() => _manualEncoding = v),
                ),
              if (_preview != null && _preview!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _preview!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FilledButton.icon(
                  onPressed:
                      _working ? null : () => _pickAndLoad(context, player),
                  icon: _working
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_open),
                  label: Text(l.subtitleLoadExternal),
                ),
              ),
              const Divider(),
              // ---- auto-translation (v1.13.0) --------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(l.translateTitle,
                    style: theme.textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  player.currentSubtitlePath == null
                      ? l.translateNoSubtitle
                      : l.translateHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.translate, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _targetLang,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final (code, name)
                              in SubtitleTranslator.languages)
                            DropdownMenuItem(
                                value: code, child: Text(name)),
                        ],
                        onChanged: _translating
                            ? null
                            : (v) =>
                                setState(() => _targetLang = v ?? 'ar'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_translating)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(
                      value: _translateProgress <= 0
                          ? null
                          : _translateProgress.clamp(0.0, 1.0)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.tonalIcon(
                  onPressed: _translating || player.currentSubtitlePath == null
                      ? null
                      : () => _translate(context, player),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(l.translateButton),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _encodingLabel(AppLocalizations l, SubtitleEncoding enc) {
    switch (enc) {
      case SubtitleEncoding.auto:
        return l.encAuto;
      case SubtitleEncoding.utf8:
        return l.encUtf8;
      case SubtitleEncoding.windows1256:
        return l.encWin1256;
      case SubtitleEncoding.iso8859_6:
        return l.encIso8859;
      case SubtitleEncoding.windows1252:
        return l.encWin1252;
    }
  }

  Future<void> _pickAndLoad(BuildContext sheetContext, PlayerService player) async {
    final l = AppLocalizations.of(context)!;
    final path = await sheetContext.read<ShareService>().pickSubtitle();
    if (path == null || !mounted) return;
    setState(() => _working = true);
    try {
      final bytes = await File(path).readAsBytes();
      final decoded =
          SubtitleCharset.decode(bytes, encoding: _manualEncoding);
      final name = path.split('/').last.split('\\').last;
      final ok = await player.loadSubtitleFromBytes(
        bytes,
        name,
        encoding: _manualEncoding,
      );
      if (!mounted) return;
      setState(() {
        _working = false;
        _preview = decoded.split('\n').take(3).join('\n');
      });
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(
        content: Text(
            ok ? l.subtitleLoadOk : l.subtitleLoadFailed),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _working = false);
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(
        content: Text(l.subtitleLoadFailed),
      ));
    }
  }

  /// v1.13.0: translates the current external subtitle and swaps the
  /// player track. Honest feedback for every outcome branch.
  Future<void> _translate(
      BuildContext sheetContext, PlayerService player) async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(sheetContext);
    setState(() {
      _translating = true;
      _translateProgress = 0;
    });
    final outcome = await player.translateCurrentSubtitle(
      targetLang: _targetLang,
      onProgress: (p) {
        if (mounted) setState(() => _translateProgress = p);
      },
    );
    if (!mounted) return;
    setState(() => _translating = false);
    String msg;
    if (outcome.done) {
      msg = outcome.cached
          ? l.translateDoneCached
          : (outcome.partial ? l.translateFailed : l.translateDone);
    } else if (outcome.alreadyTarget) {
      msg = l.translateAlreadyTarget;
    } else if (player.currentSubtitlePath == null) {
      msg = l.translateNoSubtitle;
    } else {
      msg = l.translateFailed;
    }
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }
}
