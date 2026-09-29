import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/smart/intel_v4.dart';
import '../../../state/media_studio_controller.dart';
import '../../../widgets/common/empty_state.dart';
import 'studio_actions.dart';
import 'edit_studio_screen.dart';

/// Images studio: real thumbnails (Image.file), full-screen viewer,
/// share / rename / delete / info, and a hand-off to the editor.
class ImagesStudioScreen extends StatelessWidget {
  const ImagesStudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MediaStudioController>();
    final l = AppLocalizations.of(context)!;
    final files = ctrl.filesOf(MediaBucket.image);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.studioImages),
        actions: [
          IconButton(
            tooltip: l.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: ctrl.loading ? null : ctrl.load,
          ),
        ],
      ),
      body: ctrl.loading && files.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : files.isEmpty
              ? EmptyState(
                  icon: Icons.image_not_supported_outlined,
                  title: l.studioEmptyImages,
                  body: l.studioEmptyImagesBody,
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6),
                  itemCount: files.length,
                  itemBuilder: (context, i) {
                    final f = files[i];
                    return _ImageTile(
                      file: f,
                      onOpen: () => _openViewer(context, files, i),
                    );
                  },
                ),
    );
  }

  void _openViewer(BuildContext context, List<StudioFile> files, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageViewer(files: files, initialIndex: index),
    ));
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.file, required this.onOpen});

  final StudioFile file;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onOpen,
      onLongPress: () => StudioActions.showInfo(context, file),
      child: Stack(fit: StackFit.expand, children: [
        Image.file(
          File(file.path),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (c, e, st) => Center(
              child:
                  Icon(Icons.broken_image_outlined, color: theme.colorScheme.error)),
        ),
        Positioned(
          bottom: 2,
          right: 2,
          child: _TileMenu(file: file),
        ),
      ]),
    );
  }
}

class _TileMenu extends StatelessWidget {
  const _TileMenu({required this.file});

  final StudioFile file;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert,
          size: 20, color: Colors.white.withOpacity(0.9)),
      onSelected: (a) => switch (a) {
        'edit' => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EditStudioScreen(initialPath: file.path))),
        'rename' => StudioActions.rename(context, file),
        'share' => StudioActions.share(context, file),
        'info' => StudioActions.showInfo(context, file),
        'delete' => StudioActions.confirmDelete(context, file),
        _ => Future.value(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'edit', child: Text(l.studioEdit)),
        PopupMenuItem(value: 'rename', child: Text(l.studioRename)),
        PopupMenuItem(value: 'share', child: Text(l.share)),
        PopupMenuItem(value: 'info', child: Text(l.actionInfo)),
        PopupMenuItem(value: 'delete', child: Text(l.delete)),
      ],
    );
  }
}

/// Full-screen viewer with swipe navigation and per-image actions.
class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.files, required this.initialIndex});

  final List<StudioFile> files;
  final int initialIndex;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  StudioFile get _current =>
      widget.files[_index.clamp(0, widget.files.length - 1)];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(_current.name,
            style: const TextStyle(fontSize: 14),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l.studioEdit,
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    EditStudioScreen(initialPath: _current.path))),
          ),
          IconButton(
            tooltip: l.share,
            icon: const Icon(Icons.share),
            onPressed: () => StudioActions.share(context, _current),
          ),
          IconButton(
            tooltip: l.delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              await StudioActions.confirmDelete(context, _current);
              messenger.hideCurrentSnackBar();
              navigator.pop();
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.files.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final f = widget.files[i];
          return InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.file(File(f.path),
                  fit: BoxFit.contain, gaplessPlayback: true),
            ),
          );
        },
      ),
    );
  }
}
