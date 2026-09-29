import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/security/pin_lock.dart';
import '../../state/settings_controller.dart';

/// Manage the app lock: create/change/remove the PIN and choose how
/// quickly the app re-locks after leaving.
class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  String _entry = '';
  String? _error;
  // Setup flow stages: null = menu, 'new' = enter new PIN,
  // 'confirm' = repeat it, 'remove' = verify current PIN.
  String? _stage;
  String _pendingPin = '';

  static const int _pinLength = 4;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final lock = context.read<AppLockController>();
    final settings = context.read<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.appLock)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(Icons.shield_outlined,
              size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            l.appLockIntro,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (_stage == null) ..._menu(context, lock, settings, l),
          if (_stage == 'new') ..._pinEntry(l, l.appLockChoosePin, _submitNew),
          if (_stage == 'confirm') ..._pinEntry(l, l.appLockConfirmPin, _submitConfirm),
          if (_stage == 'remove') ..._pinEntry(l, l.appLockEnterCurrent, _submitRemove),
        ],
      ),
    );
  }

  List<Widget> _menu(
    BuildContext context,
    AppLockController lock,
    SettingsController settings,
    AppLocalizations l,
  ) {
    final theme = Theme.of(context);
    return [
      if (lock.hasPin) ...[
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock),
            title: Text(l.appLockEnabledTitle),
            subtitle: Text(l.appLockEnabledDesc),
          ),
        ),
        const SizedBox(height: 12),
        Text(l.appLockAutoLock, style: theme.textTheme.titleSmall),
        for (final d in AppLockDelay.values)
          RadioListTile<AppLockDelay>(
            value: d,
            groupValue: settings.appLockDelay,
            title: Text(switch (d) {
              AppLockDelay.immediate => l.appLockImmediate,
              AppLockDelay.oneMinute => l.appLockAfter1m,
              AppLockDelay.fiveMinutes => l.appLockAfter5m,
            }),
            onChanged: (v) {
              if (v != null) settings.setAppLockDelay(v);
            },
          ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => setState(() {
            _stage = 'new';
            _entry = '';
            _error = null;
          }),
          icon: const Icon(Icons.password),
          label: Text(l.appLockChangePin),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => setState(() {
            _stage = 'remove';
            _entry = '';
            _error = null;
          }),
          icon: const Icon(Icons.lock_open),
          label: Text(l.appLockRemovePin),
        ),
      ] else
        FilledButton.icon(
          onPressed: () => setState(() {
            _stage = 'new';
            _entry = '';
            _error = null;
          }),
          icon: const Icon(Icons.lock),
          label: Text(l.appLockCreatePin),
        ),
    ];
  }

  List<Widget> _pinEntry(AppLocalizations l, String title, VoidCallback onSubmit) {
    final theme = Theme.of(context);
    return [
      Text(title, style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _pinLength; i++)
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
      const SizedBox(height: 8),
      Text(
        _error ?? '',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.error),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      _pad(onSubmit),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => setState(() {
          _stage = null;
          _entry = '';
          _error = null;
        }),
        child: Text(l.cancel),
      ),
    ];
  }

  Widget _pad(VoidCallback onSubmit) {
    return Column(
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
                  const SizedBox(width: 76, height: 56)
                else
                  Padding(
                    padding: const EdgeInsets.all(5),
                    child: SizedBox(
                      width: 64,
                      height: 48,
                      child: key == '<'
                          ? IconButton.filledTonal(
                              onPressed: () => setState(() {
                                if (_entry.isNotEmpty) {
                                  _entry =
                                      _entry.substring(0, _entry.length - 1);
                                  _error = null;
                                }
                              }),
                              icon: const Icon(Icons.backspace_outlined),
                            )
                          : FilledButton.tonal(
                              onPressed: () => _press(key, onSubmit),
                              child: Text(key,
                                  style: Theme.of(context).textTheme.titleMedium),
                            ),
                    ),
                  ),
            ],
          ),
      ],
    );
  }

  void _press(String digit, VoidCallback onSubmit) {
    if (_entry.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry += digit;
      _error = null;
    });
    if (_entry.length == _pinLength) onSubmit();
  }

  void _submitNew() {
    setState(() {
      _pendingPin = _entry;
      _entry = '';
      _stage = 'confirm';
    });
  }

  void _submitConfirm() {
    final l = AppLocalizations.of(context)!;
    final lock = context.read<AppLockController>();
    final settings = context.read<SettingsController>();
    if (_entry != _pendingPin) {
      setState(() {
        _error = l.appLockPinMismatch;
        _entry = '';
        _stage = 'new';
      });
      return;
    }
    // The live controller hashes + unlocks immediately; prefs store the
    // packed fingerprint so cold boots stay locked.
    final packed = lock.setPin(_entry);
    if (packed == null) {
      setState(() {
        _error = l.appLockChoosePin;
        _entry = '';
        _stage = 'new';
      });
      return;
    }
    settings.persistAppLockHash(packed);
    if (!mounted) return;
    setState(() {
      _stage = null;
      _entry = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.appLockSaved)));
  }

  void _submitRemove() {
    final l = AppLocalizations.of(context)!;
    final lock = context.read<AppLockController>();
    final settings = context.read<SettingsController>();
    // Verified against the live controller, then wiped from prefs.
    final ok = lock.removePin(_entry);
    if (!ok) {
      setState(() {
        _error = l.lockWrongPin;
        _entry = '';
      });
      return;
    }
    settings.clearAppLockHash();
    setState(() {
      _stage = null;
      _entry = '';
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.appLockRemoved)));
  }
}
