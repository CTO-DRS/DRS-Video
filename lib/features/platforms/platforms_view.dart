import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/media_item.dart';
import '../../data/models/stream_models.dart';
import '../../l10n/app_localizations.dart';
import '../../services/player/player_service.dart';
import '../../services/network/stream_source_factory.dart';
import '../../state/platforms_controller.dart';
import '../player/player_screen.dart';

/// المنصات (Platforms) tab: everything for watching videos from outside
/// the device — direct stream links, IPTV playlists and NAS servers.
///
/// Three sub-tabs keep each source type scannable; every action (add/import/
/// browse/play) happens inside the app.
class PlatformsView extends StatefulWidget {
  const PlatformsView({super.key});

  @override
  State<PlatformsView> createState() => _PlatformsViewState();
}

class _PlatformsViewState extends State<PlatformsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlatformsController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlatformsController>();
    final l = AppLocalizations.of(context)!;

    if (controller.loading && controller.links.isEmpty && controller.playlists.isEmpty && controller.servers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(icon: const Icon(Icons.link), text: l.platformsLinks),
            Tab(icon: const Icon(Icons.live_tv), text: l.platformsIptv),
            Tab(icon: const Icon(Icons.dns), text: l.platformsNas),
          ],
        ),
        body: Builder(
          builder: (context) {
            if (controller.error != null) {
              return _ErrorPane(
                message: PlatformsController.describeError(controller.error!),
                onRetry: controller.load,
              );
            }
            return TabBarView(
              children: [
                _LinksTab(controller: controller),
                _IptvTab(controller: controller),
                _NasTab(controller: controller),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Direct links
// ---------------------------------------------------------------------------

class _LinksTab extends StatelessWidget {
  const _LinksTab({required this.controller});

  final PlatformsController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (controller.links.isEmpty) {
      return _EmptyPane(
        icon: Icons.link,
        title: l.platformsEmptyLinks,
        body: l.platformsEmptyLinksBody,
        actionLabel: l.addLinkTitle,
        onAction: () => showAddLinkDialog(context),
      );
    }
    return ListView.builder(
      itemCount: controller.links.length,
      itemBuilder: (context, i) {
        final item = controller.links[i];
        final progress = controller.linkProgress[item.id];
        final resumable = progress != null &&
            !progress.completed &&
            progress.positionMs >= 5000;
        return ListTile(
          leading: const Icon(Icons.play_circle_outline, size: 32),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.uri,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (resumable)
                Text(
                  l.resumeFrom(Formatters.duration(progress.positionMs)),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              if (resumable)
                LinearProgressIndicator(
                  value: progress.ratio(),
                  minHeight: 2,
                ),
            ],
          ),
          isThreeLine: resumable,
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'copy':
                  copyLink(context, item.uri);
                case 'favorite':
                  await controller.toggleFavorite(item.id);
                case 'delete':
                  await controller.deleteLink(item.id);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'copy', child: Text(l.copyLink)),
              PopupMenuItem(
                value: 'favorite',
                child: Text(item.isFavorite ? l.actionUnfavorite : l.actionFavorite),
              ),
              PopupMenuItem(value: 'delete', child: Text(l.delete)),
            ],
          ),
          onTap: () => playStreamItem(context, item),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// IPTV
// ---------------------------------------------------------------------------

class _IptvTab extends StatelessWidget {
  const _IptvTab({required this.controller});

  final PlatformsController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (controller.playlists.isEmpty) {
      return _EmptyPane(
        icon: Icons.live_tv,
        title: l.platformsEmptyIptv,
        body: l.platformsEmptyIptvBody,
        actionLabel: l.iptvImportUrl,
        onAction: () => showImportIptvSheet(context),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: controller.importing
                    ? null
                    : () => showImportIptvSheet(context),
                icon: const Icon(Icons.add),
                label: Text(l.iptvImport),
              ),
              if (controller.importing) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(l.iptvImporting),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: controller.playlists.length,
            itemBuilder: (context, i) {
              final pl = controller.playlists[i];
              return ListTile(
                leading: const Icon(Icons.subscriptions_outlined, size: 30),
                title: Text(pl.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(l.iptvChannels(pl.channelCount)),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'delete') {
                      final l2 = AppLocalizations.of(context)!;
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: Text(l2.iptvDeleteConfirmTitle),
                          content: Text(l2.iptvDeleteConfirmBody(pl.name)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dialog).pop(false),
                              child: Text(l2.cancel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(dialog).pop(true),
                              child: Text(l2.delete),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await controller.deletePlaylist(pl.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'delete', child: Text(l.delete)),
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => IptvPlaylistScreen(playlist: pl),
                )),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Full-screen channel browser for one playlist: SQL search + group filter.
class IptvPlaylistScreen extends StatefulWidget {
  const IptvPlaylistScreen({super.key, required this.playlist});

  final IptvPlaylist playlist;

  @override
  State<IptvPlaylistScreen> createState() => _IptvPlaylistScreenState();
}

class _IptvPlaylistScreenState extends State<IptvPlaylistScreen> {
  String? _group;
  String _search = '';
  List<IptvChannel> _channels = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = context.read<PlatformsController>();
      final channels = await controller.channelsOf(
        widget.playlist.id,
        group: _group,
        search: _search.isEmpty ? null : _search,
      );
      if (!mounted) return;
      setState(() => _channels = channels);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final controller = context.read<PlatformsController>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.iptvSearchChannels,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (q) {
                _search = q;
                _load();
              },
            ),
          ),
          FutureBuilder<List<String>>(
            future: controller.groupsOf(widget.playlist.id),
            builder: (context, snap) {
              final groups = snap.data ?? const <String>[];
              if (groups.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(l.iptvGroupsAll),
                        selected: _group == null,
                        onSelected: (_) {
                          setState(() => _group = null);
                          _load();
                        },
                      ),
                    ),
                    for (final g in groups)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(g, overflow: TextOverflow.ellipsis),
                          selected: _group == g,
                          onSelected: (_) {
                            setState(() => _group = g);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorPane(
                        message: l.iptvLoadFail,
                        onRetry: _load,
                      )
                    : _channels.isEmpty
                        ? Center(child: Text(l.iptvNoChannels))
                        : ListView.builder(
                            itemCount: _channels.length,
                            itemBuilder: (context, i) {
                              final ch = _channels[i];
                              return ListTile(
                                leading: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: ch.logoUrl != null &&
                                          ch.logoUrl!.isNotEmpty
                                      ? Image.network(
                                          ch.logoUrl!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.tv_outlined),
                                        )
                                      : const Icon(Icons.tv_outlined),
                                ),
                                title: Text(ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: ch.groupName == null
                                    ? null
                                    : Text(ch.groupName!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                trailing: ch.isLive
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          l.liveBadge,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                  color: Colors.white),
                                        ),
                                      )
                                    : null,
                                onTap: () async {
                                  final item = await controller
                                      .playItemForChannel(ch);
                                  if (!context.mounted) return;
                                  await playStreamItem(context, item);
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NAS
// ---------------------------------------------------------------------------

class _NasTab extends StatelessWidget {
  const _NasTab({required this.controller});

  final PlatformsController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (controller.servers.isEmpty) {
      return _EmptyPane(
        icon: Icons.dns,
        title: l.platformsEmptyNas,
        body: l.platformsEmptyNasBody,
        actionLabel: l.nasAddServer,
        onAction: () => showAddServerDialog(context),
      );
    }
    return ListView.builder(
      itemCount: controller.servers.length,
      itemBuilder: (context, i) {
        final server = controller.servers[i];
        final icon = switch (server.protocol) {
          NasProtocol.webdav => Icons.cloud_outlined,
          NasProtocol.ftp => Icons.folder_shared_outlined,
          NasProtocol.sftp => Icons.terminal_outlined,
        };
        return ListTile(
          leading: Icon(icon, size: 32),
          title: Text(server.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${server.scheme}://${server.host}:${server.port}'),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              if (action == 'delete') {
                final l2 = AppLocalizations.of(context)!;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: Text(l2.nasDeleteConfirmTitle),
                    content: Text(l2.nasDeleteConfirmBody(server.name)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialog).pop(false),
                        child: Text(l2.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialog).pop(true),
                        child: Text(l2.delete),
                      ),
                    ],
                  ),
                );
                if (ok == true) await controller.deleteServer(server.id);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'delete', child: Text(l.delete)),
            ],
          ),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => NasBrowserScreen(server: server),
          )),
        );
      },
    );
  }
}

/// File browser for one NAS server: breadcrumbs, folders, video playback.
class NasBrowserScreen extends StatefulWidget {
  const NasBrowserScreen({super.key, required this.server});

  final NasServer server;

  @override
  State<NasBrowserScreen> createState() => _NasBrowserScreenState();
}

class _NasBrowserScreenState extends State<NasBrowserScreen> {
  String _path = '/';
  List<NasEntry> _entries = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _browse('/');
  }

  Future<void> _browse(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = context.read<PlatformsController>();
      final entries = await controller.browse(widget.server, path);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _path = path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _crumbs {
    final parts = _path.split('/').where((s) => s.isNotEmpty).toList();
    return parts;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final controller = context.read<PlatformsController>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_path == '/') {
          Navigator.of(context).pop();
        } else {
          final parts = _crumbs..removeLast();
          _browse(parts.isEmpty ? '/' : '/${parts.join('/')}');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Flexible(
                child: TextBreadcrumb(
                  crumbs: _crumbs,
                  root: l.nasRoot,
                  onCrumbTap: (p) => _browse(p),
                ),
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorPane(
                    message: l.nasBrowseFail(
                        _error is AppException
                            ? PlatformsController.describeError(
                                _error as AppException)
                            : _error.toString()),
                    onRetry: () => _browse(_path),
                  )
                : _entries.isEmpty
                    ? Center(child: Text(l.nasEmptyFolder))
                    : RefreshIndicator(
                        onRefresh: () => _browse(_path),
                        child: ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (context, i) {
                            final e = _entries[i];
                            return ListTile(
                              leading: Icon(
                                e.isDir
                                    ? Icons.folder_outlined
                                    : Icons.movie_outlined,
                                size: 30,
                                color: e.isVideo
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              title: Text(e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: !e.isDir && e.sizeBytes != null
                                  ? Text(Formatters.bytes(e.sizeBytes!))
                                  : null,
                              onTap: () async {
                                if (e.isDir) {
                                  final next = _path == '/'
                                      ? '/${e.name}'
                                      : '$_path/${e.name}';
                                  await _browse(next);
                                } else if (e.isVideo) {
                                  final item = await controller
                                      .playItemForNasFile(
                                          widget.server, e);
                                  if (!context.mounted) return;
                                  await playStreamItem(context, item);
                                }
                              },
                            );
                          },
                        ),
                      ),
        floatingActionButton: _path == '/'
            ? null
            : FloatingActionButton(
                tooltip: l.nasUp,
                onPressed: () {
                  final parts = _crumbs..removeLast();
                  _browse(parts.isEmpty ? '/' : '/${parts.join('/')}');
                },
                child: const Icon(Icons.arrow_upward),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs / helpers
// ---------------------------------------------------------------------------

class TextBreadcrumb extends StatelessWidget {
  const TextBreadcrumb({
    super.key,
    required this.crumbs,
    required this.root,
    required this.onCrumbTap,
  });

  final List<String> crumbs;
  final String root;
  final void Function(String path) onCrumbTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme.titleMedium;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          InkWell(
            onTap: () => onCrumbTap('/'),
            child: Text(root, style: theme, maxLines: 1),
          ),
          for (var i = 0; i < crumbs.length; i++) ...[
            const Text('  ›  ', style: TextStyle(color: Colors.grey)),
            InkWell(
              onTap: () => onCrumbTap('/${crumbs.sublist(0, i + 1).join('/')}'),
              child: Text(crumbs[i], style: theme, maxLines: 1),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens a stream item directly through PlayerService (the row already
/// lives in the library; no source-adapter resolution is wanted here).
Future<void> playStreamItem(BuildContext context, MediaItem item) async {
  final player = context.read<PlayerService>();
  await player.open(item);
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PlayerScreen(item: item),
  ));
}

void copyLink(BuildContext context, String url) async {
  final l = AppLocalizations.of(context)!;
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l.linkCopied)),
  );
}

/// Quick-add dialog for a direct stream link (toolbar ＋ button too).
Future<void> showAddLinkDialog(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final controller = context.read<PlatformsController>();
  final urlCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  Future<void> submit({required bool playNow}) async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final item = await controller.addLink(
        urlCtrl.text,
        title: nameCtrl.text.isEmpty ? null : nameCtrl.text,
      );
      messenger.showSnackBar(SnackBar(content: Text(l.linkSaved)));
      navigator.pop();
      if (playNow && context.mounted) {
        await playStreamItem(context, item);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e is AppException
            ? PlatformsController.describeError(e)
            : e.toString()),
      ));
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.addLinkTitle),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: urlCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: l.addLinkUrlHint),
              validator: (v) =>
                  (v == null || !StreamSourceFactory.isSupportedUrl(v))
                      ? l.addLinkInvalid
                      : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: l.addLinkNameHint),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => submit(playNow: false),
          child: Text(l.addLinkSaveOnly),
        ),
        FilledButton(
          onPressed: () => submit(playNow: true),
          child: Text(l.addLinkPlayNow),
        ),
      ],
    ),
  );
}

