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

/// Sleep timer sheet: off / presets / end-of-video.
Future<void> showSleepSheet(BuildContext context) async {
  final player = context.read<PlayerService>();
  final l = AppLocalizations.of(context)!;
  final timer = player.sleepTimer;
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.bedtime),
            title: Text(l.playerSleepTimer),
            titleTextStyle: Theme.of(sheet).textTheme.titleMedium,
            trailing: timer.isActive
                ? Text('${timer.remaining?.inMinutes ?? 0} min')
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
        ],
      ),
    ),
  );
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

/// Quality/track sheet: lists video tracks (HLS variants, multi-angle).
/// For single-quality sources it states that honestly instead of faking.
Future<void> showQualitySheet(BuildContext context) async {
  final player = context.read<PlayerService>();
  final l = AppLocalizations.of(context)!;
  final videoTracks =
      player.tracks.video.where((t) => t.id != 'auto' && t.id != 'no').toList();

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: Text(l.playerQuality),
            titleTextStyle: Theme.of(sheet).textTheme.titleMedium,
          ),
          if (videoTracks.isEmpty || videoTracks.length == 1)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l.playerSingleQuality),
            )
          else
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
        ],
      ),
    ),
  );
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
