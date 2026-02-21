import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path;
import 'package:empty_player/models/media_source.dart';
import 'package:empty_player/models/playback_session.dart';
import 'package:empty_player/models/playback_state.dart';
import 'package:empty_player/models/subtitle_cue.dart';
import 'package:empty_player/services/app_settings_service.dart';
import 'package:empty_player/services/mini_player_service.dart';
import 'package:empty_player/services/playback_repository.dart';
import 'package:empty_player/services/playback_controller_adapter.dart';
import 'package:empty_player/services/player_engine.dart';
import 'package:empty_player/services/player_close_policy.dart';
import 'package:empty_player/services/subtitle_service.dart';
import 'package:empty_player/ui/app_theme_tokens.dart';
import 'package:empty_player/ui/layout_system.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:empty_player/components/loading_animation.dart';

class VideoApp extends StatefulWidget {
  final MediaSource source;
  final String title;
  final PlaybackStart? start;

  const VideoApp({
    super.key,
    required this.source,
    required this.title,
    this.start,
  });

  @override
  State<VideoApp> createState() => _VideoAppState();
}

class _VideoAppState extends State<VideoApp> with WidgetsBindingObserver {
  late PlaybackControllerAdapter _controller;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isFullScreen = false;
  double _currentVolume = 1.0;
  double _playbackSpeed = 1.0;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  Timer? _volumeIndicatorTimer;
  Timer? _brightnessIndicatorTimer;
  double _currentBrightness = 0.5;

  // Debouncing for drag gestures
  Timer? _dragDebounceTimer;
  bool _wasPlaying = false;
  bool _wasBuffering = false;

  // PiP support via platform channel
  static const platform = MethodChannel('com.example.empty_player/pip');
  bool _isPipSupported = false;
  bool _wasPlayingBeforeBackground = false;

  final List<double> _speedOptions = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  // Video metadata
  String _videoResolution = "";
  String _videoDuration = "";

  String get _videoTitle => widget.title;
  MediaSource get _source => widget.source;
  String get _sourceId => _source.toStorageKey();
  String get _videoUrl => _source.rawInput;

  // Global settings service
  final AppSettingsService _appSettings = AppSettingsService();
  final MiniPlayerService _miniPlayerService = MiniPlayerService();
  final PlaybackRepository _playbackRepository =
      SharedPrefsPlaybackRepository();
  final PlayerEngine _playerEngine = const MediaKitPlayerEngine();
  DateTime _lastStateSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastSavedPositionMs = 0;
  bool _hasRestoredStartPosition = false;
  bool _controllerDisposedExternally = false;
  bool _sessionPlayCountRecorded = false;
  bool _settingsLoaded = false;
  bool _controllerAssigned = false;
  Duration _lastUiPosition = Duration.zero;

  // Extended media settings
  bool _subtitlesEnabled = false;
  double _subtitleOffsetSeconds = 0.0; // calibration offset
  final SubtitleService _subtitleService = const SubtitleService();
  List<SubtitleCue> _subtitleCues = const <SubtitleCue>[];
  String? _subtitleFileName;
  String _activeSubtitleText = '';

  @override
  void initState() {
    super.initState();
    _initializeSettings();

    // Check if we're resuming from mini player
    final existingController = _miniPlayerService.controller;
    final isSameVideo =
        _miniPlayerService.session?.source.toStorageKey() == _sourceId;

    if (existingController != null &&
        isSameVideo &&
        existingController.value.isInitialized) {
      // Reuse existing controller from mini player
      _controller = existingController;
      _controllerAssigned = true;
      _controller.addListener(_onVideoStateChanged);
      setState(() {
        final size = _controller.value.size;
        _videoResolution = '${size.width.toInt()} x ${size.height.toInt()}';
        _videoDuration = _formatDuration(_controller.value.duration);
        _currentVolume = _controller.value.volume;
        _activeSubtitleText = _resolveCurrentSubtitle(
          _controller.value.position,
        );
      });
      unawaited(_applyPlaybackPreferencesIfReady());
    } else {
      // Create new controller
      _createController();
    }

    // Get initial brightness
    _initBrightness();

    // Initialize PiP
    _initPiP();

    // Enable wakelock to keep screen on during playback
    WakelockPlus.enable();

    // Add lifecycle observer for background playback
    WidgetsBinding.instance.addObserver(this);

    // Set up method call handler for PiP callbacks
    platform.setMethodCallHandler(_handlePlatformMethod);
  }