/// IPTV import sheet: from URL or from a local M3U/M3U8 file.
Future<void> showImportIptvSheet(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final controller = context.read<PlatformsController>();
  final urlCtrl = TextEditingController();
  final nameCtrl = TextEditingController();

  Future<void> importUrl() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pl = await controller.importFromUrl(
        urlCtrl.text,
        name: nameCtrl.text.isEmpty ? null : nameCtrl.text,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(l.iptvImportDone(pl.channelCount)),
      ));
      navigator.pop();
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => IptvPlaylistScreen(playlist: pl),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.iptvImportFail(e.toString())),
      ));
    }
  }

  Future<void> importFile() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pl = await controller.pickAndImportPlaylist();
      if (pl == null) return; // user cancelled the picker
      messenger.showSnackBar(SnackBar(
        content: Text(l.iptvImportDone(pl.channelCount)),
      ));
      navigator.pop();
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => IptvPlaylistScreen(playlist: pl),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.iptvImportFail(e.toString())),
      ));
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(l.iptvImportFile),
            onTap: importFile,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l.iptvImportUrlHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: l.iptvImportNameHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: controller.importing ? null : importUrl,
              icon: const Icon(Icons.download),
              label: Text(l.iptvImportUrl),
            ),
          ),
          if (controller.importing)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Add-NAS-server dialog: protocol segmented button + connection fields.
