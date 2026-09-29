import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/storage/preferences_service.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../services/security/pin_lock.dart';
import '../../services/security/secure_flag.dart';
import '../../services/security/vault_controller.dart';
import '../../state/library_controller.dart';
import '../../services/platform/native_channel.dart';
import '../library/media_item_menu.dart';
import '../player/play_helpers.dart';

/// The private vault (v1.10.0): hidden media behind its own PIN.
///
/// Phases:
/// 1. No PIN configured → setup flow (create + confirm).
/// 2. PIN configured, locked → numeric gate (same pad as the app lock).
/// 3. Unlocked → grid of vaulted items with play / unhide / menu.
///
/// While phase 3 is on screen the window carries FLAG_SECURE via the
/// ref-counted keeper, so screenshots, recordings and the recents
/// thumbnail can never leak the vault contents. Leaving the screen
/// (pop) locks the vault again.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  String _firstPin = '';
  bool _confirming = false;

  /// Captured while the element is alive — reading via context inside
  /// dispose() is forbidden (element is being unmounted →
  /// 'Null check operator used on a null value' crash reported from the
  /// field, which ALSO aborted the rest of dispose(): the vault never
  /// re-locked, the listener leaked and FLAG_SECURE stayed raised).
  late final VaultController _vault;

  @override
  void initState() {
    super.initState();
    _vault = context.read<VaultController>();
    _vault.addListener(_onVaultChanged);
  }

  @override
  void dispose() {
    _vault.removeListener(_onVaultChanged);
    // Lock the vault when the user leaves the screen — playback opened
    // from here pops back to this route first, so this never fires while
    // a vaulted video is still visible.
    _vault.lock();
    unawaited(SecureFlagKeeper.release(SecureFlagKeys.vault));
    super.dispose();
  }

  void _onVaultChanged() {
    if (!mounted) return;
    setState(() {});
    final vault = context.read<VaultController>();
    if (vault.isUnlocked) {
      unawaited(SecureFlagKeeper.acquire(SecureFlagKeys.vault));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(vault.needsSetup
            ? AppLocalizations.of(context)!.vaultTitle
            : (vault.isUnlocked
                ? AppLocalizations.of(context)!.vaultTitle
                : AppLocalizations.of(context)!.vaultLockedTitle)),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
        actions: [
          if (vault.isUnlocked) ...[
            IconButton(
              tooltip: AppLocalizations.of(context)!.vaultChangePin,
              icon: const Icon(Icons.password),
              onPressed: () => _changePinDialog(context, vault),
            ),
            IconButton(
              tooltip: AppLocalizations.of(context)!.vaultLockNow,
              icon: const Icon(Icons.lock),
              onPressed: vault.lock,
            ),
          ],
        ],
      ),
      body: vault.needsSetup
          ? _VaultSetup(
              confirming: _confirming,
              onPinEntered: _onSetupPin,
              onCancelConfirm: _confirming
                  ? () => setState(() {
                        _confirming = false;
                        _firstPin = '';
                      })
                  : null,
            )
          : (!vault.isUnlocked
              ? _VaultGate(controller: vault)
              : const _VaultGrid()),
    );
  }

  Future<void> _onSetupPin(String pin, _VaultSetupController ctl) async {
    final l = AppLocalizations.of(context)!;
    final vault = context.read<VaultController>();
    final prefs = context.read<PreferencesService>();
    if (!_confirming) {
      setState(() {
        _firstPin = pin;
        _confirming = true;
      });
      return;
    }
    if (pin != _firstPin) {
      setState(() {
        _confirming = false;
        _firstPin = '';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.vaultPinMismatch)));
      return;
    }
    final packed = vault.setPin(pin);
    if (packed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.vaultPinInvalid)));
      return;
    }
    prefs.vaultHash = packed;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.vaultPinCreated)));
  }

  Future<void> _changePinDialog(BuildContext context, VaultController vault) async {
    final l = AppLocalizations.of(context)!;
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l.vaultChangePin),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(labelText: l.vaultCurrentPin),
            ),
            TextField(
              controller: next,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(labelText: l.vaultNewPin),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l.ok),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = context.read<PreferencesService>();
    final packed = vault.changePin(current.text.trim(), next.text.trim());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(packed != null ? l.vaultPinChanged : l.vaultWrongPin),
    ));
    if (packed != null) prefs.vaultHash = packed;
  }
}

// ---------------------------------------------------------------------------
// Phase 1: setup
// ---------------------------------------------------------------------------

/// Callback contract handed to the setup pad: the pad collects 4 digits
/// and reports them; [VaultScreen] runs the confirm step.
typedef _SetupPinCallback = Future<void> Function(
    String pin, _VaultSetupController ctl);

class _VaultSetupController {
  void Function()? clear;
}

class _VaultSetup extends StatefulWidget {
  const _VaultSetup({
    required this.confirming,
    required this.onPinEntered,
    this.onCancelConfirm,
  });

  final bool confirming;
  final _SetupPinCallback onPinEntered;
  final VoidCallback? onCancelConfirm;

  @override
  State<_VaultSetup> createState() => _VaultSetupState();
}

class _VaultSetupState extends State<_VaultSetup> {
  String _entry = '';
  final _ctl = _VaultSetupController();

  @override
  void initState() {
    super.initState();
    _ctl.clear = () {
      if (mounted) setState(() => _entry = '');
    };
  }