  Future<void> _createController() async {
    try {
      _controller = _playerEngine.createController(
        _source,
        autoPlay: widget.start?.autoPlay ?? true,
      );
      _controllerAssigned = true;
      _controller.addListener(_onVideoStateChanged);
      await _controller.initialize();

      if (!mounted) return;
      setState(() {
        final size = _controller.value.size;
        _videoResolution = '${size.width.toInt()} x ${size.height.toInt()}';
        _videoDuration = _formatDuration(_controller.value.duration);
        _currentVolume = _controller.value.volume;
        _activeSubtitleText = _resolveCurrentSubtitle(
          _controller.value.position,
        );
      });
      await _applyPlaybackPreferencesIfReady();

      await _restorePlaybackPositionIfAvailable();

      _miniPlayerService.setController(
        _controller,
        PlaybackSession(
          sessionId: buildPlaybackSessionId(_source),
          source: _source,
          title: _videoTitle,
          position: _controller.value.position,
          duration: _controller.value.duration,
          isPlaying: _controller.value.isPlaying,
          isMinimized: false,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading video: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _restorePlaybackPositionIfAvailable() async {
    if (_hasRestoredStartPosition || !_controller.value.isInitialized) return;
    _hasRestoredStartPosition = true;

    final savedState = await _playbackRepository.getState(_sourceId);
    final requestedStart = widget.start?.position;
    final targetPosition = requestedStart ?? savedState?.position;

    if (targetPosition == null || targetPosition <= Duration.zero) return;

    final duration = _controller.value.duration;
    final safeTarget = targetPosition > duration
        ? duration - const Duration(milliseconds: 500)
        : targetPosition;

    if (safeTarget > Duration.zero) {
      await _controller.seekTo(safeTarget);
    }
  }

  Future<void> _initializeSettings() async {
    await _appSettings.init();
    final defaultSpeed = _appSettings.defaultPlaybackSpeed.clamp(0.25, 4.0);
    setState(() {
      _playbackSpeed = defaultSpeed.toDouble();
      _subtitleOffsetSeconds = _appSettings.subtitleOffsetSeconds;
      _subtitlesEnabled = _appSettings.subtitlesEnabled;
      _settingsLoaded = true;
    });
    await _applyPlaybackPreferencesIfReady();
  }

  bool get _hasReadyController =>
      _controllerAssigned && _controller.value.isInitialized;

  Future<void> _applyPlaybackPreferencesIfReady() async {
    if (!_settingsLoaded || !_hasReadyController) return;
    final speed = _playbackSpeed.clamp(0.25, 4.0).toDouble();
    await _controller.setPlaybackSpeed(speed);
    if (!mounted) return;
    if ((_playbackSpeed - speed).abs() > 1e-9) {
      setState(() {
        _playbackSpeed = speed;
      });
    }
  }

  Future<dynamic> _handlePlatformMethod(MethodCall call) async {
    switch (call.method) {
      case 'onPipModeChanged':
        final bool isInPipMode = call.arguments as bool;
        debugPrint('PiP mode changed: $isInPipMode');
        // Optionally adjust UI or behavior when entering/exiting PiP
        break;
    }
  }

  Future<void> _initPiP() async {
    try {
      // Check if PiP is supported on this device (Android 8.0+)
      final bool isPipAvailable = await platform.invokeMethod('isPipAvailable');
      if (mounted) {
        setState(() {
          _isPipSupported = isPipAvailable;
        });
      }
    } catch (e) {
      debugPrint('PiP initialization error: $e');
      setState(() {
        _isPipSupported = false;
      });
    }
  }

  void _onVideoStateChanged() {
    if (!mounted) return;

    final isPlaying = _controller.value.isPlaying;
    final isBuffering = _controller.value.isBuffering;
    final position = _controller.value.position;
    final positionMovedEnough =
        (position.inMilliseconds - _lastUiPosition.inMilliseconds).abs() >= 250;
    final nextSubtitle = _resolveCurrentSubtitle(position);
    final subtitleChanged = nextSubtitle != _activeSubtitleText;

    _miniPlayerService.updatePlaybackSnapshot();
    _maybePersistPlaybackState();

    if (isPlaying != _wasPlaying ||
        isBuffering != _wasBuffering ||
        positionMovedEnough ||
        subtitleChanged) {
      setState(() {
        _wasPlaying = isPlaying;
        _wasBuffering = isBuffering;
        if (positionMovedEnough) {
          _lastUiPosition = position;
        }
        if (subtitleChanged) {
          _activeSubtitleText = nextSubtitle;
        }
      });
    }
  }

  String _resolveCurrentSubtitle(Duration position) {
    if (!_subtitlesEnabled || _subtitleCues.isEmpty) {
      return '';
    }

    final adjusted = _subtitleService.applyOffset(
      position,
      _subtitleOffsetSeconds,
    );
    final cue = _subtitleService.cueAt(_subtitleCues, adjusted);
    return cue?.text ?? '';
  }

  Future<void> _pickSubtitleFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'vtt'],
      );
      if (!mounted || result == null) return;

      final filePath = result.files.single.path;
      if (filePath == null || filePath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to access the selected file.')),
        );
        return;
      }

      final cues = await _subtitleService.parseFile(filePath);
      if (!mounted) return;
      if (cues.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No subtitle cues found in this file.')),
        );
        return;
      }

