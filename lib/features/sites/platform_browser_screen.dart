import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/storage/preferences_service.dart';
import '../../data/repositories/browser_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/browser/ad_block.dart';
import '../../features/player/player_screen.dart';
import '../../state/media_actions.dart';
import '../../state/platforms_controller.dart';
import '../../state/protection_controller.dart';

/// Built-in platform browser (v1.4.0): opens YouTube, TikTok or ANY site
/// inside the app — with real ad/tracker blocking, per-site desktop UA,
/// bookmarks, history and one-tap hand-off of detected video streams to
/// the native player (mpv) or the floating window.
class PlatformBrowserScreen extends StatefulWidget {
  const PlatformBrowserScreen({
    super.key,
    required this.initialUrl,
    this.title,
  });

  /// May be a bare URL or a search phrase (normalized via [BrowserUtils]).
  final String initialUrl;
  final String? title;

  @override
  State<PlatformBrowserScreen> createState() => _PlatformBrowserScreenState();
}

class _PlatformBrowserScreenState extends State<PlatformBrowserScreen> {
  InAppWebViewController? _controller;
  late String _currentUrl;
  final _addressCtl = TextEditingController();
  final _addressFocus = FocusNode();

  double _progress = 0;
  String? _pageTitle;
  bool _isBookmarked = false;
  bool _desktopUa = false;
  bool _incognito = false;
  int _sessionBlocked = 0;
  final List<String> _detected = [];
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    final prefs = context.read<PreferencesService>();
    _desktopUa = prefs.browserDesktopUa;
    _incognito = prefs.browserIncognito;
    _currentUrl = BrowserUtils.normalizeUrl(widget.initialUrl);
    _addressCtl.text = _currentUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProtectionController>(); // warm listeners
      _refreshBookmarkState();
    });
  }

  @override
  void dispose() {
    _addressCtl.dispose();
    _addressFocus.dispose();
    // Persist any pending blocked-count delta.
    try {
      context.read<ProtectionController>().flush();
    } catch (_) {}
    super.dispose();
  }

  /// Shield icon state (read during build -> watch for reactivity).
  bool get _adBlockOn => context.watch<ProtectionController>().adBlockEnabled;

  Future<void> _refreshBookmarkState() async {
    final repo = context.read<BrowserRepository>();
    final marked = await repo.isBookmarked(_currentUrl);
    if (mounted) setState(() => _isBookmarked = marked);
  }

  Future<void> _load(String raw) async {
    final url = BrowserUtils.normalizeUrl(raw);
    if (url.isEmpty) return;
    setState(() {
      _currentUrl = url;
      _addressCtl.text = url;
      _navigating = true;
      _detected.clear();
      _sessionBlocked = 0;
    });
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _onLoadStop(InAppWebViewController c, WebUri? url) async {
    final pageUrl = url?.toString() ?? _currentUrl;
    final title = await c.getTitle();
    if (!mounted) return;
    final prefs = context.read<PreferencesService>();
    final repo = context.read<BrowserRepository>();
    final protection = context.read<ProtectionController>();
    setState(() {
      _currentUrl = pageUrl;
      _addressCtl.text = pageUrl;
      _pageTitle = title;
      _navigating = false;
    });
    _refreshBookmarkState();
    // History recording (respects incognito + the global history switch).
    if (!_incognito && prefs.historyEnabled && pageUrl.startsWith('http')) {
      unawaited(repo.addHistory(pageUrl, title ?? ''));
    }
    unawaited(protection.flush());
  }

  // ---- protection: block ad/tracker hosts at network level ----
  Future<WebResourceResponse?> _shouldIntercept(
      InAppWebViewController c, WebResourceRequest request) async {
    final protection = context.read<ProtectionController>();
    if (!protection.adBlockEnabled) return null;
    final url = request.url.toString();
    if (!url.startsWith('http')) return null;
    final host = BrowserUtils.hostOf(url);
    if (host.isEmpty) return null;
    if (await AdBlockList.instance.shouldBlock(host)) {
      _sessionBlocked++;
      protection.registerBlocked(1);
      return WebResourceResponse(
        contentType: 'text/plain',
        data: Uint8List.fromList([]),
        statusCode: 403,
        reasonPhrase: 'DRS blocked',
      );
    }
    return null;
  }

  // ---- stream detection: surface playable media URLs ----
  void _onResource(InAppWebViewController c, LoadedResource? resource) {
    final url = resource?.url?.toString();
    if (url == null || !url.startsWith('http')) return;
    final isStream = BrowserUtils.isMediaStreamUrl(url) ||
        url.contains('.m3u8') ||
        url.contains('.mpd');
    if (!isStream) return;
    if (_detected.contains(url)) return;
    if (_detected.length >= AppConstants.browserDetectedStreamsCap) return;
    if (!mounted) return;
    setState(() => _detected.add(url));
  }

  // ---- native playback hand-off (YouTube + detected streams) ----
  Future<void> _playNative(String url) async {
    final platforms = context.read<PlatformsController>();
    final actions = context.read<MediaActions>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final item = await platforms.smartOpenUrl(url);
      await actions.playItem(item);
      if (!mounted) return;
      await navigator.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlayerScreen(item: item),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.browserPlayFailed),
      ));
    }
  }

  void _showStreamsSheet() {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            Text(l.browserStreamsTitle,
                style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (BrowserUtils.isYouTubeWatchUrl(_currentUrl))
              _StreamTile(
                label: l.browserPlayThisPage,
                kind: 'YouTube',
                url: _currentUrl,
                onPlay: () {
                  Navigator.of(sheet).pop();
                  _playNative(_currentUrl);
                },
              ),
            for (final s in _detected)
              _StreamTile(
                label: s.length > 60 ? '${s.substring(0, 60)}…' : s,
                kind: BrowserUtils.streamKindLabel(s),
                url: s,
                onPlay: () {
                  Navigator.of(sheet).pop();
                  _playNative(s);
                },
              ),
            if (_detected.isEmpty && !BrowserUtils.isYouTubeWatchUrl(_currentUrl))
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l.browserNoStreams,
                    textAlign: TextAlign.center,
                    style: Theme.of(sheet).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleBookmark() async {
    final repo = context.read<BrowserRepository>();
    final l = AppLocalizations.of(context)!;
    if (_isBookmarked) {
      await repo.removeBookmark(_currentUrl);
    } else {
      await repo.addBookmark(_currentUrl, _pageTitle ?? '');
    }
    if (mounted) {
      setState(() => _isBookmarked = !_isBookmarked);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isBookmarked ? l.bookmarkAdded : l.bookmarkRemoved),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  Future<void> _toggleUa() async {
    final prefs = context.read<PreferencesService>();
    _desktopUa = !_desktopUa;
    prefs.browserDesktopUa = _desktopUa;
    await _controller?.setSettings(settings: InAppWebViewSettings(
      userAgent: _ua,
    ));
    if (mounted) setState(() {});
    await _controller?.reload();
  }

  String get _ua => _desktopUa
      ? AppConstants.browserDesktopUserAgent
      : AppConstants.browserMobileUserAgent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return PopScope(
      // Back button walks the WebView history first; only then leaves.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          await c.goBack();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _addressCtl,
          focusNode: _addressFocus,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: _load,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            hintText: l.browserAddressHint,
            prefixIcon: Icon(
              _currentUrl.startsWith('https')
                  ? Icons.lock_outline
                  : Icons.language,
              size: 18,
            ),
            suffixIcon: _navigating
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _addressCtl.clear();
                      _addressFocus.requestFocus();
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          // Shield: ad-block state + session blocked count.
          IconButton(
            tooltip: l.browserShieldTooltip,
            onPressed: () => _showShieldSheet(),
            icon: Badge(
              isLabelVisible: _sessionBlocked > 0,
              label: Text('$_sessionBlocked'),
              child: Icon(
                _adBlockOn ? Icons.shield : Icons.shield_outlined,
                color: _adBlockOn ? theme.colorScheme.primary : null,
              ),
            ),
          ),
          // Detected streams count.
          IconButton(
            tooltip: l.browserStreamsTooltip,
            onPressed: _showStreamsSheet,
            icon: Badge(
              isLabelVisible: _detected.isNotEmpty,
              label: Text('${_detected.length}'),
              child: const Icon(Icons.ondemand_video_outlined),
            ),
          ),
          // Desktop UA toggle.
          IconButton(
            tooltip: l.browserUaTooltip,
            onPressed: _toggleUa,
            icon: Icon(_desktopUa ? Icons.desktop_windows : Icons.smartphone),
          ),
          // Bookmark.
          IconButton(
            tooltip: _isBookmarked ? l.bookmarkRemove : l.bookmarkAdd,
            onPressed: _toggleBookmark,
            icon: Icon(_isBookmarked ? Icons.star : Icons.star_border),
          ),
        ],
        bottom: _progress < 1 && _progress > 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress, minHeight: 2))
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
              initialSettings: InAppWebViewSettings(
                userAgent: _ua,
                useShouldInterceptRequest: true,
                useOnLoadResource: true,
                transparentBackground: false,
                supportZoom: true,
              ),
              onWebViewCreated: (c) => _controller = c,
              onLoadStart: (c, url) {
                if (mounted) setState(() => _navigating = true);
              },
              onLoadStop: _onLoadStop,
              onProgressChanged: (c, p) {
                if (mounted) setState(() => _progress = p / 100);
              },
              onTitleChanged: (c, t) {
                if (mounted) setState(() => _pageTitle = t);
              },
              shouldOverrideUrlLoading: (c, action) async {
                // Fast path: navigation-level blocking of known bad hosts.
                final protection = context.read<ProtectionController>();
                if (protection.adBlockEnabled) {
                  final host = BrowserUtils.hostOf(action.request.url.toString());
                  if (host.isNotEmpty &&
                      await AdBlockList.instance.shouldBlock(host)) {
                    protection.registerBlocked(1);
                    return NavigationActionPolicy.CANCEL;
                  }
                }
                return NavigationActionPolicy.ALLOW;
              },
              shouldInterceptRequest: _shouldIntercept,
              onLoadResource: _onResource,
              onReceivedError: (c, req, err) {
                if (mounted) setState(() => _navigating = false);
              },
              onEnterFullscreen: (c) {},
              onExitFullscreen: (c) {},
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _showShieldSheet() {
    final l = AppLocalizations.of(context)!;
    final protection = context.read<ProtectionController>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.browserShieldTooltip,
                  style: Theme.of(sheet).textTheme.titleMedium),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (context, setSheetState) => Column(children: [
                  SwitchListTile(
                    title: Text(l.protectionAdBlock),
                    subtitle: Text(l.browserBlockedSession(_sessionBlocked)),
                    value: protection.adBlockEnabled,
                    onChanged: (v) {
                      protection.setAdBlock(v);
                      setSheetState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: Text(l.protectionIncognito),
                    value: protection.incognito,
                    onChanged: (v) {
                      protection.setIncognito(v);
                      setState(() => _incognito = v);
                      setSheetState(() {});
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Text(
                l.protectionBlocklistInfo,
                style: Theme.of(sheet).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreamTile extends StatelessWidget {
  const _StreamTile({
    required this.label,
    required this.kind,
    required this.url,
    required this.onPlay,
  });

  final String label;
  final String kind;
  final String url;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListTile(
      dense: true,
      leading: Chip(
        label: Text(kind, style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
      ),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l.browserPlayInPlayer,
          style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(Icons.play_arrow),
      onTap: onPlay,
    );
  }
}
