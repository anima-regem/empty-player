import 'package:empty_player/models/media_source.dart';

class PlaybackStart {
  final Duration? position;
  final bool autoPlay;

  const PlaybackStart({this.position, this.autoPlay = true});
}

class PlaybackSession {
  final String sessionId;
  final MediaSource source;
  final String title;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isMinimized;

  const PlaybackSession({
    required this.sessionId,
    required this.source,
    required this.title,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isMinimized = false,
  });

  PlaybackSession copyWith({
    String? sessionId,
    MediaSource? source,
    String? title,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isMinimized,
  }) {
    return PlaybackSession(
      sessionId: sessionId ?? this.sessionId,
      source: source ?? this.source,
      title: title ?? this.title,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isMinimized: isMinimized ?? this.isMinimized,
    );
  }
}

String buildPlaybackSessionId(MediaSource source) => source.toStorageKey();
