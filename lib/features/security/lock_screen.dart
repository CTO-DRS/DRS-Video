import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/security/pin_lock.dart';

/// Full-screen PIN gate shown above the Navigator (via MaterialApp.builder)
/// whenever the app must be unlocked. Covers ALL pushed routes, including
/// the player.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.controller, required this.child});

  final AppLockController controller;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        widget.controller.onPaused();
      case AppLifecycleState.resumed:
        widget.controller.onResumed();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.hasPin || !c.isLocked) return widget.child;
    return LockScreen(controller: c);
  }
}

/// PIN entry screen: numeric pad, dots feedback, wrong-PIN shake,
/// lockout countdown after repeated failures.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller});

  final AppLockController controller;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entry = '';
  String? _error;
  Timer? _ticker;

  static const int _pinLength = 4;

  AppLockController get _c => widget.controller;

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
    setState(() {}); // lockout countdown ticks via listener + timer below
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
    if (_c.isLockedOut || _entry.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry += digit;
      _error = null;
    });
    if (_entry.length == _pinLength) {
      _submit();
    }
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context)!;
    final result = _c.unlock(_entry);
    if (result == UnlockResult.success) {
      setState(() => _entry = '');
      return;
    }
    setState(() {
      _entry = '';
      _error = result == UnlockResult.lockedOut ? null : l.lockWrongPin;
    });
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry = _entry.substring(0, _entry.length - 1);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final remaining = _c.lockoutRemaining;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_person,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(l.lockTitle, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    remaining != null
                        ? l.lockLockedOut(remaining.inSeconds.clamp(1, 30).toInt())
                        : l.lockSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: remaining != null
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedOpacity(
                    opacity: remaining != null ? 0.35 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < _pinLength; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 8),
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
                        _buildPad(theme),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPad(ThemeData theme) {
    final l = AppLocalizations.of(context)!;
    final disabled = _c.isLockedOut;
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
                                onPressed: disabled ? null : _backspace,
                                icon: const Icon(Icons.backspace_outlined),
                              )
                            : FilledButton.tonal(
                                onPressed:
                                    disabled ? null : () => _press(key),
                                child: Text(key,
                                    style: theme.textTheme.titleLarge),
                              ),
                      ),
                    ),
              ],
            ),
          const SizedBox(height: 8),
          Text(l.lockPrivacyNote,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
