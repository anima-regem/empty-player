import 'dart:async';

import 'package:empty_player/models/media_source.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlaybackDurationRange {
  final Duration start;
  final Duration end;

  const PlaybackDurationRange(this.start, this.end);
}

@immutable
class PlaybackControllerValue {
  final Duration duration;
  final Size size;
  final Duration position;
  final List<PlaybackDurationRange> buffered;
  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final double volume;
  final double playbackSpeed;
  final String? errorDescription;
  final bool isCompleted;

  const PlaybackControllerValue({
    required this.duration,
    this.size = Size.zero,
    this.position = Duration.zero,
    this.buffered = const <PlaybackDurationRange>[],
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.volume = 1.0,
    this.playbackSpeed = 1.0,
    this.errorDescription,
    this.isCompleted = false,
  });

  const PlaybackControllerValue.uninitialized()
    : this(duration: Duration.zero, isInitialized: false);

  const PlaybackControllerValue.erroneous(String errorDescription)
    : this(
        duration: Duration.zero,
        isInitialized: false,
        errorDescription: errorDescription,
      );

  bool get hasError => errorDescription != null;

  double get aspectRatio {
    if (!isInitialized || size.width == 0 || size.height == 0) {
      return 1.0;
    }
    final aspectRatio = size.width / size.height;
    if (aspectRatio <= 0) return 1.0;
    return aspectRatio;
  }

  PlaybackControllerValue copyWith({
    Duration? duration,
    Size? size,
    Duration? position,
    List<PlaybackDurationRange>? buffered,
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    double? volume,
    double? playbackSpeed,
    String? errorDescription,
    bool? isCompleted,
  }) {
    return PlaybackControllerValue(
      duration: duration ?? this.duration,
      size: size ?? this.size,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      volume: volume ?? this.volume,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      errorDescription: errorDescription,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

abstract class PlaybackControllerAdapter extends ChangeNotifier {
  PlaybackControllerValue get value;

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setPlaybackSpeed(double speed);

  Widget buildVideo({BoxFit fit = BoxFit.contain});
  Future<void> disposeController();
}

class MediaKitPlaybackControllerAdapter extends PlaybackControllerAdapter {
  final MediaSource source;
  final bool autoPlay;

  late final Player _player;
  late final VideoController _videoController;

  PlaybackControllerValue _value =
      const PlaybackControllerValue.uninitialized();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;
  bool _initialized = false;
  String? _lastError;

  MediaKitPlaybackControllerAdapter({
    required this.source,
    this.autoPlay = true,
  }) {
    _player = Player();
    _videoController = VideoController(_player);
    _bindPlayerStreams();
  }

  @override
  PlaybackControllerValue get value => _value;

  @override
  Future<void> initialize() async {
    try {
      await _player.open(_toMedia(source), play: autoPlay);
      _initialized = true;
      _syncValue(notify: true);
    } catch (error) {
      _lastError = error.toString();
      _value = PlaybackControllerValue.erroneous(_lastError!);
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) {
    final normalized = volume.clamp(0.0, 1.0);
    return _player.setVolume(normalized * 100.0);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) {
    final normalized = speed.clamp(0.25, 4.0);
    return _player.setRate(normalized);
  }

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) {
    return Video(
      controller: _videoController,
      fit: fit,
      controls: null,
      wakelock: false,
      pauseUponEnteringBackgroundMode: false,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        visible: false,
      ),
    );
  }

  @override
  Future<void> disposeController() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _player.dispose();
  }

  void _bindPlayerStreams() {
    _subscriptions.addAll([
      _player.stream.position.listen((_) => _syncValue()),
      _player.stream.duration.listen((_) => _syncValue()),
      _player.stream.buffer.listen((_) => _syncValue()),
      _player.stream.playing.listen((_) => _syncValue()),
      _player.stream.buffering.listen((_) => _syncValue()),
      _player.stream.rate.listen((_) => _syncValue()),
      _player.stream.volume.listen((_) => _syncValue()),
      _player.stream.width.listen((_) => _syncValue()),
      _player.stream.height.listen((_) => _syncValue()),
      _player.stream.completed.listen((_) => _syncValue()),
      _player.stream.error.listen((message) {
        _lastError = message;
        _syncValue(notify: true);
      }),
    ]);
  }

  void _syncValue({bool notify = true}) {
    if (_disposed) return;

    final state = _player.state;
    final width = state.width?.toDouble() ?? 0.0;
    final height = state.height?.toDouble() ?? 0.0;
    final size = (width > 0 && height > 0) ? Size(width, height) : Size.zero;

    _value = _value.copyWith(
      duration: state.duration,
      position: state.position,
      buffered: <PlaybackDurationRange>[
        PlaybackDurationRange(Duration.zero, state.buffer),
      ],
      isInitialized: _initialized,
      isPlaying: state.playing,
      isBuffering: state.buffering,
      volume: (state.volume / 100.0).clamp(0.0, 1.0),
      playbackSpeed: state.rate,
      size: size,
      errorDescription: _lastError,
      isCompleted: state.completed,
    );

    if (notify) {
      notifyListeners();
    }
  }

  static Media _toMedia(MediaSource source) {
    if (source is NetworkMediaSource) {
      return Media(source.uri.toString(), httpHeaders: source.headers);
    }
    if (source is ContentMediaSource) {
      return Media(source.uri.toString());
    }
    if (source is FileMediaSource) {
      return Media(source.path);
    }

    throw UnsupportedError('Unsupported media source: ${source.runtimeType}');
  }
}
