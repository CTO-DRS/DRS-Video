import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/player/player_service.dart';

/// A-B segment loop sheet (v1.9.0): mark start (A) / end (B) at the
/// current playback position or clear the loop. The loop itself runs in
/// [PlayerService] — this is just the control surface.
Future<void> showAbRepeatSheet(BuildContext context) async {
  final player = context.read<PlayerService>();
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: AnimatedBuilder(
        animation: player,
        builder: (sheet, _) {
          final l = AppLocalizations.of(sheet)!;
          final theme = Theme.of(sheet);
          final markers = player.abMarkers;
          final aMs = markers.aMs;
          final bMs = markers.bMs;
          return ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.repeat),
                title: Text(l.playerAbRepeat),
                titleTextStyle: theme.textTheme.titleMedium,
                subtitle: player.abActive
                    ? Text(
                        '${Formatters.duration(aMs!)} → ${Formatters.duration(bMs!)}',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600),
                      )
                    : Text(l.playerAbInactive,
                        style: theme.textTheme.bodySmall),
              ),
              ListTile(
                leading: Icon(Icons.looks_one,
                    color: aMs != null ? theme.colorScheme.primary : null),
                title: Text(l.playerAbSetStart),
                subtitle: aMs != null
                    ? Text(Formatters.duration(aMs))
                    : Text(l.playerAbSetStartHint,
                        style: theme.textTheme.bodySmall),
                onTap: () => player.setLoopA(),
              ),
              ListTile(
                leading: Icon(Icons.last_page,
                    color: player.abActive ? theme.colorScheme.primary : null),
                title: Text(l.playerAbSetEnd),
                subtitle: bMs != null
                    ? Text(Formatters.duration(bMs))
                    : Text(l.playerAbSetEndHint,
                        style: theme.textTheme.bodySmall),
                onTap: () async {
                  final ok = player.setLoopB();
                  if (!ok && sheet.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.playerAbTooShort)),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.not_interested),
                title: Text(l.playerAbClear),
                enabled: aMs != null || bMs != null,
                onTap: () {
                  player.clearAbLoop();
                  if (sheet.mounted) Navigator.of(sheet).pop();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(l.playerAbNote, style: theme.textTheme.bodySmall),
              ),
            ],
          );
        },
      ),
    ),
  );
}
