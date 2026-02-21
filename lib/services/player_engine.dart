import 'package:empty_player/models/media_source.dart';
import 'package:empty_player/services/playback_controller_adapter.dart';

abstract interface class PlayerEngine {
  PlaybackControllerAdapter createController(
    MediaSource source, {
    bool autoPlay,
  });
}

class MediaKitPlayerEngine implements PlayerEngine {
  const MediaKitPlayerEngine();

  @override
  PlaybackControllerAdapter createController(
    MediaSource source, {
    bool autoPlay = true,
  }) {
    return MediaKitPlaybackControllerAdapter(
      source: source,
      autoPlay: autoPlay,
    );
  }
}
