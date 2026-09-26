import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/browser_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/browser/sites_catalog.dart';
import 'platform_browser_screen.dart';

/// "المواقع" sub-tab (v1.4.0): the bundled real-platforms catalog
/// (YouTube, TikTok, Shahid, Netflix, …) + user-added sites + bookmarks.
/// Tapping a site opens the built-in browser with ad blocking.
class SitesTab extends StatefulWidget {
  const SitesTab({super.key});

  @override
  State<SitesTab> createState() => _SitesTabState();
}

class _SitesTabState extends State<SitesTab> {
  String _query = '';
  String _category = '';
  List<UserSite> _userSites = [];
  bool _loading = true;

  static const _categoryOrder = [
    'mine', 'video', 'arabic', 'movies', 'live', 'sports', 'music',
    'anime', 'social', 'learn', 'tv',
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final repo = context.read<BrowserRepository>();
    await SitesCatalog.instance.ensureLoaded();
    final users = await repo.userSites();
    if (!mounted) return;
    setState(() {
      _userSites = users;
      _loading = false;
    });
  }

  void _open(String url, [String? title]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlatformBrowserScreen(
        initialUrl: url,
        title: title,
      ),
    ));
  }

  Future<void> _addCustomSite() async {
    final l = AppLocalizations.of(context)!;
    final nameCtl = TextEditingController();
    final urlCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final repo = context.read<BrowserRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l.sitesAddTitle),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtl,
                decoration: InputDecoration(
                    labelText: l.sitesAddName, hintText: 'YouTube'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l.sitesNameRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: urlCtl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                    labelText: l.sitesAddUrl, hintText: 'youtube.com'),
                validator: (v) {
                  final normalized =
                      BrowserUtilsLite.normalizeSiteUrl(v ?? '');
                  if (normalized == null) return l.addLinkInvalid;
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialog).pop(true);
              }
            },
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final url = BrowserUtilsLite.normalizeSiteUrl(urlCtl.text.trim());
    if (url == null) return;
    await repo.addUserSite(nameCtl.text.trim(), url);
    if (mounted) {
      await _refresh();
      _open(url, nameCtl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_loading) return const Center(child: CircularProgressIndicator());

    final all =
        SitesCatalog.mergeUserSites(SitesCatalog.instance.sites, _userSites);
    final byCat = SitesCatalog.byCategory(all, _category);
    final visible = SitesCatalog.filter(byCat, _query);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomSite,
        icon: const Icon(Icons.add),
        label: Text(l.sitesAddAny),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: l.sitesSearchHint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // Category chips + "open empty browser" action.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('', l.sitesAll),
                for (final c in _categoryOrder) _chip(c, _catLabel(c, l)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ActionChip(
                    avatar: const Icon(Icons.history, size: 18),
                    label: Text(l.sitesBookmarks),
                    onPressed: _showBookmarksSheet,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.45,
                ),
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final s = visible[i];
                  return _SiteCard(
                    site: s,
                    onTap: () => _open(s.url, s.name),
                    onDelete: s.category == 'mine'
                        ? () async {
                            final repo = context.read<BrowserRepository>();
                            final user = _userSites.firstWhere(
                                (u) => u.url == s.url,
                                orElse: () => _userSites.first);
                            await repo.removeUserSite(user.id);
                            await _refresh();
                          }
                        : null,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _catLabel(String c, AppLocalizations l) => switch (c) {
        'mine' => l.sitesCatMine,
        'video' => l.sitesCatVideo,
        'arabic' => l.sitesCatArabic,
        'movies' => l.sitesCatMovies,
        'live' => l.sitesCatLive,
        'sports' => l.sitesCatSports,
        'music' => l.sitesCatMusic,
        'anime' => l.sitesCatAnime,
        'social' => l.sitesCatSocial,
        'learn' => l.sitesCatLearn,
        'tv' => l.sitesCatTv,
        _ => c,
      };

  Widget _chip(String value, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilterChip(
          label: Text(label),
          selected: _category == value,
          onSelected: (_) => setState(() => _category = value),
        ),
      );

  Future<void> _showBookmarksSheet() async {
    final l = AppLocalizations.of(context)!;
    final repo = context.read<BrowserRepository>();
    final marks = await repo.bookmarks();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.sitesBookmarks,
                  style: Theme.of(sheet).textTheme.titleMedium),
            ),
            if (marks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l.bookmarksEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(sheet).textTheme.bodySmall),
              ),
            for (final m in marks)
              ListTile(
                dense: true,
                leading: const Icon(Icons.star),
                title: Text(m.title.isEmpty ? m.url : m.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(m.url,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await repo.removeBookmark(m.url);
                    Navigator.of(sheet).pop();
                    await _refresh();
                  },
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _open(m.url, m.title);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.site, required this.onTap, this.onDelete});

  final CatalogSite site;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = site.name.isEmpty ? '?' : site.name[0].toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primaryContainer,
                      ),
                      child: Text(
                        initial,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      site.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (onDelete != null)
              PositionedDirectional(
                top: 0,
                end: 0,
                child: InkResponse(
                  onTap: onDelete,
                  child: Icon(Icons.remove_circle_outline,
                      size: 18, color: scheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small shared URL helper kept separate from the browser screen to avoid
/// a UI import here (used by the add-site dialog validator).
class BrowserUtilsLite {
  BrowserUtilsLite._();

  /// Returns a normalized https URL, or null when invalid.
  static String? normalizeSiteUrl(String input) {
    final t = input.trim();
    if (t.isEmpty) return null;
    var url = t;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(url)) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      return null;
    }
    return url;
  }
}
