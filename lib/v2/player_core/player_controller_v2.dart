import 'package:empty_player/models/media_source.dart';

class AudioTrack {
  final String id;
  final String label;
  final bool isSelected;

  const AudioTrack({
    required this.id,
    required this.label,
    required this.isSelected,
  });
}

class SubtitleTrack {
  final String? id;
  final String label;
  final bool isSelected;

  const SubtitleTrack({
    required this.id,
    required this.label,
    required this.isSelected,
  });
}

class PlayerSnapshot {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final double speed;
  final double volume;

  const PlayerSnapshot({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isBuffering,
    required this.isCompleted,
    required this.speed,
    required this.volume,
  });
}

abstract interface class PlayerControllerV2 {
  Stream<PlayerSnapshot> snapshots();

  Future<void> open(
    MediaSource source, {
    Duration? startAt,
    bool autoPlay = true,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);

  Future<List<AudioTrack>> getAudioTracks();
  Future<void> selectAudioTrack(String trackId);
  Future<void> setAudioDelay(Duration delay);

  Future<List<SubtitleTrack>> getSubtitleTracks();
  Future<void> selectSubtitleTrack(String? trackId);
  Future<void> setSubtitleOffset(Duration offset);
}
