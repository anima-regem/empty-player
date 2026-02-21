import 'dart:async';

import 'package:empty_player/services/mini_player_service.dart';
import 'package:empty_player/services/playback_controller_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlaybackTransportService {
  static final PlaybackTransportService instance =
      PlaybackTransportService._internal();

  static const MethodChannel _transportChannel = MethodChannel(
    'com.example.empty_player/transport',
  );

  PlaybackTransportService._internal();

  final MiniPlayerService _miniPlayerService = MiniPlayerService();

  bool _started = false;
  PlaybackControllerAdapter? _attachedController;
  String? _lastSessionId;
  int _lastPositionBucket = -1;
  bool _lastPlaying = false;
  bool _lastBuffering = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _miniPlayerService.addListener(_onMiniPlayerStateChanged);
    _transportChannel.setMethodCallHandler(_handleTransportMethodCall);
    _onMiniPlayerStateChanged();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;

    _miniPlayerService.removeListener(_onMiniPlayerStateChanged);
    _detachController();
    _transportChannel.setMethodCallHandler(null);
    await _disableTransport();
  }

  void _onMiniPlayerStateChanged() {
    _syncControllerBinding();
    _syncTransportState(force: true);
  }

  void _syncControllerBinding() {
    final currentController = _miniPlayerService.controller;
    if (identical(currentController, _attachedController)) {
      return;
    }

    _detachController();
    _attachedController = currentController;
    _attachedController?.addListener(_onControllerStateChanged);
  }

  void _detachController() {
    _attachedController?.removeListener(_onControllerStateChanged);
    _attachedController = null;
  }

  void _onControllerStateChanged() {
    _miniPlayerService.updatePlaybackSnapshot();
    _syncTransportState();
  }

  void _syncTransportState({bool force = false}) {
    final session = _miniPlayerService.session;
    final controller = _miniPlayerService.controller;
    if (session == null || controller == null) {
      unawaited(_disableTransport());
      return;
    }

    final positionBucket = session.position.inMilliseconds ~/ 1000;
    final isPlaying = controller.value.isPlaying;
    final isBuffering = controller.value.isBuffering;
    if (!force &&
        session.sessionId == _lastSessionId &&
        positionBucket == _lastPositionBucket &&
        isPlaying == _lastPlaying &&
        isBuffering == _lastBuffering) {
      return;
    }

    _lastSessionId = session.sessionId;
    _lastPositionBucket = positionBucket;
    _lastPlaying = isPlaying;
    _lastBuffering = isBuffering;

    final args = <String, dynamic>{
      'sessionId': session.sessionId,
      'title': session.title,
      'positionMs': session.position.inMilliseconds,
      'durationMs': session.duration.inMilliseconds,
      'isPlaying': isPlaying,
      'isBuffering': isBuffering,
    };

    unawaited(
      _transportChannel
          .invokeMethod<void>('updateTransportState', args)
          .catchError((Object error) {
            debugPrint('Transport sync failed: $error');
          }),
    );
  }

  Future<void> _disableTransport() async {
    _lastSessionId = null;
    _lastPositionBucket = -1;
    _lastPlaying = false;
    _lastBuffering = false;
    try {
      await _transportChannel.invokeMethod<void>('disableTransport');
    } catch (_) {
      // Ignore failures on platforms where transport controls are unsupported.
    }
  }

  Future<dynamic> _handleTransportMethodCall(MethodCall call) async {
    if (call.method != 'onTransportAction') {
      return;
    }

    final rawArgs = call.arguments;
    final args = rawArgs is Map ? Map<String, dynamic>.from(rawArgs) : const {};
    final action = (args['action'] as String?)?.trim();
    if (action == null || action.isEmpty) return;

    final controller = _miniPlayerService.controller;
    if (controller == null) return;

    switch (action) {
      case 'play':
        await controller.play();
        break;
      case 'pause':
        await controller.pause();
        break;
      case 'toggle':
        if (controller.value.isPlaying) {
          await controller.pause();
        } else {
          await controller.play();
        }
        break;
      case 'seek_forward':
        await _seekRelative(controller, 10);
        break;
      case 'seek_backward':
        await _seekRelative(controller, -10);
        break;
      case 'seek_to':
        final positionMs = (args['positionMs'] as num?)?.toInt() ?? 0;
        await controller.seekTo(Duration(milliseconds: positionMs));
        break;
      case 'stop':
      case 'close':
        await controller.pause();
        _miniPlayerService.clearController();
        break;
    }

    _miniPlayerService.updatePlaybackSnapshot();
    _syncTransportState(force: true);
  }

  Future<void> _seekRelative(
    PlaybackControllerAdapter controller,
    int seconds,
  ) async {
    final current = controller.value.position;
    final duration = controller.value.duration;
    var target = current + Duration(seconds: seconds);

    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (duration > Duration.zero && target > duration) {
      target = duration;
    }

    await controller.seekTo(target);
  }
}
