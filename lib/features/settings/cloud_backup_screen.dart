import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/errors/app_exception.dart';
import '../../core/storage/preferences_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/logger.dart';
import '../../l10n/app_localizations.dart';
import '../../services/backup/backup_service.dart';
import '../../services/backup/cloud_backup_service.dart';
import '../../state/app_providers.dart';
import '../../widgets/common/error_view.dart';

/// Configure a WebDAV/SFTP server, push backups to it, browse and restore
/// from it (v1.8.0). Works with any provider: Nextcloud, self-hosted SFTP,
/// Synology, etc.
class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  CloudBackupConfig? _config;
  List<CloudBackupInfo>? _remote;
  bool _busy = false;
  String? _lastResult;

  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _basePath = TextEditingController();
  CloudBackupKind _kind = CloudBackupKind.webdav;
  bool _tls = true;

  PreferencesService get _prefs =>
      context.read<AppServices>().prefs;

  @override
  void initState() {
    super.initState();
    _restoreSavedConfig();
  }

  /// P2 security fix (C1): the saved password no longer lives inside the
  /// SharedPreferences JSON blob — it is read from the Keystore-backed
  /// vault. A legacy plaintext password is migrated here (idempotent,
  /// lazy — the boot contract stays untouched) before hydrating the form.
  Future<void> _restoreSavedConfig() async {
    final services = context.read<AppServices>();
    try {
      await services.credentials.migrateCloudBackupPassword(_prefs);
    } catch (_) {
      // Migration is best-effort; the vault read below decides the rest.
    }
    final stored = CloudBackupConfig.tryParse(_prefs.cloudBackupConfigRaw);
    if (stored == null) return;
    var pw = stored.password; // non-empty only for a legacy not-yet-migrated blob
    try {
      final saved = await services.credentials.cloudBackupPassword();
      if (saved != null && saved.isNotEmpty) pw = saved;
    } catch (_) {
      // Vault unavailable: fall back to whatever the config blob holds.
    }
    if (!mounted) return;
    setState(() {
      _config = CloudBackupConfig(
        kind: stored.kind,
        host: stored.host,
        port: stored.port,
        username: stored.username,
        password: pw,
        useTls: stored.useTls,
        basePath: stored.basePath,
      );
      _kind = stored.kind;
      _host.text = stored.host;
      _port.text = stored.port > 0 ? '${stored.port}' : '';
      _user.text = stored.username;
      _password.text = pw;
      _basePath.text = stored.basePath;
      _tls = stored.useTls;
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _basePath.dispose();
    super.dispose();
  }

  CloudBackupConfig _currentForm() => CloudBackupConfig(
        kind: _kind,
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 0,
        username: _user.text,
        password: _password.text,
        useTls: _tls,
        basePath: _basePath.text.trim(),
      );

  Future<void> _saveForm() async {
    final cfg = _currentForm();
    _config = cfg;
    final services = context.read<AppServices>();
    try {
      // P2 (C1): the secret goes to the Keystore vault, never to prefs.
      await services.credentials
          .setCloudBackupPassword(cfg.password.isEmpty ? null : cfg.password);
    } catch (e) {
      AppLogger.instance.warning('vault', 'cloud password save failed: $e');
    }
    // The persisted blob keeps connection metadata only.
    _prefs.cloudBackupConfigRaw = configWithPassword(cfg, '').serialize();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.cloudBackupTitle),
        actions: [
          IconButton(
            tooltip: l.cloudRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _loadRemote,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- connection form -------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<CloudBackupKind>(
                    segments: [
                      ButtonSegment(
                        value: CloudBackupKind.webdav,
                        label: Text(l.cloudKindWebdav),
                        icon: const Icon(Icons.cloud_outlined),
                      ),
                      ButtonSegment(
                        value: CloudBackupKind.sftp,
                        label: Text(l.cloudKindSftp),
                        icon: const Icon(Icons.dns_outlined),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) =>
                        setState(() => _kind = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _host,
                    decoration: InputDecoration(
                      labelText: l.cloudHost,
                      hintText: _kind == CloudBackupKind.webdav
                          ? 'dav.example.com'
                          : '192.168.1.20',
                      prefixIcon: const Icon(Icons.language),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText:
                              '${l.cloudPort} (${_currentForm().effectivePort})',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_kind == CloudBackupKind.webdav)
                      Expanded(
                        child: SwitchListTile(
                          title: Text(l.cloudTls),
                          value: _tls,
                          onChanged: (v) => setState(() => _tls = v),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _user,
                    decoration: InputDecoration(
                        labelText: l.cloudUser, prefixIcon: const Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: l.cloudPassword,
                        prefixIcon: const Icon(Icons.password_outlined)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _basePath,
                    decoration: InputDecoration(
                      labelText: l.cloudBasePath,
                      hintText: '/dav',
                      prefixIcon: const Icon(Icons.folder_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(l.cloudPathNote(CloudBackupService.remoteDirName),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _test,
                        icon: const Icon(Icons.wifi_tethering),
                        label: Text(l.cloudTest),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _upload,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(l.cloudUploadNow),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ---- auto backup toggle ----------------------------------
          SwitchListTile(
            title: Text(l.cloudAutoTitle),
            subtitle: Text(_autoSubtitle(l)),
            value: _prefs.cloudBackupEnabled,
            onChanged: _config == null
                ? null
                : (v) {
                    _prefs.cloudBackupEnabled = v;
                    if (v) {
                      unawaitedAutoCheck(context);
                    }
                    setState(() {});
                  },
          ),
          if (_prefs.cloudBackupLastAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l.cloudLastBackup(_formatStamp(_prefs.cloudBackupLastAt!)),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 12),
          if (_lastResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_lastResult!,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ),
          // ---- remote list ------------------------------------------
          Text(l.cloudRemoteList, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_remote == null)
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: Text(l.cloudListHint),
              onTap: _busy ? null : _loadRemote,
            )
          else if (_remote!.isEmpty)
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(l.cloudListEmpty),
            )
          else
            for (final b in _remote!)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: Text(b.fileName,
                      style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    '${Formatters.bytes(b.sizeBytes)}'
                    ' · ${b.modifiedAt == null ? '-' : _formatStamp(b.modifiedAt!)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: l.backupImport,
                    onPressed: _busy ? null : () => _restore(b.fileName),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  String _autoSubtitle(AppLocalizations l) => _config == null
      ? l.cloudAutoNeedsConfig
      : l.cloudAutoDesc;

  String _formatStamp(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _guard(Future<void> Function() op) async {
    final l = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await op();
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      _snack(ErrorView.messageFor(context, _reasonToError(e)));
    } on SSHHostkeyError catch (e) {
      // P2 (C3): the SFTP target's key no longer matches the pinned
      // fingerprint — nothing was sent to the impostor. Offer an explicit
      // re-trust (OpenSSH-style prompt) instead of failing silently.
      AppLogger.instance.warning('cloud-backup', 'host key rejected: $e');
      if (!mounted) return;
      final retrusted = await _offerHostKeyRetrust();
      if (retrusted) {
        await _guard(op);
        return;
      }
    } catch (e) {
      AppLogger.instance.warning('cloud-backup', 'failed: $e');
      _snack(l.cloudFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// OpenSSH-style host key prompt: shows the presented fingerprint and
  /// lets the user pin it explicitly. Returns true when the caller may
  /// retry the failed operation.
  Future<bool> _offerHostKeyRetrust() async {
    final l = AppLocalizations.of(context)!;
    final services = context.read<AppServices>();
    final host = _host.text.trim();
    if (host.isEmpty) return false;
    final port = _currentForm().effectivePort;
    final presented = services.sshTrust.lastMismatchFingerprint(host, port);
    if (presented == null || presented.isEmpty) return false;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l.cloudHostKeyChangedTitle),
        content: Text(l.cloudHostKeyChangedBody(host, presented)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: Text(l.cloudHostKeyTrustNew),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await services.sshTrust.trust(host, port, presented);
    return true;
  }

  AppErrorType _reasonToError(BackupFormatException e) => switch (e.reason) {
        'empty' || 'json' || 'structure' => AppErrorType.invalidInput,
        'checksum' || 'format' || 'schema' => AppErrorType.unsupported,
        _ => AppErrorType.unknown,
      };

  Future<void> _test() => _guard(() async {
        final l = AppLocalizations.of(context)!;
        await _saveForm();
        final svc = _service();
        await svc.testConnection();
        await svc.close();
        _snack(l.cloudTestOk);
      });

  /// Builds the cloud service with the app-wide SSH trust store (P2/C3).
  CloudBackupService _service() => CloudBackupService(
        config: _config!,
        trustStore: context.read<AppServices>().sshTrust,
      );

  Future<void> _upload() => _guard(() async {
        final l = AppLocalizations.of(context)!;
        final services = context.read<AppServices>();
        _saveForm();
        final backup = BackupService(
          library: services.library,
          playlists: services.playlists,
          history: services.history,
          prefs: services.prefs,
        );
        final localPath = await backup.buildBackupFile();
        final svc = _service();
        final remote = await svc.uploadBackup(localPath);
        await svc.close();
        _prefs.cloudBackupLastAt = DateTime.now();
        if (!mounted) return;
        setState(() => _lastResult = l.cloudUploaded(remote));
        await _loadRemote();
      });

  Future<void> _loadRemote() => _guard(() async {
        if (_config == null) await _saveForm();
        if (_host.text.trim().isEmpty) return;
        final svc = _service();
        final list = await svc.listBackups();
        await svc.close();
        if (!mounted) return;
        setState(() => _remote = list);
      });

  Future<void> _restore(String fileName) => _guard(() async {
        final l = AppLocalizations.of(context)!;
        final services = context.read<AppServices>();
        final svc = _service();
        final dir = await getTempDownloadDir();
        final local = await svc.downloadBackup(
            fileName, '$dir/$fileName');
        await svc.close();
        final raw = await File(local).readAsString();
        final backup = BackupService(
          library: services.library,
          playlists: services.playlists,
          history: services.history,
          prefs: services.prefs,
        );
        final parsed = backup.parseBackup(raw);
        if (!mounted) return;
        final confirmed = await _confirm(l, parsed.appVersion,
            parsed.exportedAt);
        if (!confirmed || !mounted) return;
        final result = await backup.mergeInto(parsed.payload);
        if (!mounted) return;
        setState(() =>
            _lastResult = l.backupImportDone(
              result.addedItems,
              result.skippedItems,
              result.addedPlaylists,
              result.mergedPlaylists,
              result.restoredProgress,
              result.restoredSearches,
            ));
      });

  Future<bool> _confirm(AppLocalizations l, String version, DateTime at) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l.backupConfirmTitle),
        content: Text(l.backupConfirmBody(version, _formatStamp(at))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: Text(l.backupConfirmRestore),
          ),
        ],
      ),
    );
    return res ?? false;
  }
}

/// Fired (fire-and-forget) when the user enables the auto toggle: if a
/// backup is due right now, push one immediately.
void unawaitedAutoCheck(BuildContext context) {
  final services = context.read<AppServices>();
  final prefs = services.prefs;
  final cfg = CloudBackupConfig.tryParse(prefs.cloudBackupConfigRaw);
  if (!CloudBackupPolicy.shouldAutoBackup(
    enabled: prefs.cloudBackupEnabled,
    config: cfg,
    lastBackupAt: prefs.cloudBackupLastAt,
    now: DateTime.now(),
  )) {
    return;
  }
  () async {
    try {
      // P2 (C1): hydrate the secret from the vault — the persisted blob
      // no longer carries the password.
      var hydrated = cfg!;
      if (hydrated.password.isEmpty) {
        try {
          final pw = await services.credentials.cloudBackupPassword();
          if (pw != null && pw.isNotEmpty) {
            hydrated = configWithPassword(hydrated, pw);
          }
        } catch (_) {
          // Vault unavailable → empty password → auth will fail loudly.
        }
      }
      final backup = BackupService(
        library: services.library,
        playlists: services.playlists,
        history: services.history,
        prefs: prefs,
      );
      final localPath = await backup.buildBackupFile();
      final svc = CloudBackupService(
        config: hydrated,
        trustStore: services.sshTrust,
      );
      await svc.uploadBackup(localPath);
      await svc.close();
      prefs.cloudBackupLastAt = DateTime.now();
      AppLogger.instance.info('cloud-backup', 'auto backup done');
    } catch (e) {
      AppLogger.instance.warning('cloud-backup', 'auto backup failed: $e');
    }
  }();
}

/// Returns a copy of [cfg] with [password] in place (used to hydrate
/// from the vault without touching the persisted metadata blob).
CloudBackupConfig configWithPassword(CloudBackupConfig cfg, String password) =>
    CloudBackupConfig(
      kind: cfg.kind,
      host: cfg.host,
      port: cfg.port,
      username: cfg.username,
      password: password,
      useTls: cfg.useTls,
      basePath: cfg.basePath,
    );

/// Temp dir for downloaded remote backups (import staging).
Future<String> getTempDownloadDir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/backups');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir.path;
}
