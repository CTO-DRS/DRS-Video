import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/media_item.dart';
import '../../state/media_actions.dart';
import 'player_screen.dart';

/// Plays [item] within [queue] context and opens the full player screen.
Future<void> openPlayerFromLibrary(
  BuildContext context,
  MediaItem item,
  List<MediaItem> queue,
) async {
  final actions = context.read<MediaActions>();
  await actions.playItem(item, queue: queue);
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PlayerScreen(item: item),
  ));
}
