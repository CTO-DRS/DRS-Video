import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/logger.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/platform/native_channel.dart';
import '../../../services/sharing/share_service.dart';
import '../../../services/smart/image_render.dart';
import '../../../services/smart/intel_v4.dart';
import '../../../state/media_studio_controller.dart';

/// Edit studio: REAL image editing (rotate/flip/grayscale/invert/brightness/
/// contrast, rendered in isolates via the pure image_render pipeline + intel_v4
/// LUT math) that always saves a NEW copy and never destroys the original.
/// For video/audio files it offers honest file-level operations with an
/// explicit note that visual trimming is not possible today.
class EditStudioScreen extends StatefulWidget {
  const EditStudioScreen({super.key, this.initialPath});

  final String? initialPath;

  @override
  State<EditStudioScreen> createState() => _EditStudioScreenState();
}

class _EditStudioScreenState extends State<EditStudioScreen> {
  String? _path;
  String? _name;
  Uint8List? _originalBytes;
  Uint8List? _previewSourcePng; // downscaled, un-edited source (cached)
  Uint8List? _previewPng; // downscaled + current edits
  bool _isImage = false;
  bool _busy = false;
  String? _error;

  int _quarterTurns = 0;
  bool _flipH = false;
  bool _flipV = false;
  bool _grayscale = false;
  bool _invert = false;
  double _brightness = 0;
  double _contrast = 1.0;
  double _gamma = 1.0;

  EditParams get _params => EditParams(
        quarterTurns: _quarterTurns,
        flipH: _flipH,
        flipV: _flipV,
        grayscale: _grayscale,
        invert: _invert,
        brightness: _brightness.round(),
        contrast: _contrast,
        gamma: _gamma,
      );

