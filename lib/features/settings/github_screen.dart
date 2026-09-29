import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/storage/preferences_service.dart';
import '../../l10n/app_localizations.dart';
import '../../services/platform/native_channel.dart';
import '../../services/smart/intel_v2.dart' show VersionCompare;
import '../../services/update/update_service.dart';

/// GitHub hub + in-app self-update (v1.12.0).
///
/// One screen covering the user-facing half of the release pipeline:
///  • Update card — current vs latest release, one-tap check, streamed
///    download with progress + md5 verification, native install intent.
///  • Releases — the recent GitHub releases with notes; any of them can
///    be downloaded and installed the same way.
///  • Links — repository, releases page and the developer account.
class GitHubScreen extends StatefulWidget {
  const GitHubScreen({super.key});

  @override
  State<GitHubScreen> createState() => _GitHubScreenState();
}

enum _Stage { idle, checking, downloading, installing }

class _GitHubScreenState extends State<GitHubScreen> {
  final UpdateService _svc = UpdateService.instance;

  List<GitHubRelease> _releases = const [];
  GitHubRelease? _update;
  _Stage _stage = _Stage.idle;
  double? _progress;
  String? _error;
  bool _autoCheck = true;

  /// The version the app is REALLY running (live PackageInfo), so the
  /// update card never compares against a stale hand-maintained constant
  /// (root cause of the endless-update-prompt bug fixed in v1.14.5).
  String _currentVersion = AppConstants.appVersion;

  @override
  void initState() {
    super.initState();
    _autoCheck =
        context.read<PreferencesService>().updateAutoCheck;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // One silent check for the update card + fill the releases list.
    await _check(silent: true);
  }

  Future<void> _check({bool silent = false}) async {
    setState(() {
      _stage = _Stage.checking;
      _error = null;
      if (!silent) _progress = null;
    });
    try {
      _currentVersion = await UpdateService.runningVersion();
      final releases = await _svc.fetchReleases(limit: 10);
      GitHubRelease? update;
      for (final r in releases) {
        if (r.apkAsset == null) continue;
        if (VersionCompare.isNewer(r.tagName, _currentVersion)) {
          update = r;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _releases = releases;
        _update = update;
        _stage = _Stage.idle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        if (!silent) _error = e.toString();
      });
    }
  }

  Future<void> _downloadAndInstall(GitHubRelease release) async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _error = null;
    });
    try {
      final path = await _svc.downloadApk(
        release,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => total > 0 ? _progress = received / total : null);
        },
      );
      if (!mounted) return;
      setState(() => _stage = _Stage.installing);
      final ok = await NativeChannel.instance.installApk(path);
      if (!mounted) return;
      setState(() => _stage = _Stage.idle);
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(l.ghInstallFailed)));
      }
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _progress = null;
        _error = e.message == 'cancelled' ? null : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _progress = null;
        _error = e.toString();
      });
    }
  }

  Future<void> _open(String url) => NativeChannel.instance.openExternal(url);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final busy = _stage == _Stage.checking ||
        _stage == _Stage.downloading ||
        _stage == _Stage.installing;

    return Scaffold(
      appBar: AppBar(title: Text(l.ghTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ---- update card -------------------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.system_update_alt,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.ghUpdateSection,
                          style: theme.textTheme.titleMedium),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(l.ghCurrentVersion(_currentVersion),
                      style: theme.textTheme.bodyMedium),
                  if (_update != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l.ghUpdateAvailable(_update!.tagName),
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary),
                      ),
                    ),
                  if (_stage == _Stage.checking)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  if (_stage == _Stage.downloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                        value: _progress, minHeight: 6),
                    const SizedBox(height: 6),
                    Text(
                      _progress == null
                          ? l.ghDownloading
                          : l.ghDownloadingPct((_progress! * 100).round()),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (_stage == _Stage.installing)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(l.ghInstalling,
                          style: theme.textTheme.bodySmall),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error)),
                    ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: [
                    FilledButton.icon(
                      onPressed: busy ? null : () => _check(),
                      icon: const Icon(Icons.refresh),
                      label: Text(l.ghCheckUpdate),
                    ),
                    if (_update != null)
                      FilledButton.tonalIcon(
                        onPressed:
                            busy ? null : () => _downloadAndInstall(_update!),
                        icon: const Icon(Icons.download),
                        label: Text(l.ghInstall),
                      ),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.ghAutoCheck,
                        style: theme.textTheme.bodyMedium),
                    subtitle: Text(l.ghAutoCheckDesc,
                        style: theme.textTheme.bodySmall),
                    value: _autoCheck,
                    onChanged: (v) {
                      setState(() => _autoCheck = v);
                      context.read<PreferencesService>().updateAutoCheck = v;
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ---- links --------------------------------------------------------
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.code),
                title: Text(l.ghOpenRepo),
                subtitle: const Text(AppConstants.githubRepo),
                onTap: () => _open(AppConstants.githubRepoUrl),
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(l.ghOpenReleases),
                subtitle: const Text(AppConstants.githubReleasesUrl),
                onTap: () => _open(AppConstants.githubReleasesUrl),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(l.ghOpenDeveloper),
                subtitle: const Text(AppConstants.githubDeveloperUrl),
                onTap: () => _open(AppConstants.githubDeveloperUrl),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ---- releases -------------------------------------------------------
          Text(l.ghReleasesSection, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (_releases.isEmpty && _stage != _Stage.checking)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(l.ghNoReleases,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            )
          else
            for (final r in _releases)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  title: Text(r.name.isNotEmpty ? r.name : r.tagName,
                      style: theme.textTheme.titleSmall),
                  subtitle: Text(
                    '${r.tagName}${r.prerelease ? ' · beta' : ''}'
                    '${r.publishedAtMs > 0 ? ' · ${_date(r.publishedAtMs)}' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: r.apkAsset == null
                      ? null
                      : IconButton(
                          tooltip: l.ghInstall,
                          icon: const Icon(Icons.download),
                          onPressed: busy
                              ? null
                              : () => _downloadAndInstall(r),
                        ),
                  children: [
                    if (r.body.isEmpty)
                      Text(l.ghNoNotes,
                          style: theme.textTheme.bodySmall)
                    else
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          _trimNotes(r.body),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Notes are markdown; show the first ~600 chars stripped of heavy
  /// markdown syntax so the tile stays readable.
  static String _trimNotes(String body) {
    var t = body
        .replaceAll(RegExp(r'^#{1,6}\s?', multiLine: true), '')
        .replaceAll('**', '')
        .replaceAll('`', '');
    if (t.length > 600) t = '${t.substring(0, 600)}…';
    return t;
  }
}
