import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show SubtitleTrack;
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/player/player_service.dart';
import '../../../services/sharing/share_service.dart';

/// Speed selection sheet (0.25x .. 4x presets).
Future<void> showSpeedSheet(BuildContext context) async {
  final player = context.read<PlayerService>();
  final l = AppLocalizations.of(context)!;
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.speed),
            title: Text(l.playerSpeed),
            titleTextStyle: Theme.of(sheet).textTheme.titleMedium,
          ),
          for (final speed in AppConstants.speedPresets)
            RadioListTile<double>(
              value: speed,
              groupValue: player.rate,
              onChanged: (v) async {
                if (v != null) await player.setRate(v);
                if (sheet.mounted) Navigator.of(sheet).pop();
              },
              title: Text('${speed}x'),
            ),
        ],
      ),
    ),
  );
}

/// Sleep timer sheet: off / presets / custom minutes / end-of-video, with
/// a live countdown and a note about the gentle volume fade-out (v1.6.0).
Future<void> showSleepSheet(BuildContext context) async {
  final player = context.read<PlayerService>();
  final l = AppLocalizations.of(context)!;
  final timer = player.sleepTimer;
  final customCtrl = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: AnimatedBuilder(
        animation: timer,
        builder: (sheet, _) => ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.bedtime),
              title: Text(l.playerSleepTimer),
              titleTextStyle: Theme.of(sheet).textTheme.titleMedium,
              trailing: timer.isEndOfVideo
                  ? Text(l.playerEndOfVideo,
                      style: Theme.of(sheet).textTheme.bodySmall)
                  : timer.isActive
                      ? Text(_formatSleepRemaining(timer.remaining!),
                          style: Theme.of(sheet).textTheme.titleMedium?.copyWith(
                              color: Theme.of(sheet).colorScheme.primary,
                              fontFeatures: const [FontFeature.tabularFigures()]))
                      : null,
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l.playerOff),
              onTap: () {
                timer.cancel();
                Navigator.of(sheet).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.last_page),
              title: Text(l.playerEndOfVideo),
              selected: timer.isEndOfVideo,
              onTap: () {
                timer.startEndOfVideo();
                Navigator.of(sheet).pop();
              },
            ),
            for (final minutes in AppConstants.sleepTimerPresets)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(l.playerMinutes(minutes)),
                onTap: () {
                  timer.start(Duration(minutes: minutes));
                  Navigator.of(sheet).pop();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: customCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 3,
                      decoration: InputDecoration(
                        labelText: l.sleepCustomMinutes,
                        counterText: '',
                        suffixText: l.minutesUnit,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final v = int.tryParse(customCtrl.text.trim());
                      if (v == null || v <= 0 || v > 480) return;
                      timer.start(Duration(minutes: v));
                      Navigator.of(sheet).pop();
                    },
                    child: Text(l.sleepStart),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.volume_down,
                      size: 16, color: Theme.of(sheet).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l.sleepFadeNote,
                        style: Theme.of(sheet).textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatSleepRemaining(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Audio + subtitle track selection with external subtitle loading.
Future<void> showTracksSheet(BuildContext context) async {
  final player = context.read<PlayerService>();
  final l = AppLocalizations.of(context)!;
  final theme = Theme.of(context);

  final audioTracks = player.tracks.audio
      .where((t) => t.id != 'auto' && t.id != 'no')
      .toList();
  final subtitleTracks = player.tracks.subtitle
      .where((t) => t.id != 'auto' && t.id != 'no')
      .toList();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: DefaultTabController(
        length: 2,
        child: SizedBox(
          height: 420,
          child: Column(
            children: [
              TabBar(tabs: [
                Tab(text: l.playerAudioTrack),
                Tab(text: l.playerSubtitleTrack),
              ]),
              Expanded(
                child: TabBarView(
                  children: [
                    // Audio tracks
                    if (audioTracks.isEmpty)
                      _Hint(l.playerNoAudioTracks)
                    else
                      ListView(
                        children: [
                          for (final t in audioTracks)
                            RadioListTile<String>(
                              value: t.id,
                              groupValue: player.audioTrack.id,
                              title: Text(t.title ?? '?'),
                              onChanged: (_) async {
                                await player.selectAudioTrack(t);
                                if (sheet.mounted) Navigator.of(sheet).pop();
                              },
                            ),
                        ],
                      ),
                    // Subtitle tracks
                    ListView(
                      children: [
                        RadioListTile<String>(
                          value: 'off',
                          groupValue: player.subtitleTrack.id == 'no' ? 'off' : player.subtitleTrack.id,
                          title: Text(l.playerOff),
                          onChanged: (_) async {
                            await player.selectSubtitleTrack(
                                SubtitleTrack.no());
                            if (sheet.mounted) Navigator.of(sheet).pop();
                          },
                        ),
                        for (final t in subtitleTracks)
                          RadioListTile<String>(
                            value: t.id,
                            groupValue: player.subtitleTrack.id,
                            title: Text(t.title ?? '?'),
                            onChanged: (_) async {
                              await player.selectSubtitleTrack(t);
                              if (sheet.mounted) Navigator.of(sheet).pop();
                            },
                          ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.add),
                          title: Text(l.playerAddSubtitle),
                          onTap: () async {
                            final path = await context
                                .read<ShareService>()
                                .pickSubtitle();
                            if (path == null) return;
                            final name = path.split('/').last.split('\\').last;
                            final ok = await player.addExternalSubtitle(path, name);
                            if (!sheet.mounted) return;
                            Navigator.of(sheet).pop();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok
                                  ? l.playerSubLoaded
                                  : l.playerSubInvalid),
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.language),
                          title: Text(l.addSubtitleUrl),
                          onTap: () {
                            Navigator.of(sheet).pop();
                            _promptSubtitleUrl(context, player);
                          },
                        ),
                        if (subtitleTracks.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              l.playerNoSubtitleTracks,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Quality/track sheet: lists video tracks (HLS variants, multi-angle) and
/// offers bitrate caps for adaptive streams. For single-quality sources it
/// states that honestly instead of faking.
Future<void> showQualitySheet(BuildContext context) async {
  final player = context.read<PlayerService>();
  final l = AppLocalizations.of(context)!;
  final videoTracks = player.videoQualityTracks;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheetState) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.high_quality_outlined),
              title: Text(l.playerQuality),
              titleTextStyle: Theme.of(sheet).textTheme.titleMedium,
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(l.qualityAuto),
              trailing: player.hlsBitrateCap == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () async {
                await player.setHlsBitrate(null);
                if (sheet.mounted) Navigator.of(sheet).pop();
              },
            ),
            for (final cap in AppConstants.hlsQualityCapsKbps)
              ListTile(
                leading: const Icon(Icons.speed),
                title: Text(l.qualityCap(cap)),
                trailing: player.hlsBitrateCap == cap
                    ? const Icon(Icons.check)
                    : null,
                onTap: () async {
                  await player.setHlsBitrate(cap);
                  if (sheet.mounted) Navigator.of(sheet).pop();
                },
              ),
            if (videoTracks.length > 1) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(l.playerVideoTrack),
              ),
              for (final t in videoTracks)
                RadioListTile<String>(
                  value: t.id,
                  groupValue: player.videoTrack.id,
                  title: Text(t.title ?? '?'),
                  onChanged: (_) async {
                    await player.selectVideoTrack(t);
                    if (sheet.mounted) Navigator.of(sheet).pop();
                  },
                ),
            ] else
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l.playerSingleQuality),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Prompts for a remote subtitle URL (SRT/VTT over HTTP/S) and loads it.
Future<void> _promptSubtitleUrl(
    BuildContext context, PlayerService player) async {
  final l = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l.addSubtitleUrl),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(hintText: l.subtitleUrlHint),
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
  final url = controller.text.trim();
  if (url.isEmpty) return;
  final loaded =
      await player.addExternalSubtitle(url, url.split('/').last);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(loaded ? l.subtitleAdded : l.subtitleInvalid),
  ));
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
}