  bool get _hasEdits => _params.hasEdits;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) _openPath(widget.initialPath!);
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path != null) await _openPath(path);
  }

  Future<void> _openPath(String path) async {
    setState(() {
      _busy = true;
      _error = null;
      _previewPng = null;
      _previewSourcePng = null;
      _path = path;
      _name = p.basename(path);
      _quarterTurns = 0;
      _flipH = _flipV = _grayscale = _invert = false;
      _brightness = 0;
      _contrast = 1;
      _gamma = 1;
    });
    try {
      final bytes = await Isolate.run(() => File(path).readAsBytesSync());
      _isImage = MediaCataloguer.of(path) == MediaBucket.image;
      if (_isImage) {
        // Decode once at full res, cache a small untouched PNG as the
        // preview source (subsequent slider moves stay fast).
        _previewSourcePng = await Isolate.run(() =>
            renderImage(bytes, const EditParams(), maxEdge: 480));
        await _rebuildPreview();
      }
      setState(() => _originalBytes = bytes);
    } catch (e) {
      AppLogger.instance.warning('edit', 'open failed: $e');
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebuildPreview() async {
    final src = _previewSourcePng;
    if (src == null) return;
    final t0 = DateTime.now();
    // Isolate.run closures must capture only sendables: snapshot params first.
    final params = _params;
    final out = await Isolate.run(() => renderImage(src, params));
    AppLogger.instance.debug('edit',
        'preview in ${DateTime.now().difference(t0).inMilliseconds}ms');
    if (mounted) setState(() => _previewPng = out);
  }

  Future<void> _saveCopy() async {
    final src = _originalBytes;
    final path = _path;
    if (src == null || path == null || !_hasEdits) return;
    setState(() => _busy = true);
    try {
      final params = _params;
      final outDir = await _outputDir();
      final stem = FileNameSuggester.sanitize(p.basenameWithoutExtension(path));
      var outPath = p.join(outDir, '${stem}_edited.png');
      var i = 1;
      while (File(outPath).existsSync()) {
        outPath = p.join(outDir, '${stem}_edited_${i++}.png');
      }
      final saved = await Isolate.run(() async {
        final data = renderImage(src, params, pngLevelOne: false);
        await File(outPath).writeAsBytes(data, flush: true);
        return outPath;
      });
      await NativeChannel.instance.scanFile(saved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.editSavedCopy)));
      await context.read<MediaStudioController>().load();
    } catch (e) {
      AppLogger.instance.warning('edit', 'save failed: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _outputDir() async {
    // App-private pictures folder (visible to the images studio scanner
    // and to the user via the file manager).
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/pictures');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_busy) {
      return Scaffold(
        appBar: AppBar(title: Text(l.studioEdit)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_path == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.studioEdit)),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tune,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(l.editPickHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open),
              label: Text(l.editPickButton),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_name ?? l.studioEdit,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l.editPickAnother,
            icon: const Icon(Icons.file_open),
            onPressed: _pickFile,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
          if (_isImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest,
                height: 260,
                alignment: Alignment.center,
                child: _previewPng != null
                    ? Image.memory(_previewPng!, fit: BoxFit.contain)
                    : const CircularProgressIndicator(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                  avatar: const Icon(Icons.rotate_right, size: 18),
                  label: Text(l.editRotate),
                  onPressed: () async {
                    setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
                    await _rebuildPreview();
                  }),
              ActionChip(
                  avatar: const Icon(Icons.flip, size: 18),
                  label: Text(l.editFlipH),
                  onPressed: () async {
                    setState(() => _flipH = !_flipH);
                    await _rebuildPreview();
                  }),
              ActionChip(
                  avatar: const Icon(Icons.flip_outlined, size: 18),
                  label: Text(l.editFlipV),
                  onPressed: () async {
                    setState(() => _flipV = !_flipV);
                    await _rebuildPreview();
                  }),
            ]),
            const SizedBox(height: 4),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.editGrayscale),
                value: _grayscale,
                onChanged: (v) async {
                  setState(() => _grayscale = v);
                  await _rebuildPreview();
                }),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.editInvert),
                value: _invert,
                onChanged: (v) async {
                  setState(() => _invert = v);
                  await _rebuildPreview();
                }),
            _Slider(
                label: l.editBrightness,
                min: -100,
                max: 100,
                divisions: 200,
                value: _brightness,
                onChanged: (v) async {
                  setState(() => _brightness = v);
                  await _rebuildPreview();
                }),
            _Slider(
                label: l.editContrast,
                min: 0,
                max: 2,
                divisions: 200,
                value: _contrast,
                onChanged: (v) async {
                  setState(() => _contrast = v);
                  await _rebuildPreview();
                }),
            _Slider(
                label: l.editGamma,
                min: 0.1,
                max: 3,
                value: _gamma,
                onChanged: (v) async {
                  setState(() => _gamma = v);
                  await _rebuildPreview();
                }),
            Row(children: [
              TextButton.icon(
                  onPressed: _hasEdits
                      ? () async {
                          setState(() {
                            _quarterTurns = 0;
                            _flipH = _flipV = _grayscale = _invert = false;
                            _brightness = 0;
                            _contrast = 1;
                            _gamma = 1;
                          });
                          await _rebuildPreview();
                        }
                      : null,
                  icon: const Icon(Icons.restart_alt),
                  label: Text(l.editReset)),
              const Spacer(),
              FilledButton.icon(
                  onPressed: _hasEdits ? _saveCopy : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l.editSave)),
            ]),
          ] else ...[
            // Honest non-image path: real file ops + explicit limitation.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(l.editNotImage,
                          style: theme.textTheme.bodySmall)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(l.studioRename),
              onTap: () => _renameCurrent(context),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(l.share),
              onTap: () => _shareCurrent(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _renameCurrent(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: _name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.studioRename),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: l.dlAddName)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(l.save)),
        ],
      ),
    );
    final path = _path;
    if (newName == null || path == null || !context.mounted) return;
    try {
      await context.read<MediaStudioController>().rename(
            StudioFile(
                path: path,
                name: _name ?? '',
                sizeBytes: 0,
                modified: DateTime.now()),
            newName,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(AppLocalizations.of(context)!.studioRenameFailed)));
      }
    }
  }

  void _shareCurrent(BuildContext context) {
    final path = _path;
    if (path == null) return;
    context.read<ShareService>().shareFile(path);
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double min;
  final double max;
  final double value;
  final int? divisions;
  final Future<void> Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    final text = max == 2
        ? value.toStringAsFixed(2)
        : value.round().toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall)),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ]),
      Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max),
          onChanged: (v) => onChanged(v)),
    ]);
  }
}
