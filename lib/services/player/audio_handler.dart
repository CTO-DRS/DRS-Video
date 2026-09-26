import 'package:audio_service/audio_service.dart' as aservice;
import '../player/player_service.dart';

/// audio_service bridge: gives DRS Video a real media notification and a
/// foreground service so playback continues with the app minimized.
class DrsAudioHandler extends aservice.BaseAudioHandler
    with aservice.QueueHandler, aservice.SeekHandler {
  DrsAudioHandler(this._player);

  final PlayerService _player;

  void attach() {
    _player.addListener(_sync);
    _sync();
  }

  void _sync() {
    final playing = _player.isPlaying;
    final position = _player.position;

    playbackState.add(aservice.PlaybackState(
      controls: [
        if (playing) aservice.MediaControl.pause else aservice.MediaControl.play,
        aservice.MediaControl.skipToNext,
        aservice.MediaControl.stop,
      ],
      systemActions: const {
        aservice.MediaAction.seek,
        aservice.MediaAction.seekForward,
        aservice.MediaAction.seekBackward,
      },
      processingState: _player.isBuffering
          ? aservice.AudioProcessingState.buffering
          : aservice.AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: position,
      speed: _player.rate,
    ));
  }

  void setNowPlaying({required String id, required String title, String? album}) {
    mediaItem.add(aservice.MediaItem(
      id: id,
      title: title,
      album: album ?? 'DRS Video',
      duration: _player.duration,
    ));
  }

  @override
  Future<void> play() async => _player.resume();

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seekTo(position);

  @override
  Future<void> skipToNext() async => _player.playNext();

  @override
  Future<void> skipToPrevious() async => _player.playPrevious();
}

/// Creates the handler once with the media notification channel config.
Future<DrsAudioHandler> initAudioService(PlayerService player) async {
  return aservice.AudioService.init(
    builder: () => DrsAudioHandler(player),
    config: const aservice.AudioServiceConfig(
      androidNotificationChannelId: 'drs.video.playback',
      androidNotificationChannelName: 'DRS Video playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}
