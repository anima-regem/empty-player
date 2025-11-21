import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MiniPlayerService extends ChangeNotifier {
  static final MiniPlayerService _instance = MiniPlayerService._internal();
  
  factory MiniPlayerService() {
    return _instance;
  }
  
  MiniPlayerService._internal();
  
  VideoPlayerController? _controller;
  String? _videoTitle;
  String? _videoUrl;
  bool _isMinimized = false;
  
  VideoPlayerController? get controller => _controller;
  String? get videoTitle => _videoTitle;
  String? get videoUrl => _videoUrl;
  bool get isMinimized => _isMinimized;
  bool get hasVideo => _controller != null;
  
  void setController(VideoPlayerController controller, String videoUrl, String? videoTitle) {
    _controller = controller;
    _videoUrl = videoUrl;
    _videoTitle = videoTitle;
    _isMinimized = false;
    notifyListeners();
  }
  
  void minimize() {
    _isMinimized = true;
    notifyListeners();
  }
  
  void maximize() {
    _isMinimized = false;
    notifyListeners();
  }
  
  void clearController() {
    _controller?.dispose();
    _controller = null;
    _videoUrl = null;
    _videoTitle = null;
    _isMinimized = false;
    notifyListeners();
  }
  
  void togglePlayPause() {
    if (_controller != null) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      notifyListeners();
    }
  }
}
