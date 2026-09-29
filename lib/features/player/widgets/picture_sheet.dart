import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/player/player_service.dart';

/// v1.13.0 picture calibration sheet: mpv eq channels (brightness,
/// contrast, saturation, gamma, hue), rotation cycle and zoom reset —
/// all applied live through PlayerService.
Future<void> showPictureSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => const _PictureSheet(),
  );
}

class _PictureSheet extends StatelessWidget {
  const _PictureSheet();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final player = context.read<PlayerService>();

    return SafeArea(
      child: AnimatedBuilder(
        animation: player,
        builder: (sheet, _) {
          final eq = player.videoEq;
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(l.pictureTitle, style: theme.textTheme.titleMedium),
              ),
              _channel(
                context,
                icon: Icons.brightness_6_outlined,
                label: l.pictureBrightness,
                value: eq.brightness,
                onChanged: (v) =>
                    player.setVideoEq(channel: 'brightness', value: v),
              ),
              _channel(
                context,
                icon: Icons.contrast,
                label: l.pictureContrast,
                value: eq.contrast,
                onChanged: (v) =>
                    player.setVideoEq(channel: 'contrast', value: v),
              ),
              _channel(
                context,
                icon: Icons.gradient_outlined,
                label: l.pictureSaturation,
                value: eq.saturation,
                onChanged: (v) =>
                    player.setVideoEq(channel: 'saturation', value: v),
              ),
              _channel(
                context,
                icon: Icons.blur_linear_outlined,
                label: l.pictureGamma,
                value: eq.gamma,
                onChanged: (v) => player.setVideoEq(channel: 'gamma', value: v),
              ),
              _channel(
                context,
                icon: Icons.palette_outlined,
                label: l.pictureHue,
                value: eq.hue,
                onChanged: (v) => player.setVideoEq(channel: 'hue', value: v),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: eq.isNeutral
                            ? null
                            : () => player.resetVideoEq(),
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: Text(l.pictureReset),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => player.cycleVideoRotate(),
                        icon: const Icon(Icons.rotate_90_degrees_ccw_outlined,
                            size: 18),
                        label: Text(
                          player.videoRotate == 0
                              ? l.pictureRotate
                              : '${player.videoRotate}°',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Zoom session state + reset (the pinch gesture drives it).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_in_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${l.pictureZoom}: '
                        '${math.pow(2, player.videoZoomPan.zoom).toStringAsFixed(2)}x',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: player.videoZoomPan.zoom == 0
                          ? null
                          : () => player.resetVideoZoomPan(),
                      child: Text(l.pictureZoomReset),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  l.pictureZoomHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _channel(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12),
          child: Icon(icon, size: 20),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(-100, 100).toDouble(),
            min: -100,
            max: 100,
            divisions: 40, // 5-unit steps
            label: value.toStringAsFixed(0),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(0),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}
