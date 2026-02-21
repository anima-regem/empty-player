import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:empty_player/models/playback_session.dart';
import 'package:empty_player/services/mini_player_service.dart';
import 'package:empty_player/services/playback_controller_adapter.dart';
import 'package:empty_player/pages/video_player.dart';
import 'package:empty_player/ui/app_theme_tokens.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  static const _cardHeight = 72.0;
  static const _outerMargin = 8.0;
  final MiniPlayerService _miniPlayerService = MiniPlayerService();
  PlaybackControllerAdapter? _attachedController;

  @override
  void initState() {
    super.initState();
    _miniPlayerService.addListener(_onPlayerStateChanged);
    _syncControllerListener();
  }

  @override
  void dispose() {
    _miniPlayerService.removeListener(_onPlayerStateChanged);
    _detachControllerListener();
    super.dispose();
  }

  void _onPlayerStateChanged() {
    _syncControllerListener();
    if (mounted) {
      setState(() {});
    }
  }

  void _onControllerUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncControllerListener() {
    final controller = _miniPlayerService.controller;
    if (identical(controller, _attachedController)) {
      return;
    }
    _detachControllerListener();
    _attachedController = controller;
    _attachedController?.addListener(_onControllerUpdated);
  }

  void _detachControllerListener() {
    _attachedController?.removeListener(_onControllerUpdated);
    _attachedController = null;
  }

  void _openFullPlayer() {
    final session = _miniPlayerService.session;
    if (session != null) {
      _miniPlayerService.maximize();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoApp(
            source: session.source,
            title: session.title,
            start: PlaybackStart(position: session.position),
          ),
        ),
      );
    }
  }

  void _closePlayer() {
    _miniPlayerService.clearController();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_miniPlayerService.hasVideo || !_miniPlayerService.isMinimized) {
      _miniPlayerService.setLayoutState(MiniPlayerLayoutState.hidden);
      return const SizedBox.shrink();
    }

    final controller = _miniPlayerService.controller!;
    final session = _miniPlayerService.session!;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final reservedInset = (_outerMargin * 2) + _cardHeight + safeBottom;
    _miniPlayerService.setLayoutState(
      MiniPlayerLayoutState(
        isVisible: true,
        reservedBottomInset: reservedInset,
      ),
    );

    return GestureDetector(
      onTap: _openFullPlayer,
      child: Container(
        height: _cardHeight,
        margin: const EdgeInsets.all(_outerMargin),
        decoration: BoxDecoration(
          color: AppThemeTokens.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Album art / placeholder
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppThemeTokens.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Colors.white54,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              // Title and progress
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      session.title,
                      style: GoogleFonts.lato(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDuration(controller.value.position)} / '
                      '${_formatDuration(controller.value.duration)}',
                      style: GoogleFonts.lato(
                        color: AppThemeTokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: controller.value.duration.inMilliseconds > 0
                            ? controller.value.position.inMilliseconds /
                                  controller.value.duration.inMilliseconds
                            : 0.0,
                        backgroundColor: AppThemeTokens.surface,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppThemeTokens.accent,
                        ),
                        minHeight: 3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Play/Pause button
              IconButton(
                onPressed: () {
                  _miniPlayerService.togglePlayPause();
                },
                icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 28,
                ),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                ),
              ),
              // Close button
              IconButton(
                onPressed: _closePlayer,
                icon: const Icon(Icons.close_rounded, size: 24),
                color: AppThemeTokens.textSecondary,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