Future<void> showAddServerDialog(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final controller = context.read<PlatformsController>();
  NasProtocol protocol = NasProtocol.webdav;
  int port = AppConstants.webdavDefaultPort;

  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setDialogState) {
        final hostCtrl = TextEditingController();
        final portCtrl = TextEditingController(text: '$port');
        final nameCtrl = TextEditingController();
        final userCtrl = TextEditingController();
        final passCtrl = TextEditingController();
        bool useTls = false;

        void applyProtocol(NasProtocol p) {
          protocol = p;
          switch (p) {
            case NasProtocol.webdav:
              port = AppConstants.webdavDefaultPort;
            case NasProtocol.ftp:
              port = AppConstants.ftpDefaultPort;
            case NasProtocol.sftp:
              port = AppConstants.sftpDefaultPort;
          }
          portCtrl.text = '$port';
          if (p != NasProtocol.webdav) useTls = false;
        }

        Future<void> submit() async {
          final messenger = ScaffoldMessenger.of(context);
          final navigator = Navigator.of(dialog);
          final parsedPort = int.tryParse(portCtrl.text) ?? port;
          try {
            await controller.addServer(
              name: nameCtrl.text,
              protocol: protocol,
              host: hostCtrl.text,
              port: parsedPort,
              username: userCtrl.text,
              password: passCtrl.text.isEmpty ? null : passCtrl.text,
              useTls: useTls,
            );
            navigator.pop();
          } catch (e) {
            messenger.showSnackBar(SnackBar(
              content: Text(l.nasConnectFail(e is AppException
                  ? PlatformsController.describeError(e)
                  : e.toString())),
            ));
          }
        }

        return AlertDialog(
          title: Text(l.nasAddServer),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<NasProtocol>(
                  segments: const [
                    ButtonSegment(
                        value: NasProtocol.webdav, label: Text('WebDAV')),
                    ButtonSegment(value: NasProtocol.ftp, label: Text('FTP')),
                    ButtonSegment(
                        value: NasProtocol.sftp, label: Text('SFTP')),
                  ],
                  selected: {protocol},
                  onSelectionChanged: (selection) {
                    setDialogState(() => applyProtocol(selection.first));
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration:
                      InputDecoration(labelText: l.nasName),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: hostCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration:
                      InputDecoration(labelText: l.nasHost),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.nasPort),
                  onChanged: (v) =>
                      port = int.tryParse(v) ?? port,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: userCtrl,
                  decoration:
                      InputDecoration(labelText: l.nasUsername),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration:
                      InputDecoration(labelText: l.nasPassword),
                ),
                if (protocol == NasProtocol.webdav)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.nasUseTls),
                    value: useTls,
                    onChanged: (v) => setDialogState(() => useTls = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: submit,
              child: Text(l.save),
            ),
          ],
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared panes
// ---------------------------------------------------------------------------

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l.retry),
            ),
          ],
        ),
      ),
    );
  }
}
