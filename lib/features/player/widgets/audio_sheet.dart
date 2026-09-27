import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/player/audio_enhancer.dart';
import '../../../services/player/player_service.dart';

/// Audio enhancement sheet (v1.9.0): EQ presets + software gain boost.
/// Changes apply LIVE to the playing media and persist as defaults.
Future<void> showAudioSheet(BuildContext context) async {
  final player = context.read<PlayerService>();
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: AnimatedBuilder(
        animation: player,
        builder: (sheet, _) {
          final l = AppLocalizations.of(sheet)!;
          final theme = Theme.of(sheet);
          final preset = player.audioPreset;
          final boost = player.audioBoostDb;
          return ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.equalizer),
                title: Text(l.audioSheetTitle),
                titleTextStyle: theme.textTheme.titleMedium,
              ),
              for (final p in AudioPreset.values)
                RadioListTile<AudioPreset>(
                  value: p,
                  groupValue: preset,
                  onChanged: (v) async {
                    if (v != null) await player.setAudioEnhance(preset: v);
                  },
                  title: Text(_presetLabel(l, p)),
                  subtitle: Text(_presetDesc(l, p),
                      style: theme.textTheme.bodySmall),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(l.audioBoost, style: theme.textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    Text('0dB',
                        style: theme.textTheme.labelSmall),
                    Expanded(
                      child: Slider(
                        value: boost.clamp(0.0, AppConstants.maxAudioBoostDb).toDouble(),
                        min: 0,
                        max: AppConstants.maxAudioBoostDb,
                        divisions:
                            AppConstants.maxAudioBoostDb.round(), // 1 dB steps
                        label: '+${boost.toStringAsFixed(0)}dB',
                        onChanged: (v) =>
                            player.setAudioEnhance(boostDb: v),
                      ),
                    ),
                    Text('+${AppConstants.maxAudioBoostDb.round()}dB',
                        style: theme.textTheme.labelSmall),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              if (boost > 9)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    l.audioBoostWarning,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(l.audioEnhanceNote,
                    style: theme.textTheme.bodySmall),
              ),
            ],
          );
        },
      ),
    ),
  );
}

String _presetLabel(AppLocalizations l, AudioPreset p) => switch (p) {
      AudioPreset.flat => l.audioPresetFlat,
      AudioPreset.bass => l.audioPresetBass,
      AudioPreset.vocal => l.audioPresetVocal,
      AudioPreset.night => l.audioPresetNight,
      AudioPreset.movie => l.audioPresetMovie,
    };

String _presetDesc(AppLocalizations l, AudioPreset p) => switch (p) {
      AudioPreset.flat => l.audioPresetFlatDesc,
      AudioPreset.bass => l.audioPresetBassDesc,
      AudioPreset.vocal => l.audioPresetVocalDesc,
      AudioPreset.night => l.audioPresetNightDesc,
      AudioPreset.movie => l.audioPresetMovieDesc,
    };
