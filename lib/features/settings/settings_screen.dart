import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/logger.dart';
import '../../l10n/app_localizations.dart';
import '../../services/permissions/permission_service.dart';
import '../../services/platform/native_channel.dart';
import '../../services/sharing/share_service.dart';
import '../../state/app_providers.dart';
import '../../state/downloads_controller.dart';
import '../../state/settings_controller.dart';
import 'diagnostics_screen.dart';
import 'storage_screen.dart';

/// Settings Center: playback, downloads, appearance, storage, privacy,
/// notifications, about.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final themeController = context.watch<ThemeController>();
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      body: ListView(
        children: [
          _Section(l.settingsPlayback, Icons.play_circle_outline, context, () {
            _showPlaybackSettings(context, settings, l);
          }),
          _Section(l.settingsDownloads, Icons.download_outlined, context, () {
            _showDownloadsSettings(context, settings, l);
          }),
          _Section(l.settingsAppearance, Icons.palette_outlined, context, () {
            _showAppearanceSettings(context, themeController, l);
          }),
          _Section(l.backupSection, Icons.cloud_sync_outlined, context, () {
            _showBackupSheet(context, l);
          }),
          _Section(l.settingsStorage, Icons.storage_outlined, context, () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StorageScreen()));
          }),
          _Section(l.setDiagnostics, Icons.troubleshoot_outlined, context, () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiagnosticsScreen()));
          }),
          _Section(l.settingsPrivacy, Icons.privacy_tip_outlined, context, () {
            _showPrivacySettings(context, settings, l);
          }),
          _Section(l.settingsNotifications, Icons.notifications_outlined, context, () {
            _showNotificationsSettings(context, settings, l);
          }),
          _Section(l.settingsAbout, Icons.info_outline, context, () {
            _showAbout(context, l);
          }),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l.privacyLocalDataNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _Section(String title, IconData icon, BuildContext context, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  // ---- Playback ----

  void _showPlaybackSettings(BuildContext context, SettingsController s, AppLocalizations l) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(l.setDefaultQuality, style: Theme.of(sheet).textTheme.titleSmall)),
          for (final q in ['auto', 'high', 'medium', 'low'])
            RadioListTile<String>(
              value: q,
              groupValue: s.defaultQuality,
              title: Text(switch (q) {
                'auto' => l.qualityAuto,
                'high' => l.qualityHigh,
                'medium' => l.qualityMedium,
                _ => l.qualityLow,
              }),
              onChanged: (v) {
                if (v != null) s.setDefaultQuality(v);
              },
            ),
          ListTile(title: Text(l.setDefaultSpeed, style: Theme.of(sheet).textTheme.titleSmall)),
          for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
            RadioListTile<double>(
              value: speed,
              groupValue: s.defaultSpeed,
              title: Text('${speed}x'),
              onChanged: (v) {
                if (v != null) s.setDefaultSpeed(v);
              },
            ),
          SwitchListTile(
            title: Text(l.setAutoPlayNext),
            subtitle: Text(l.setAutoPlayNextDesc),
            value: s.autoPlayNext,
            onChanged: s.setAutoPlayNext,
          ),
          SwitchListTile(
            title: Text(l.setAlwaysResume),
            subtitle: Text(l.setAlwaysResumeDesc),
            value: s.alwaysResume,
            onChanged: s.setAlwaysResume,
          ),
          SwitchListTile(
            title: Text(l.setPip),
            subtitle: Text(l.setPipDesc),
            value: s.enablePip,
            onChanged: s.setEnablePip,
          ),
          SwitchListTile(
            title: Text(l.setAutoPip),
            subtitle: Text(l.setAutoPipDesc),
            value: s.autoPip,
            onChanged: s.setAutoPip,
          ),
          SwitchListTile(
            title: Text(l.setBackground),
            subtitle: Text(l.setBackgroundDesc),
            value: s.backgroundPlayback,
            onChanged: s.setBackgroundPlayback,
          ),
          SwitchListTile(
            title: Text(l.setPreferFullscreen),
            value: s.preferFullscreen,
            onChanged: s.setPreferFullscreen,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---- Downloads ----

  void _showDownloadsSettings(BuildContext context, SettingsController s, AppLocalizations l) {
    final controller = context.read<DownloadsController>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(l.setDownloadFolder, style: Theme.of(sheet).textTheme.titleSmall),
              subtitle: Text(s.downloadDir ?? '-'),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(l.setUseCustomFolder),
              subtitle: Text(l.setCustomFolderNeedsAllFiles),
              onTap: () async {
                final granted = await PermissionService.instance.requestAllFiles();
                if (!granted) {
                  await NativeChannel.instance.openManageAllFiles();
                  return;
                }
                final share = context.read<ShareService>();
                final dir = await share.pickDirectory();
                if (dir != null) {
                  s.setDownloadDir(dir);
                  setSheetState(() {});
                }
              },
            ),
            ListTile(title: Text('${l.setConcurrency}: ${s.maxConcurrent}')),
            Slider(
              value: s.maxConcurrent.toDouble(),
              min: 1,
              max: 4,
              divisions: 3,
              label: '${s.maxConcurrent}',
              onChanged: (v) {
                s.setMaxConcurrent(v.toInt());
                setSheetState(() {});
              },
            ),
            SwitchListTile(
              title: Text(l.setWifiOnly),
              value: s.wifiOnly,
              onChanged: s.setWifiOnly,
            ),
            SwitchListTile(
              title: Text(l.setNotifyDone),
              value: s.notifyDone,
              onChanged: s.setNotifyDone,
            ),
            SwitchListTile(
              title: Text(l.setNotifyError),
              value: s.notifyError,
              onChanged: s.setNotifyError,
            ),
            SwitchListTile(
              title: Text(l.setNotifyStorage),
              value: s.notifyStorage,
              onChanged: s.setNotifyStorage,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
    // Refresh download gate with new policy.
    controller.refresh();
  }

  // ---- Appearance ----

  void _showAppearanceSettings(BuildContext context, ThemeController t, AppLocalizations l) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(l.setThemeMode, style: Theme.of(sheet).textTheme.titleSmall)),
          for (final mode in ThemeModeSetting.values)
            RadioListTile<ThemeModeSetting>(
              value: mode,
              groupValue: t.mode,
              title: Text(switch (mode) {
                ThemeModeSetting.system => l.themeSystem,
                ThemeModeSetting.light => l.themeLight,
                ThemeModeSetting.dark => l.themeDark,
              }),
              onChanged: (v) {
                if (v != null) t.setMode(v);
              },
            ),
          SwitchListTile(
            title: Text(l.setDynamicColor),
            subtitle: Text(l.setDynamicColorDesc),
            value: t.dynamicColor,
            onChanged: t.setDynamicColor,
          ),
          ListTile(title: Text(l.themeColor, style: Theme.of(sheet).textTheme.titleSmall)),
          for (final palette in AppPalette.values)
            RadioListTile<AppPalette>(
              value: palette,
              groupValue: t.palette,
              secondary: palette.seed == null
                  ? const Icon(Icons.auto_awesome)
                  : CircleAvatar(backgroundColor: palette.seed, radius: 14),
              title: Text(switch (palette) {
                AppPalette.dynamic => l.paletteDynamic,
                AppPalette.nightBlue => l.paletteNightBlue,
                AppPalette.emerald => l.paletteEmerald,
                AppPalette.purple => l.palettePurple,
                AppPalette.sunset => l.paletteSunset,
                AppPalette.calmGray => l.paletteCalmGray,
              }),
              onChanged: (v) {
                if (v != null) t.setPalette(v);
              },
            ),
          SwitchListTile(
            title: Text(l.setAnimations),
            value: t.animations,
            onChanged: t.setAnimations,
          ),
          ListTile(title: Text(l.setLayout)),
          RadioListTile<LayoutSetting>(
            value: LayoutSetting.compact,
            groupValue: t.layout,
            title: Text(l.layoutCompact),
            onChanged: (v) {
              if (v != null) t.setLayout(v);
            },
          ),
          RadioListTile<LayoutSetting>(
            value: LayoutSetting.comfortable,
            groupValue: t.layout,
            title: Text(l.layoutComfortable),
            onChanged: (v) {
              if (v != null) t.setLayout(v);
            },
          ),
          ListTile(title: Text(l.setLanguage)),
          for (final lang in LanguageSetting.values)
            RadioListTile<LanguageSetting>(
              value: lang,
              groupValue: t.language,
              title: Text(switch (lang) {
                LanguageSetting.system => l.langSystem,
                LanguageSetting.arabic => l.langArabic,
                LanguageSetting.english => l.langEnglish,
              }),
              onChanged: (v) {
                if (v != null) t.setLanguage(v);
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---- Privacy ----

  void _showPrivacySettings(BuildContext context, SettingsController s, AppLocalizations l) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          SwitchListTile(
            title: Text(l.privacyHistoryEnabled),
            subtitle: Text(l.privacyHistoryDesc),
            value: s.historyEnabled,
            onChanged: s.setHistoryEnabled,
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l.privacyClearHistory),
            onTap: () async {
              await s.clearHistory();
              if (!sheet.mounted) return;
              ScaffoldMessenger.of(sheet)
                  .showSnackBar(SnackBar(content: Text(l.storageCleared)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.search_off),
            title: Text(l.privacyClearSearch),
            onTap: () async {
              await s.clearSearchHistory();
              if (!sheet.mounted) return;
              ScaffoldMessenger.of(sheet)
                  .showSnackBar(SnackBar(content: Text(l.storageCleared)));
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever,
                color: Theme.of(sheet).colorScheme.error),
            title: Text(l.privacyClearAllData),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: sheet,
                builder: (dialog) => AlertDialog(
                  title: Text(l.privacyClearAllData),
                  content: Text(l.privacyClearAllConfirm),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(dialog).pop(false),
                        child: Text(l.cancel)),
                    FilledButton(
                        onPressed: () => Navigator.of(dialog).pop(true),
                        child: Text(l.delete)),
                  ],
                ),
              );
              if (confirmed == true) {
                await s.clearAllLocalData();
                if (!sheet.mounted) return;
                ScaffoldMessenger.of(sheet)
                    .showSnackBar(SnackBar(content: Text(l.storageCleared)));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(l.privacyPermissions),
            onTap: () async {
              final snap = await s.permissionSnapshot();
              if (!sheet.mounted) return;
              showDialog<void>(
                context: sheet,
                builder: (dialog) => AlertDialog(
                  title: Text(l.privacyPermissions),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _permRow(l.permMediaTitle, snap.media),
                      _permRow(l.permNotificationTitle, snap.notifications),
                      _permRow(l.permAllFilesTitle, snap.allFiles),
                    ],
                  ),
                  actions: [
                    TextButton(
                        onPressed: () async {
                          await openAppSettings();
                        },
                        child: Text(l.permOpenSettings)),
                    TextButton(
                        onPressed: () => Navigator.of(dialog).pop(),
                        child: Text(l.close)),
                  ],
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(l.privacyExportLogs),
            onTap: () async {
              final logs = AppLogger.instance.export();
              await Share.share(logs, subject: 'DRS Video logs');
            },
          ),
        ],
      ),
    );
  }

  Widget _permRow(String title, bool granted) => Row(
        children: [
          Icon(
            granted ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: granted ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      );

  // ---- Notifications ----

  void _showNotificationsSettings(BuildContext context, SettingsController s, AppLocalizations l) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          SwitchListTile(
            title: Text(l.setNotifyDone),
            value: s.notifyDone,
            onChanged: s.setNotifyDone,
          ),
          SwitchListTile(
            title: Text(l.setNotifyError),
            value: s.notifyError,
            onChanged: s.setNotifyError,
          ),
          SwitchListTile(
            title: Text(l.setNotifyStorage),
            value: s.notifyStorage,
            onChanged: s.setNotifyStorage,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---- About ----

  void _showAbout(BuildContext context, AppLocalizations l) {
    Future(() async {
      final info = await PackageInfo.fromPlatform();
      if (!context.mounted) return;
      showLicensePage(
        context: context,
        applicationName: l.appName,
        applicationVersion: '${l.aboutVersion} ${info.version}',
        applicationLegalese: l.aboutPrivacyBody,
      );
    });
  }

  // ---- Backup / restore (v1.1.0) ----

  Future<void> _showBackupSheet(BuildContext context, AppLocalizations l) async {
    final services = context.read<AppServices>();
    final messenger = ScaffoldMessenger.of(context);
    final backup = services.backup;

    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l.backupSection),
              titleTextStyle: Theme.of(sheet).textTheme.titleMedium,
              subtitle: Text(l.backupHint),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text(l.backupExport),
              subtitle: Text(l.backupExportDesc),
              onTap: () async {
                Navigator.of(sheet).pop();
                final count = await backup.exportAll();
                if (!messenger.mounted) return;
                messenger.showSnackBar(SnackBar(
                  content: Text(count >= 0
                      ? l.backupExportDone(count)
                      : l.backupFailed),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(l.backupImport),
              subtitle: Text(l.backupImportDesc),
              onTap: () async {
                Navigator.of(sheet).pop();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: Text(l.backupImport),
                    content: Text(l.backupImportConfirm),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(dialog).pop(false),
                          child: Text(l.cancel)),
                      FilledButton(
                          onPressed: () => Navigator.of(dialog).pop(true),
                          child: Text(l.backupImport)),
                    ],
                  ),
                );
                if (confirmed != true) return;
                final count = await backup.importAll();
                if (!messenger.mounted) return;
                messenger.showSnackBar(SnackBar(
                  content: Text(count >= 0
                      ? l.backupImportDone(count)
                      : l.backupFailed),
                ));
              },
            ),
          ],
        ),
      ),
    );
    AppLogger.instance.info('backup', 'sheet result: $result');
  }
}
