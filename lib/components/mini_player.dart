import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:empty_player/services/mini_player_service.dart';
import 'package:empty_player/pages/video_player.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final MiniPlayerService _miniPlayerService = MiniPlayerService();
  
  @override
  void initState() {
    super.initState();
    _miniPlayerService.addListener(_onPlayerStateChanged);
  }
  
  @override
  void dispose() {
    _miniPlayerService.removeListener(_onPlayerStateChanged);
    super.dispose();
  }
  
  void _onPlayerStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }
  
  void _openFullPlayer() {
    if (_miniPlayerService.videoUrl != null) {
      _miniPlayerService.maximize();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoApp(
            videoUrl: _miniPlayerService.videoUrl!,
            videoTitle: _miniPlayerService.videoTitle,
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
      return const SizedBox.shrink();
    }
    
    final controller = _miniPlayerService.controller!;
    
    return GestureDetector(
      onTap: _openFullPlayer,
      child: Container(
        height: 72,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
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
                  color: Colors.grey.shade800,
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
                      _miniPlayerService.videoTitle ?? 'Audio Playing',
                      style: GoogleFonts.lato(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    StreamBuilder(
                      stream: Stream.periodic(const Duration(milliseconds: 500)),
                      builder: (context, snapshot) {
                        final position = controller.value.position;
                        final duration = controller.value.duration;
                        return Text(
                          '${_formatDuration(position)} / ${_formatDuration(duration)}',
                          style: GoogleFonts.lato(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    // Progress bar
                    StreamBuilder(
                      stream: Stream.periodic(const Duration(milliseconds: 500)),
                      builder: (context, snapshot) {
                        final position = controller.value.position;
                        final duration = controller.value.duration;
                        final progress = duration.inMilliseconds > 0
                            ? position.inMilliseconds / duration.inMilliseconds
                            : 0.0;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade800,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            minHeight: 3,
                          ),
                        );
                      },
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
                color: Colors.grey.shade500,
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