  void _press(String digit) {
    if (_entry.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _entry += digit);
    if (_entry.length == 4) {
      final pin = _entry;
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        _ctl.clear?.call();
        widget.onPinEntered(pin, _ctl);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Icon(Icons.shield_outlined,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                widget.confirming ? l.vaultConfirmPin : l.vaultCreatePin,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  l.vaultSetupHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (widget.confirming && widget.onCancelConfirm != null)
                TextButton(
                  onPressed: widget.onCancelConfirm,
                  child: Text(l.cancel),
                ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _entry.length
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _pad(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pad(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', '<'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final key in row)
                  if (key.isEmpty)
                    const SizedBox(width: 76, height: 64)
                  else
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: SizedBox(
                        width: 64,
                        height: 52,
                        child: key == '<'
                            ? IconButton.filledTonal(
                                onPressed: () {
                                  if (_entry.isEmpty) return;
                                  HapticFeedback.selectionClick();
                                  setState(() => _entry =
                                      _entry.substring(0, _entry.length - 1));
                                },
                                icon:
                                    const Icon(Icons.backspace_outlined),
                              )
                            : FilledButton.tonal(
                                onPressed: () => _press(key),
                                child: Text(key,
                                    style: theme.textTheme.titleLarge),
                              ),
                      ),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 2: gate
// ---------------------------------------------------------------------------

class _VaultGate extends StatefulWidget {
  const _VaultGate({required this.controller});

  final VaultController controller;

  @override
  State<_VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<_VaultGate> {
  String _entry = '';
  String? _error;
  Timer? _ticker;

  VaultController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _c.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    setState(() {});
    if (_c.isLockedOut) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _press(String digit) {
    if (_c.isLockedOut || _entry.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry += digit;
      _error = null;
    });
    if (_entry.length == 4) _submit();
  }

  void _submit() {
    final l = AppLocalizations.of(context)!;
    final result = _c.unlock(_entry);
    if (result == UnlockResult.success) {
      setState(() => _entry = '');
      return;
    }
    setState(() {
      _entry = '';
      _error = result == UnlockResult.lockedOut ? null : l.vaultWrongPin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final remaining = _c.lockoutRemaining;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Icon(Icons.lock_outline,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(l.vaultLockedTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                remaining != null
                    ? l.vaultLockedOut(
                        remaining.inSeconds.clamp(1, 30).toInt())
                    : l.vaultEnterPin,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: remaining != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _entry.length
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: theme.textTheme.bodySmall!.copyWith(
                  color: _error != null
                      ? theme.colorScheme.error
                      : Colors.transparent,
                ),
                child: Text(_error ?? '_'),
              ),
              const SizedBox(height: 12),
              _pad(theme, remaining != null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pad(ThemeData theme, bool disabled) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', '<'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final key in row)
                  if (key.isEmpty)
                    const SizedBox(width: 76, height: 64)
                  else
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: SizedBox(
                        width: 64,
                        height: 52,
                        child: key == '<'
                            ? IconButton.filledTonal(
                                onPressed: disabled
                                    ? null
                                    : () {
                                        if (_entry.isEmpty) return;
                                        setState(() => _entry = _entry
                                            .substring(
                                                0, _entry.length - 1));
                                      },
                                icon:
                                    const Icon(Icons.backspace_outlined),
                              )
                            : FilledButton.tonal(
                                onPressed: disabled
                                    ? null
                                    : () => _press(key),
                                child: Text(key,
                                    style: theme.textTheme.titleLarge),
                              ),
                      ),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 3: unlocked grid
// ---------------------------------------------------------------------------

class _VaultGrid extends StatefulWidget {
  const _VaultGrid();

  @override
  State<_VaultGrid> createState() => _VaultGridState();
}

class _VaultGridState extends State<_VaultGrid> {
  late Future<List<MediaItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = context.read<LibraryRepository>().vaultItems();
  }

  void _reload() {
    setState(() {
      _items = context.read<LibraryRepository>().vaultItems();
    });
    context.read<LibraryController>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return FutureBuilder<List<MediaItem>>(
      future: _items,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? const <MediaItem>[];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_moon,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(l.vaultEmpty, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    l.vaultEmptyHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: 0.78,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            return _VaultCard(
              item: item,
              onChanged: _reload,
            );
          },
        );
      },
    );
  }
}

class _VaultCard extends StatelessWidget {
  const _VaultCard({required this.item, required this.onChanged});

  final MediaItem item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final thumb = item.thumbPath;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final repo = context.read<LibraryRepository>();
        final fresh = await repo.byId(item.id) ?? item;
        await openPlayerFromLibrary(context, fresh, [fresh]);
      },
      onLongPress: () => showMediaItemMenu(context, item),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumb != null && File(thumb).existsSync()
                      ? Image.file(File(thumb), fit: BoxFit.cover)
                      : ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.movie_outlined,
                              size: 40,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                  PositionedDirectional(
                    end: 4,
                    top: 4,
                    child: _SecureBadge(theme: theme),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: l.unhideFromVault,
                        icon: const Icon(Icons.visibility_outlined,
                            size: 20),
                        onPressed: () async {
                          await context
                              .read<LibraryRepository>()
                              .setHidden(item.id, false);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(l.vaultItemRestored)));
                          onChanged();
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: l.vaultRemoveForever,
                        icon: Icon(Icons.delete_outline,
                            size: 20,
                            color: theme.colorScheme.error),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (dialog) => AlertDialog(
                              title: Text(l.vaultRemoveForever),
                              content: Text(l.vaultRemoveForeverHint),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialog).pop(false),
                                  child: Text(l.cancel),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(dialog).pop(true),
                                  child: Text(l.delete),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          await NativeChannel.instance
                              .deleteUris([item.uri]);
                          await context
                              .read<LibraryRepository>()
                              .delete(item.id);
                          onChanged();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecureBadge extends StatelessWidget {
  const _SecureBadge({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.shield,
          size: 14, color: theme.colorScheme.primary),
    );
  }
}
