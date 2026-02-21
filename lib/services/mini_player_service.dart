import 'package:flutter/material.dart';
import 'package:empty_player/models/playback_session.dart';
import 'package:empty_player/services/playback_controller_adapter.dart';

@immutable
class MiniPlayerLayoutState {
  final bool isVisible;
  final double reservedBottomInset;

  const MiniPlayerLayoutState({
    required this.isVisible,
    required this.reservedBottomInset,
  });

  static const hidden = MiniPlayerLayoutState(
    isVisible: false,
    reservedBottomInset: 0,
  );

  @override
  bool operator ==(Object other) {
    return other is MiniPlayerLayoutState &&
        other.isVisible == isVisible &&
        other.reservedBottomInset == reservedBottomInset;
  }

  @override
  int get hashCode => Object.hash(isVisible, reservedBottomInset);
}

class MiniPlayerService extends ChangeNotifier {
  static final MiniPlayerService _instance = MiniPlayerService._internal();

  factory MiniPlayerService() {
    return _instance;
  }

  MiniPlayerService._internal();

  PlaybackControllerAdapter? _controller;
  PlaybackSession? _session;
  bool _isMinimized = false;
  MiniPlayerLayoutState _layoutState = MiniPlayerLayoutState.hidden;

  PlaybackControllerAdapter? get controller => _controller;
  PlaybackSession? get session => _session;
  String? get videoTitle => _session?.title;
  String? get videoUrl => _session?.source.rawInput;
  bool get isMinimized => _isMinimized;
  bool get hasVideo => _controller != null;
  MiniPlayerLayoutState get layoutState => _layoutState;

  void setController(
    PlaybackControllerAdapter controller,
    PlaybackSession session,
  ) {
    _controller = controller;
    _session = session.copyWith(
      position: controller.value.position,
      duration: controller.value.duration,
      isPlaying: controller.value.isPlaying,
      isMinimized: false,
    );
    _isMinimized = false;
    notifyListeners();
  }

  void minimize() {
    _isMinimized = true;
    if (_session != null && _controller != null) {
      _session = _session!.copyWith(
        isMinimized: true,
        position: _controller!.value.position,
        duration: _controller!.value.duration,
        isPlaying: _controller!.value.isPlaying,
      );
    }
    notifyListeners();
  }

  void maximize() {
    _isMinimized = false;
    if (_session != null && _controller != null) {
      _session = _session!.copyWith(
        isMinimized: false,
        position: _controller!.value.position,
        duration: _controller!.value.duration,
        isPlaying: _controller!.value.isPlaying,
      );
    }
    notifyListeners();
  }

  bool matchesSession(String sessionId) {
    return _session?.sessionId == sessionId && _controller != null;
  }

  void updatePlaybackSnapshot() {
    if (_session == null || _controller == null) return;
    _session = _session!.copyWith(
      isMinimized: _isMinimized,
      position: _controller!.value.position,
      duration: _controller!.value.duration,
      isPlaying: _controller!.value.isPlaying,
    );
    notifyListeners();
  }

  void clearController() {
    _controller?.disposeController();
    _controller = null;
    _session = null;
    _isMinimized = false;
    _layoutState = MiniPlayerLayoutState.hidden;
    notifyListeners();
  }

  void setLayoutState(MiniPlayerLayoutState state) {
    if (_layoutState == state) return;
    _layoutState = state;
    notifyListeners();
  }

  void togglePlayPause() {
    if (_controller != null) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      updatePlaybackSnapshot();
      notifyListeners();
    }
  }
}
