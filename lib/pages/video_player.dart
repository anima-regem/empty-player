import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:empty_player/services/app_settings_service.dart';
import 'package:empty_player/services/mini_player_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:empty_player/components/loading_animation.dart';

class VideoApp extends StatefulWidget {
  final String videoUrl;
  final String? videoTitle;

  const VideoApp({super.key, required this.videoUrl, this.videoTitle});

  @override
  State<VideoApp> createState() => _VideoAppState();
}

class _VideoAppState extends State<VideoApp> with WidgetsBindingObserver {
  late VideoPlayerController _controller;
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

  String get _videoTitle => widget.videoTitle ?? 'Video Player';
  String get _videoUrl => widget.videoUrl;

  // Global settings service
  final AppSettingsService _appSettings = AppSettingsService();
  final MiniPlayerService _miniPlayerService = MiniPlayerService();

  // Extended media settings (placeholders)
  final List<String> _audioTracks = ['Track 1'];
  int _selectedAudioTrack = 0;
  double _audioDelayMs = 0.0; // milliseconds
  bool _subtitlesEnabled = false;
  double _subtitleOffsetSeconds = 0.0; // calibration offset

  @override
  void initState() {
    super.initState();
    _initializeSettings();

    // Check if we're resuming from mini player
    final existingController = _miniPlayerService.controller;
    final isSameVideo = _miniPlayerService.videoUrl == _videoUrl;

    if (existingController != null &&
        isSameVideo &&
        existingController.value.isInitialized) {
      // Reuse existing controller from mini player
      _controller = existingController;
      setState(() {
        final size = _controller.value.size;
        _videoResolution = '${size.width.toInt()} x ${size.height.toInt()}';
        _videoDuration = _formatDuration(_controller.value.duration);
        _controller.setPlaybackSpeed(_playbackSpeed);
      });
    } else {
      // Create new controller
      _controller = VideoPlayerController.networkUrl(Uri.parse(_videoUrl))
        ..initialize()
            .then((_) {
              if (mounted) {
                setState(() {
                  // Get video metadata after initialization
                  final size = _controller.value.size;
                  _videoResolution =
                      '${size.width.toInt()} x ${size.height.toInt()}';
                  _videoDuration = _formatDuration(_controller.value.duration);
                  // Apply default playback speed from settings once initialized
                  _controller.setPlaybackSpeed(_playbackSpeed);
                });
                // Set to mini player service
                _miniPlayerService.setController(
                  _controller,
                  _videoUrl,
                  _videoTitle,
                );
              }
            })
            .catchError((error) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error loading video: $error'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            });
    }

    // Only rebuild on specific state changes, not every frame
    _controller.addListener(_onVideoStateChanged);

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

  Future<void> _initializeSettings() async {
    await _appSettings.init();
    setState(() {
      _playbackSpeed = _appSettings.defaultPlaybackSpeed;
    });
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

    // Only rebuild if critical state has changed
    final isPlaying = _controller.value.isPlaying;
    final isBuffering = _controller.value.isBuffering;

    if (isPlaying != _wasPlaying || isBuffering != _wasBuffering) {
      setState(() {
        _wasPlaying = isPlaying;
        _wasBuffering = isBuffering;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App going to background - save playback state
        _wasPlayingBeforeBackground = _controller.value.isPlaying;
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
        break;

      case AppLifecycleState.hidden:
        // App is hidden but still running
        break;
    }
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
    _resetHideTimer();
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

  Future<void> _enablePiP() async {
    if (_isPipSupported) {
      try {
        await platform.invokeMethod('enterPipMode');
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
  }

  Future<void> _openExternally() async {
    // Attempt to launch the video via an external application (system intent)
    final uri = _videoUrl.startsWith('http') || _videoUrl.startsWith('rtsp')
        ? Uri.parse(_videoUrl)
        : Uri.file(_videoUrl);
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

  @override
  Widget build(BuildContext context) {
    if (_controller.value.hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
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
        backgroundColor: Colors.black,
        body: const Center(child: CompactLoadingAnimation(color: Colors.red)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          if (didPop) return;

          // If video is playing, minimize to mini player
          if (_controller.value.isPlaying) {
            // Save controller to mini player service
            _miniPlayerService.setController(
              _controller,
              _videoUrl,
              _videoTitle,
            );
            _miniPlayerService.minimize();
            // Pop without disposing controller
            if (mounted) {
              Navigator.of(context).pop();
            }
          } else {
            // If not playing, clear mini player and pop normally
            _miniPlayerService.clearController();
            if (mounted) {
              Navigator.of(context).pop();
            }
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

            if (tapPosition < screenWidth / 3) {
              _seekRelative(-10);
              _showSeekFeedback(-10);
            } else if (tapPosition > screenWidth * 2 / 3) {
              _seekRelative(10);
              _showSeekFeedback(10);
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
                    child: VideoPlayer(_controller),
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

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
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
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    final buffered = _controller.value.buffered.isNotEmpty
        ? _controller.value.buffered.last.end
        : Duration.zero;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                      value: position.inMilliseconds.toDouble(),
                      max: duration.inMilliseconds.toDouble(),
                      activeColor: Colors.red,
                      inactiveColor: Colors.grey.withValues(alpha: 0.5),
                      secondaryTrackValue: buffered.inMilliseconds.toDouble(),
                      secondaryActiveColor: Colors.white.withValues(alpha: 0.3),
                      onChanged: (value) {
                        _controller.seekTo(
                          Duration(milliseconds: value.toInt()),
                        );
                      },
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
                _formatDuration(duration),
                style: GoogleFonts.lato(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),

        // Control Buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // Play/Pause
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

                  // Rewind 10s
                  IconButton(
                    icon: const Icon(Icons.replay_10_rounded),
                    color: Colors.white,
                    iconSize: 32,
                    onPressed: () => _seekRelative(-10),
                  ),

                  // Forward 10s
                  IconButton(
                    icon: const Icon(Icons.forward_10_rounded),
                    color: Colors.white,
                    iconSize: 32,
                    onPressed: () => _seekRelative(10),
                  ),

                  // Speed indicator
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
                  // Settings Menu
                  GestureDetector(
                    onTap: () {
                      _showSettingsDialog();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.settings_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Fullscreen Toggle
                  GestureDetector(
                    onTap: _toggleFullScreen,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isFullScreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSeekFeedback(int seconds) {
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

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
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
                      style: GoogleFonts.lato(color: Colors.grey, fontSize: 14),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showSpeedDialog();
                },
              ),
              // Audio Track option (placeholder)
              ListTile(
                leading: const Icon(
                  Icons.audiotrack_rounded,
                  color: Colors.white,
                ),
                title: Text(
                  'Audio Track',
                  style: GoogleFonts.lato(color: Colors.white),
                ),
                subtitle: Text(
                  _audioTracks[_selectedAudioTrack],
                  style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAudioTrackDialog();
                },
              ),
              // Audio Delay option
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: Colors.white),
                title: Text(
                  'Audio Delay',
                  style: GoogleFonts.lato(color: Colors.white),
                ),
                subtitle: Text(
                  '${_audioDelayMs.toStringAsFixed(0)} ms',
                  style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAudioDelayDialog();
                },
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
                  _subtitlesEnabled ? 'Enabled (no file loaded)' : 'Disabled',
                  style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
                ),
                onChanged: (v) {
                  setState(() => _subtitlesEnabled = v);
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
        );
      },
    );
  }

  void _showSpeedDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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
                      _buildInfoRow('Source', 'Network Stream'),
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

  void _showAudioTrackDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    'Audio Track',
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
            ..._audioTracks.asMap().entries.map((e) {
              final idx = e.key;
              final name = e.value;
              final selected = idx == _selectedAudioTrack;
              return ListTile(
                title: Text(
                  name,
                  style: GoogleFonts.lato(
                    color: selected ? Colors.red : Colors.white,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: selected
                    ? const Icon(Icons.check_circle_rounded, color: Colors.red)
                    : null,
                onTap: () {
                  setState(() => _selectedAudioTrack = idx);
                  Navigator.pop(context);
                  _showSettingsDialog();
                },
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showAudioDelayDialog() {
    double tempDelay = _audioDelayMs;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
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
                      'Audio Delay',
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
                      'Delay (ms)',
                      style: GoogleFonts.lato(color: Colors.grey, fontSize: 12),
                    ),
                    Slider(
                      value: tempDelay,
                      min: -1000,
                      max: 1000,
                      divisions: 40,
                      label: '${tempDelay.round()} ms',
                      onChanged: (v) => setModalState(() => tempDelay = v),
                    ),
                    Text(
                      '${tempDelay.round()} ms',
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
                            setState(() => _audioDelayMs = tempDelay);
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
    );
  }

  void _showSubtitleOffsetDialog() {
    double tempOffset = _subtitleOffsetSeconds;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
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
                      style: GoogleFonts.lato(color: Colors.grey, fontSize: 12),
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
                            setState(() => _subtitleOffsetSeconds = tempOffset);
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
    );
  }

  @override
  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _controller.removeListener(_onVideoStateChanged);
    _hideTimer?.cancel();
    _volumeIndicatorTimer?.cancel();
    _brightnessIndicatorTimer?.cancel();
    _dragDebounceTimer?.cancel();

    // Only dispose controller if not minimized to mini player
    if (!_miniPlayerService.isMinimized ||
        _miniPlayerService.controller != _controller) {
      _controller.dispose();
    }

    // Disable wakelock when leaving
    WakelockPlus.disable();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }
}
