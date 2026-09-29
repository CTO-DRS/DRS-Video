import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/network/vpngate_service.dart';
import '../../services/vpn/vpn_service.dart';
import '../../state/protection_controller.dart';

/// الحماية والـ VPN (v1.4.0): real ad/tracker blocking, incognito mode,
/// and a FREE OpenVPN client — public VPNGate servers (no account, no
/// fees) plus importing any .ovpn file.
class ProtectionScreen extends StatefulWidget {
  const ProtectionScreen({super.key});

  @override
  State<ProtectionScreen> createState() => _ProtectionScreenState();
}

class _ProtectionScreenState extends State<ProtectionScreen> {
  bool _loadingServers = false;
  List<VpngateServer> _servers = [];
  String? _serversError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<VpnService>().ensureInitialized();
    });
  }

  Future<void> _loadServers({bool force = false}) async {
    setState(() {
      _loadingServers = true;
      _serversError = null;
    });
    try {
      final all = await VpngateService().fetch(force: force);
      if (!mounted) return;
      setState(() => _servers = all);
    } catch (e) {
      if (!mounted) return;
      setState(() => _serversError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingServers = false);
    }
  }

  Future<void> _connect(VpnTarget target) async {
    final vpn = context.read<VpnService>();
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await vpn.connect(target);
    if (!ok && vpn.lastError != null) {
      // Permission denial is silent (user cancelled the system dialog).
      if (vpn.lastError != 'permission-denied') {
        messenger.showSnackBar(SnackBar(content: Text(l.vpnConnectFailed)));
      }
    }
  }

  Future<void> _importOvpn() async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ovpn', 'conf', 'txt'],
      withData: true,
    );
    final file = res?.files.single;
    if (file == null) return;
    final content = String.fromCharCodes(file.bytes ?? []);
    if (!content.contains('remote ')) {
      messenger.showSnackBar(SnackBar(content: Text(l.vpnInvalidConfig)));
      return;
    }
    await _connect(VpnTarget(
      name: file.name.replaceAll(RegExp(r'\.(ovpn|conf|txt)$'), ''),
      subtitle: l.vpnImportedFile,
      config: content,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final vpn = context.watch<VpnService>();
    final protection = context.watch<ProtectionController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.protectionTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- VPN card ----
          _VpnCard(
            vpn: vpn,
            l: l,
            theme: theme,
            onConnectRemembered: vpn.remembered == null
                ? null
                : () => _connect(vpn.remembered!),
            onDisconnect: vpn.disconnect,
            onPickServer: _showServerSheet,
            onImport: _importOvpn,
          ),
          const SizedBox(height: 16),

          // ---- ad blocking ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(l.protectionAdBlockTitle,
                        style: theme.textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.protectionAdBlock),
                    subtitle: Text(l.protectionAdBlockDesc),
                    value: protection.adBlockEnabled,
                    onChanged: (v) => protection.setAdBlock(v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.protectionIncognito),
                    subtitle: Text(l.protectionIncognitoDesc),
                    value: protection.incognito,
                    onChanged: (v) => protection.setIncognito(v),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.block),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.protectionBlockedTotal(protection.blockedTotal),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: protection.resetCounter,
                        child: Text(l.protectionResetCounter),
                      ),
                    ],
                  ),
                  Text(
                    l.protectionBlocklistInfo,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- honest limitations ----
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.protectionHonestNote,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- free server picker ----

  Future<void> _showServerSheet() async {
    final l = AppLocalizations.of(context)!;
    if (!_loadingServers && _servers.isEmpty) {
      await _loadServers();
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scrollController) => StatefulBuilder(
          builder: (context, setSheetState) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l.vpnServersTitle,
                          style: Theme.of(sheet).textTheme.titleMedium),
                    ),
                    IconButton(
                      tooltip: l.refresh,
                      onPressed: () async {
                        setSheetState(() => _loadingServers = true);
                        await _loadServers(force: true);
                        setSheetState(() => _loadingServers = false);
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              if (_loadingServers)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_serversError != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.vpnServersFail,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () async {
                            await _loadServers();
                            setSheetState(() {});
                          },
                          child: Text(l.retry),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_servers.isEmpty)
                Expanded(
                    child: Center(child: Text(l.vpnNoServers)))
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _servers.length,
                    itemBuilder: (context, i) {
                      final s = _servers[i];
                      final flag = _flagEmoji(s.countryCode);
                      return ListTile(
                        dense: true,
                        leading: Text(flag,
                            style: const TextStyle(fontSize: 22)),
                        title: Text(s.countryLong.isEmpty
                            ? s.hostName
                            : s.countryLong),
                        subtitle: Text(
                          '${(s.speedBps / 1000000).toStringAsFixed(1)} Mbps · '
                          'ping ${s.ping} ms · ${s.sessions} جلسة',
                        ),
                        trailing: const Icon(Icons.connect_without_contact),
                        onTap: () {
                          Navigator.of(sheet).pop();
                          _connect(VpnTarget.fromVpngate(s));
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _flagEmoji(String code) {
    if (code.length != 2) return '🌐';
    final base = 0x1F1E6;
    final a = code.toUpperCase().codeUnitAt(0) - 65;
    final b = code.toUpperCase().codeUnitAt(1) - 65;
    if (a < 0 || a > 25 || b < 0 || b > 25) return '🌐';
    return String.fromCharCode(base + a) + String.fromCharCode(base + b);
  }
}

class _VpnCard extends StatelessWidget {
  const _VpnCard({
    required this.vpn,
    required this.l,
    required this.theme,
    required this.onConnectRemembered,
    required this.onDisconnect,
    required this.onPickServer,
    required this.onImport,
  });

  final VpnService vpn;
  final AppLocalizations l;
  final ThemeData theme;
  final VoidCallback? onConnectRemembered;
  final VoidCallback onDisconnect;
  final VoidCallback onPickServer;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final connected = vpn.state == VpnState.connected;
    final connecting = vpn.isBusy;
    final unsupported = vpn.state == VpnState.unsupported;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.vpn_lock_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.vpnTitle, style: theme.textTheme.titleMedium),
              ),
              _StateChip(state: vpn.state, l: l),
            ]),
            const SizedBox(height: 8),
            if (unsupported)
              Text(l.vpnUnsupported, style: theme.textTheme.bodySmall)
            else ...[
              if (vpn.state == VpnState.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(l.vpnError,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              Text(
                connected
                    ? l.vpnConnectedTo(
                        vpn.current?.name ?? vpn.remembered?.name ?? '')
                    : connecting
                        ? l.vpnConnecting(vpn.stageText)
                        : l.vpnDisconnectedHint,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: connecting ? null : onPickServer,
                      icon: const Icon(Icons.dns_outlined),
                      label: Text(l.vpnPickServer),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: l.vpnImport,
                    onPressed: connecting ? null : onImport,
                    icon: const Icon(Icons.upload_file),
                  ),
                ],
              ),
              if (connected || vpn.state == VpnState.disconnecting) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: connecting ? null : onDisconnect,
                  icon: const Icon(Icons.link_off),
                  label: Text(l.vpnDisconnect),
                ),
              ] else if (!connected &&
                  onConnectRemembered != null &&
                  !connecting) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onConnectRemembered,
                  icon: const Icon(Icons.history),
                  label: Text(l.vpnReconnect(
                      vpn.remembered?.name ?? '')),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state, required this.l});

  final VpnState state;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      VpnState.connected => (l.vpnStateConnected, Colors.green),
      VpnState.connecting ||
      VpnState.preparing ||
      VpnState.disconnecting => (
          l.vpnStateBusy,
          Colors.orange
        ),
      VpnState.error => (l.vpnStateError, Colors.red),
      VpnState.unsupported => (l.vpnStateUnsupported, Colors.grey),
      VpnState.disconnected => (l.vpnStateOff, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
