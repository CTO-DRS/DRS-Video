import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/errors/app_exception.dart';
import '../../l10n/app_localizations.dart';
import '../../state/downloads_controller.dart';
import '../../state/media_actions.dart';
import '../../state/platforms_controller.dart';
import '../player/player_screen.dart';
import 'platform_browser_screen.dart';

/// v1.14.3 — NATIVE YouTube search screen.
///
/// Why this exists: until now the only way to reach YouTube inside the app
/// was the built-in WebView browser — the full YouTube site renders inside
/// it, which is slow on mid-range phones AND still shows YouTube's own
/// ads. Downloading from there was impossible too: a copied watch URL is
/// an HTML page, which the download pipeline correctly rejects.
///
/// This screen talks to YouTube directly (youtube_explode, the same engine
/// playback uses): results arrive in seconds, there are no ads, and every
/// result can be PLAYED (per-session stream resolution through
/// MediaActions.playItem) or DOWNLOADED (the platform resolver now picks
/// the best muxed MP4 for the native download engine).
class YouTubeSearchScreen extends StatefulWidget {
  const YouTubeSearchScreen({super.key});

  /// True when [url] points at any YouTube host (home page, m., music,
  /// youtu.be). Used to route the Sites catalog YouTube entry to this
  /// native screen instead of the WebView browser.
  static bool isYouTubeSite(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final h = uri.host.toLowerCase();
    return h == 'youtube.com' ||
        h.endsWith('.youtube.com') ||
        h == 'youtu.be';
  }

  @override
  State<YouTubeSearchScreen> createState() => _YouTubeSearchScreenState();
}

class _YouTubeSearchScreenState extends State<YouTubeSearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  YoutubeExplode? _yt;

  List<Video>? _results;
  bool _searching = false;
  String? _error;
  String _playingId = '';
  final Set<String> _downloading = {};

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _yt?.close();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _ctrl.text.trim();
    final l = AppLocalizations.of(context)!;
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _results = null;
    });
    try {
      _yt ??= YoutubeExplode();
      final list = await _yt!.search
          .search(q)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _results = list.toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l.ytSearchFailed);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _play(Video v) async {
    final l = AppLocalizations.of(context)!;
    final watch = 'https://www.youtube.com/watch?v=${v.id.value}';
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _playingId = v.id.value);
    try {
      final item = await context
          .read<PlatformsController>()
          .smartOpenUrl(watch, title: v.title);
      await context.read<MediaActions>().playItem(item);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlayerScreen(item: item),
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.ytSearchFailed)));
    } finally {
      if (mounted) setState(() => _playingId = '');
    }
  }

  Future<void> _download(Video v) async {
    final l = AppLocalizations.of(context)!;
    final watch = 'https://www.youtube.com/watch?v=${v.id.value}';
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloading.add(v.id.value));
    try {
      await context
          .read<DownloadsController>()
          .startFromUrl(url: watch, title: v.title);
      messenger.showSnackBar(SnackBar(content: Text(l.dlAddStarted)));
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_dlError(l, e))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.dlAddProbeFailed)));
    } finally {
      if (mounted) setState(() => _downloading.remove(v.id.value));
    }
  }

  static String _dlError(AppLocalizations l, AppException e) =>
      switch (e.type) {
        AppErrorType.network => l.playerErrorNetwork,
        AppErrorType.timeout => l.playerErrorTimeout,
        AppErrorType.storage => l.dlAddStorage,
        _ => l.ytSearchExtractFailed,
      };

  static String _fmtDuration(Duration? d) {
    if (d == null) return '';
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.ytSearchTitle),
        actions: [
          IconButton(
            tooltip: l.openInBrowser,
            icon: const Icon(Icons.public),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PlatformBrowserScreen(
                initialUrl: 'https://www.youtube.com',
                title: 'YouTube',
              ),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                hintText: l.ytSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _results = null);
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            _Message(icon: Icons.wifi_off, text: _error!)
          else if (_results != null && _results!.isEmpty)
            _Message(icon: Icons.search_off, text: l.ytSearchEmpty)
          else if (_results != null)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: _results!.length,
                itemBuilder: (context, i) {
                  final v = _results![i];
                  final busyPlay = _playingId == v.id.value;
                  final busyDl = _downloading.contains(v.id.value);
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 96,
                        height: 54,
                        child: ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Image.network(
                            v.thumbnails.mediumResUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.movie_outlined, size: 22)),
                          ),
                        ),
                      ),
                    ),
                    title: Text(v.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [
                        v.author,
                        if (_fmtDuration(v.duration).isNotEmpty)
                          _fmtDuration(v.duration),
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: busyPlay ? null : () => _play(v),
                    trailing: busyPlay
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : busyDl
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(
                                tooltip: l.dlAddTitle,
                                icon: const Icon(Icons.download_outlined),
                                onPressed: () => _download(v),
                              ),
                  );
                },
              ),
            )
          else
            Expanded(
              child: Center(
                child: Icon(Icons.play_circle_outline,
                    size: 72, color: theme.colorScheme.primaryContainer),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 44, color: Theme.of(context).disabledColor),
                const SizedBox(height: 12),
                Text(text, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}