      setState(() {
        _subtitleCues = cues;
        _subtitleFileName = path.basename(filePath);
        _subtitlesEnabled = true;
        _activeSubtitleText = _resolveCurrentSubtitle(
          _controller.value.position,
        );
      });
      _appSettings.subtitlesEnabled = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded ${cues.length} subtitle cues.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load subtitles: $error')),
      );
    }
  }

  void _clearSubtitles() {
    setState(() {
      _subtitleCues = const <SubtitleCue>[];
      _subtitleFileName = null;
      _activeSubtitleText = '';
      _subtitlesEnabled = false;
    });
    _appSettings.subtitlesEnabled = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App going to background - save playback state
        _wasPlayingBeforeBackground = _controller.value.isPlaying;
        unawaited(_persistPlaybackState(force: true));
        // Respect background playback setting
        if (!_appSettings.backgroundPlaybackEnabled) {
          _controller.pause();
        }
        break;

      case AppLifecycleState.resumed:
        // App returning from background
        // Resume playback if it was playing before
        if (_wasPlayingBeforeBackground && !_controller.value.isPlaying) {
          _controller.play();
        }
        break;

      case AppLifecycleState.detached:
        // App is being terminated
        unawaited(_persistPlaybackState(force: true));
        break;

      case AppLifecycleState.hidden:
        // App is hidden but still running
        break;
    }
  }

  void _maybePersistPlaybackState() {
    if (!_controller.value.isInitialized) return;
    final positionMs = _controller.value.position.inMilliseconds;
    final now = DateTime.now();
    final crossedTimeWindow =
        now.difference(_lastStateSavedAt) >= const Duration(seconds: 5);
    final movedEnough = (positionMs - _lastSavedPositionMs).abs() >= 5000;

    if (crossedTimeWindow && movedEnough) {
      _lastStateSavedAt = now;
      _lastSavedPositionMs = positionMs;
      unawaited(_persistPlaybackState());
    }
  }

  Future<void> _persistPlaybackState({bool force = false}) async {
    if (!_controller.value.isInitialized) return;
    final positionMs = _controller.value.position.inMilliseconds;
    final durationMs = _controller.value.duration.inMilliseconds;

    if (!force && durationMs > 0 && positionMs <= 0) {
      return;
    }

    final existing = await _playbackRepository.getState(_sourceId);
    final baseCount = existing?.playCount ?? 0;
    final nextCount = _sessionPlayCountRecorded ? baseCount : baseCount + 1;
    final state = PlaybackState(
      mediaId: _sourceId,
      sourceInput: _source.rawInput,
      title: _videoTitle,
      positionMs: positionMs.clamp(0, durationMs),
      durationMs: durationMs,
      updatedAt: DateTime.now(),
      playCount: nextCount,
    );

    await _playbackRepository.saveState(state);
    await _playbackRepository.saveLastPlayed(state);
    _sessionPlayCountRecorded = true;
  }

  Future<void> _initBrightness() async {
    try {
      final brightness = await ScreenBrightness().current;
      setState(() {
        _currentBrightness = brightness;
      });
    } catch (e) {
      // Handle error
      _currentBrightness = 0.5;
    }
  }

  void _togglePlayPause() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
    _miniPlayerService.updatePlaybackSnapshot();
    _maybePersistPlaybackState();
    _resetHideTimer();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _resetHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (_controller.value.isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _seekRelative(int seconds) {
    final currentPosition = _controller.value.position;
    final targetPosition = currentPosition + Duration(seconds: seconds);
    final duration = _controller.value.duration;

    if (targetPosition < Duration.zero) {
      _controller.seekTo(Duration.zero);
    } else if (targetPosition > duration) {
      _controller.seekTo(duration);
    } else {
      _controller.seekTo(targetPosition);
    }
    _maybePersistPlaybackState();
    _resetHideTimer();
  }

  int _defaultSeekSeconds() {
    final totalMinutes = _controller.value.duration.inMinutes;
    if (totalMinutes >= 60) {
      return 20;
    }
    return 10;
  }

  void _handleVerticalDrag(double delta) {
    // Negative delta = swipe up = increase volume
    // Positive delta = swipe down = decrease volume
    final volumeChange = -delta / 300; // Adjust sensitivity
    final newVolume = (_currentVolume + volumeChange).clamp(0.0, 1.0);

    // Update volume immediately without setState
    _currentVolume = newVolume;
    _controller.setVolume(newVolume);

    // Debounce setState calls
    _dragDebounceTimer?.cancel();
    _dragDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = true;
        });
      }
    });

    // Auto-hide volume indicator
    _volumeIndicatorTimer?.cancel();
    _volumeIndicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = false;
        });
      }
    });
  }

  void _handleBrightnessDrag(double delta) async {
    // Negative delta = swipe up = increase brightness
    // Positive delta = swipe down = decrease brightness
    final brightnessChange = -delta / 300; // Adjust sensitivity
    final newBrightness = (_currentBrightness + brightnessChange).clamp(
      0.0,
      1.0,
    );

    try {
      // Update brightness immediately
      _currentBrightness = newBrightness;
      await ScreenBrightness().setScreenBrightness(newBrightness);

      // Debounce setState calls
      _dragDebounceTimer?.cancel();
      _dragDebounceTimer = Timer(const Duration(milliseconds: 50), () {
        if (mounted) {
          setState(() {
            _showBrightnessIndicator = true;
          });
        }
      });

      // Auto-hide brightness indicator
      _brightnessIndicatorTimer?.cancel();
      _brightnessIndicatorTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showBrightnessIndicator = false;
          });
        }
      });
    } catch (e) {
      // Handle error
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    });
  }

  Future<bool> _enablePiP() async {
    if (_isPipSupported) {
      try {
        final entered = await platform.invokeMethod<bool>('enterPipMode');
        return entered ?? false;
      } catch (e) {
        debugPrint('Error enabling PiP: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PiP mode not available on this device'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
    return false;
  }

  Future<void> _openExternally() async {
    // Attempt to launch the video via an external application (system intent)
    final uri = _source.uri;
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open externally'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('External open error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  PlaybackSession _buildSessionSnapshot({required bool isMinimized}) {
    return PlaybackSession(
      sessionId: buildPlaybackSessionId(_source),
      source: _source,
      title: _videoTitle,
      position: _controller.value.position,
      duration: _controller.value.duration,
      isPlaying: _controller.value.isPlaying,
      isMinimized: isMinimized,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.value.hasError) {
      return Scaffold(
        backgroundColor: AppThemeTokens.scaffold,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 20),
                Text(
                  'Failed to load video',
                  style: GoogleFonts.lato(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _controller.value.errorDescription ?? 'Unknown error',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lato(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_controller.value.isInitialized) {
      return Scaffold(
        backgroundColor: AppThemeTokens.scaffold,
        body: const Center(child: CompactLoadingAnimation(color: Colors.red)),
      );
    }

    return Scaffold(
      backgroundColor: AppThemeTokens.scaffold,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          await _persistPlaybackState(force: true);

          final closeAction = PlayerClosePolicy.resolve(
            isPlaying: _controller.value.isPlaying,
            pipOnCloseEnabled: _appSettings.pipOnCloseEnabled,
            pipSupported: _isPipSupported,
          );

          if (closeAction == PlayerCloseAction.close) {
            if (_miniPlayerService.controller == _controller) {
              _controllerDisposedExternally = true;
            }
            _miniPlayerService.clearController();
          } else if (closeAction == PlayerCloseAction.enterPip) {
            final enteredPip = await _enablePiP();
            _miniPlayerService.setController(
              _controller,
              _buildSessionSnapshot(isMinimized: false),
            );
            if (!enteredPip) {
              _miniPlayerService.minimize();
            } else {
              _miniPlayerService.maximize();
            }
          } else {
            _miniPlayerService.setController(
              _controller,
              _buildSessionSnapshot(isMinimized: true),
            );
            _miniPlayerService.minimize();
          }

          if (navigator.mounted) {
            navigator.pop();
          }
        },
        child: GestureDetector(
          onTapDown: (details) {
            final size = MediaQuery.of(context).size;
            final tapPosition = details.globalPosition;

            // Don't toggle controls if tapping in the bottom 150px (control area) or top 80px (top bar)
            if (tapPosition.dy > size.height - 150 || tapPosition.dy < 80) {
              return;
            }

            // Check if tap is in the center area (for play/pause button)
            if (_showControls) {
              final center = Offset(size.width / 2, size.height / 2);

              // Check if tap is within 50 pixels of center (button radius)
              final distance = (tapPosition - center).distance;

              if (distance <= 50) {
                // Tapped on center button - toggle play/pause
                _togglePlayPause();
                return;
              }
            }

            // Tapped elsewhere - toggle controls
            _toggleControls();
          },
          onVerticalDragUpdate: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            final horizontalPosition = details.globalPosition.dx;

            // Left side of screen - brightness control
            if (horizontalPosition < screenWidth / 2) {
              _handleBrightnessDrag(details.delta.dy);
            } else {
              // Right side of screen - volume control
              _handleVerticalDrag(details.delta.dy);
            }
          },
          onDoubleTapDown: (details) {
            final screenWidth = MediaQuery.of(context).size.width;
            final tapPosition = details.globalPosition.dx;
            final skipSeconds = _defaultSeekSeconds();

            if (tapPosition < screenWidth / 3) {
              _seekRelative(-skipSeconds);
              _showSeekFeedback(-skipSeconds);
            } else if (tapPosition > screenWidth * 2 / 3) {
              _seekRelative(skipSeconds);
              _showSeekFeedback(skipSeconds);
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Video Player with RepaintBoundary to isolate repaints
              RepaintBoundary(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: _controller.buildVideo(),
                  ),
                ),
              ),

              // Buffering Indicator
              if (_controller.value.isBuffering)
                const CompactLoadingAnimation(color: Colors.red),

              // Center Play/Pause Button (Large) - Always show when controls are visible
              if (_showControls)
                IgnorePointer(
                  child: AnimatedScale(
                    scale: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 64,
                        ),
                      ),
                    ),
                  ),
                ),

              // Brightness Indicator
              if (_showBrightnessIndicator)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  left: _showBrightnessIndicator ? 20 : -80,
                  child: AnimatedOpacity(
                    opacity: _showBrightnessIndicator ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      height: 150,
                      width: 50,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                // Background
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                // Filled brightness
                                AnimatedFractionallySizedBox(
                                  duration: const Duration(milliseconds: 100),
                                  heightFactor: _currentBrightness,
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.yellow.shade700,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          Icon(
                            _currentBrightness < 0.3
                                ? Icons.brightness_low_rounded
                                : _currentBrightness < 0.7
                                ? Icons.brightness_medium_rounded
                                : Icons.brightness_high_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          Text(
                            '${(_currentBrightness * 100).round()}%',
                            style: GoogleFonts.lato(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Volume Indicator
              if (_showVolumeIndicator)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  right: _showVolumeIndicator ? 20 : -80,
                  child: AnimatedOpacity(
                    opacity: _showVolumeIndicator ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      height: 150,
                      width: 50,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                // Background
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                // Filled volume
                                AnimatedFractionallySizedBox(
                                  duration: const Duration(milliseconds: 100),
                                  heightFactor: _currentVolume,
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Icon(
                            _currentVolume == 0
                                ? Icons.volume_off_rounded
                                : _currentVolume < 0.5
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          Text(
                            '${(_currentVolume * 100).round()}%',
                            style: GoogleFonts.lato(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // External subtitle overlay
              if (_subtitlesEnabled && _activeSubtitleText.trim().isNotEmpty)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: _subtitleBottomInset(context),
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _activeSubtitleText,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lato(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Controls Overlay
              if (_showControls)
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: _buildControls(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black54,
              Colors.transparent,
              Colors.transparent,
              Colors.black87,
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Bar
            _buildTopBar(),

            // Bottom Controls
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  double _subtitleBottomInset(BuildContext context) {
    final metrics = LayoutMetrics.of(context);
    final safeBottom = MediaQuery.of(context).padding.bottom;
    if (!_showControls) return safeBottom + 28;
    return safeBottom + (metrics.isCompact ? 170 : 122);
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.of(context).maybePop();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _videoTitle,
              style: GoogleFonts.lato(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isPipSupported) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _enablePiP,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.picture_in_picture_alt_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _openExternally,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.open_in_new_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final metrics = LayoutMetrics.of(context);
    final compact = metrics.isCompact;
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    final durationMs = duration.inMilliseconds;
    final hasSeekableDuration = durationMs > 0;
    final clampedPositionMs = hasSeekableDuration
        ? position.inMilliseconds.clamp(0, durationMs)
        : 0;
    final sliderMax = hasSeekableDuration ? durationMs.toDouble() : 1.0;
    final sliderValue = clampedPositionMs.toDouble();
    final buffered = _controller.value.buffered.isNotEmpty
        ? _controller.value.buffered.last.end
        : Duration.zero;
    final bufferedMs = hasSeekableDuration
        ? buffered.inMilliseconds.clamp(0, durationMs)
        : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress Bar
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16),
          child: Row(
            children: [
              Text(
                _formatDuration(position),
                style: GoogleFonts.lato(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Slider(
                      value: sliderValue,
                      max: sliderMax,
                      activeColor: Colors.red,
                      inactiveColor: Colors.grey.withValues(alpha: 0.5),
                      secondaryTrackValue: bufferedMs.toDouble(),
                      secondaryActiveColor: Colors.white.withValues(alpha: 0.3),
                      onChanged: hasSeekableDuration
                          ? (value) {
                              _controller.seekTo(
                                Duration(milliseconds: value.toInt()),
                              );
                            }
                          : null,
                      onChangeStart: (_) {
                        _hideTimer?.cancel();
                      },
                      onChangeEnd: (_) {
                        _resetHideTimer();
                      },
                    ),
                  ),
                ),
              ),
              Text(
                hasSeekableDuration ? _formatDuration(duration) : '--:--',
                style: GoogleFonts.lato(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),

        // Control Buttons
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 16,
            vertical: compact ? 6 : 8,
          ),
          child: compact
              ? Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_filled_rounded,
                          ),
                          color: Colors.white,
                          iconSize: 34,
                          onPressed: _togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded),
                          color: Colors.white,
                          iconSize: metrics.controlIconSize,
                          onPressed: () =>
                              _seekRelative(-_defaultSeekSeconds()),
                        ),
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded),
                          color: Colors.white,
                          iconSize: metrics.controlIconSize,
                          onPressed: () => _seekRelative(_defaultSeekSeconds()),
                        ),
                        _buildRoundActionButton(
                          icon: Icons.settings_rounded,
                          onTap: _showSettingsDialog,
                        ),
                        const SizedBox(width: 8),
                        _buildRoundActionButton(
                          icon: _isFullScreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          onTap: _toggleFullScreen,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_playbackSpeed}x',
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_filled_rounded,
                          ),
                          color: Colors.white,
                          iconSize: 36,
                          onPressed: _togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded),
                          color: Colors.white,
                          iconSize: 32,
                          onPressed: () =>
                              _seekRelative(-_defaultSeekSeconds()),
                        ),
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded),
                          color: Colors.white,
                          iconSize: 32,
                          onPressed: () => _seekRelative(_defaultSeekSeconds()),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${_playbackSpeed}x',
                            style: GoogleFonts.lato(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildRoundActionButton(
                          icon: Icons.settings_rounded,
                          onTap: _showSettingsDialog,
                        ),
                        const SizedBox(width: 8),
                        _buildRoundActionButton(
                          icon: _isFullScreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          onTap: _toggleFullScreen,
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildRoundActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  void _showSeekFeedback(int seconds) {
    unawaited(HapticFeedback.selectionClick());
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    seconds > 0
                        ? Icons.forward_10_rounded
                        : Icons.replay_10_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${seconds.abs()} seconds',
                    style: GoogleFonts.lato(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Timer(const Duration(milliseconds: 600), () {
      overlayEntry.remove();
    });
  }

  Widget _buildResponsiveSheet({
    required BuildContext context,
    required Widget child,
    double maxHeightFactor = 0.9,
  }) {
    final maxHeight = MediaQuery.of(context).size.height * maxHeightFactor;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(child: child),
      ),
    );
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return _buildResponsiveSheet(
          context: context,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Settings title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Settings',
                      style: GoogleFonts.lato(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const Divider(color: Colors.grey),
                // Playback Speed option
                ListTile(
                  leading: const Icon(Icons.speed_rounded, color: Colors.white),
                  title: Text(
                    'Playback Speed',
                    style: GoogleFonts.lato(color: Colors.white),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_playbackSpeed}x',
                        style: GoogleFonts.lato(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSpeedDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.audiotrack_rounded,
                    color: Colors.white70,
                  ),
                  title: Text(
                    'Audio Controls',
                    style: GoogleFonts.lato(color: Colors.white70),
                  ),
                  subtitle: Text(
                    'Track selection and audio delay are unavailable with the current playback engine.',
                    style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: const Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.grey,
                  ),
                  enabled: false,
                ),
                // Subtitles toggle
                SwitchListTile(
                  value: _subtitlesEnabled,
                  secondary: const Icon(
                    Icons.subtitles_rounded,
                    color: Colors.white,
                  ),
                  title: Text(
                    'Subtitles',
                    style: GoogleFonts.lato(color: Colors.white),
                  ),
                  subtitle: Text(
                    _subtitleFileName != null
                        ? (_subtitlesEnabled
                              ? 'Enabled • $_subtitleFileName'
                              : 'Loaded • Disabled')
                        : (_subtitlesEnabled
                              ? 'Enabled (no subtitle file loaded)'
                              : 'Disabled'),
                    style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _subtitlesEnabled = v;
                      _activeSubtitleText = _resolveCurrentSubtitle(
                        _controller.value.position,
                      );
                    });
                    _appSettings.subtitlesEnabled = v;
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.upload_file_rounded,
                    color: Colors.white,
                  ),
                  title: Text(
                    'Load Subtitle File',
                    style: GoogleFonts.lato(color: Colors.white),
                  ),
                  subtitle: Text(
                    _subtitleFileName ?? 'Choose .srt or .vtt',
                    style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey,
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickSubtitleFile();
                  },
                ),
                if (_subtitleFileName != null)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                    title: Text(
                      'Clear Subtitles',
                      style: GoogleFonts.lato(color: Colors.white),
                    ),
                    subtitle: Text(
                      _subtitleFileName!,
                      style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _clearSubtitles();
                    },
                  ),
                // Subtitle Offset option
                ListTile(
                  leading: const Icon(Icons.tune_rounded, color: Colors.white),
                  title: Text(
                    'Subtitle Offset',
                    style: GoogleFonts.lato(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${_subtitleOffsetSeconds.toStringAsFixed(2)} s',
                    style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSubtitleOffsetDialog();
                  },
                ),
                // Video Info option
                ListTile(
                  leading: const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white,
                  ),
                  title: Text(
                    'Video Info',
                    style: GoogleFonts.lato(color: Colors.white),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showVideoInfoDialog();
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpeedDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return _buildResponsiveSheet(
          context: context,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Speed title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _showSettingsDialog();
                        },
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Playback Speed',
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.grey),
                // Speed options
                ..._speedOptions.map((speed) {
                  final isSelected = _playbackSpeed == speed;
                  return ListTile(
                    title: Text(
                      '${speed}x',
                      style: GoogleFonts.lato(
                        color: isSelected ? Colors.red : Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.red,
                          )
                        : null,
                    onTap: () {
                      setState(() {
                        _playbackSpeed = speed;
                        _controller.setPlaybackSpeed(speed);
                      });
                      Navigator.pop(context);
                      _resetHideTimer();
                    },
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showVideoInfoDialog() {
    final currentPosition = _controller.value.position;
    final buffered = _controller.value.buffered.isNotEmpty
        ? _controller.value.buffered.last.end
        : Duration.zero;
    final bufferPercentage = _controller.value.duration.inMilliseconds > 0
        ? (buffered.inMilliseconds /
                  _controller.value.duration.inMilliseconds *
                  100)
              .toStringAsFixed(1)
        : '0.0';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Info title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _showSettingsDialog();
                        },
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Video Info',
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.grey),
                // Video information
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Title', _videoTitle),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        'Resolution',
                        _videoResolution.isEmpty
                            ? 'Loading...'
                            : _videoResolution,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        'Duration',
                        _videoDuration.isEmpty ? 'Loading...' : _videoDuration,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        'Current Position',
                        _formatDuration(currentPosition),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow('Buffered', '$bufferPercentage%'),
                      const SizedBox(height: 16),
                      _buildInfoRow('Playback Speed', '${_playbackSpeed}x'),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        'Volume',
                        '${(_currentVolume * 100).toInt()}%',
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        'Source',
                        _source is NetworkMediaSource
                            ? 'Network Stream'
                            : _source is ContentMediaSource
                            ? 'Content URI'
                            : 'Local File',
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow('URL', _videoUrl, isUrl: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isUrl = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.lato(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.lato(color: Colors.white, fontSize: 14),
          maxLines: isUrl ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  void _showSubtitleOffsetDialog() {
    double tempOffset = _subtitleOffsetSeconds;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => _buildResponsiveSheet(
          context: context,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _showSettingsDialog();
                        },
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Subtitle Offset',
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.grey),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offset (seconds)',
                        style: GoogleFonts.lato(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Slider(
                        value: tempOffset,
                        min: -5,
                        max: 5,
                        divisions: 40,
                        label: '${tempOffset.toStringAsFixed(2)} s',
                        onChanged: (v) => setModalState(() => tempOffset = v),
                      ),
                      Text(
                        '${tempOffset.toStringAsFixed(2)} s',
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _showSettingsDialog();
                            },
                            child: Text('Cancel', style: GoogleFonts.lato()),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _subtitleOffsetSeconds = tempOffset;
                                _activeSubtitleText = _resolveCurrentSubtitle(
                                  _controller.value.position,
                                );
                              });
                              _appSettings.subtitleOffsetSeconds = tempOffset;
                              Navigator.pop(context);
                              _showSettingsDialog();
                            },
                            child: Text(
                              'Save',
                              style: GoogleFonts.lato(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    unawaited(_persistPlaybackState(force: true));
    _controller.removeListener(_onVideoStateChanged);
    _hideTimer?.cancel();
    _volumeIndicatorTimer?.cancel();
    _brightnessIndicatorTimer?.cancel();
    _dragDebounceTimer?.cancel();

    // Only dispose controller if it's not retained by mini player/PiP session.
    if (!_controllerDisposedExternally &&
        _miniPlayerService.controller != _controller) {
      _controller.disposeController();
    }

    // Disable wakelock when leaving
    WakelockPlus.disable();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }
}
