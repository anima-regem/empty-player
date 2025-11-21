import 'package:flutter/material.dart';
import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/pages/video_player.dart';
import 'package:google_fonts/google_fonts.dart';

class VideoListPage extends StatelessWidget {
  final VideoFolder folder;

  const VideoListPage({super.key, required this.folder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () => Navigator.pop(context),
          color: Colors.white,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              folder.name,
              style: GoogleFonts.lato(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${folder.videoCount} video${folder.videoCount != 1 ? 's' : ''}',
              style: GoogleFonts.lato(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: folder.videos.length,
        itemBuilder: (context, index) {
          final video = folder.videos[index];
          return _buildVideoItem(context, video);
        },
      ),
    );
  }

  Widget _buildVideoItem(BuildContext context, VideoItem video) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoApp(
                videoUrl: video.path,
                videoTitle: video.name,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 100,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.name,
                      style: GoogleFonts.lato(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (video.duration != null) ...[
                          Icon(
                            Icons.access_time,
                            color: Colors.grey.shade600,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(video.duration!),
                            style: GoogleFonts.lato(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                        if (video.duration != null && video.size != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '•',
                              style: GoogleFonts.lato(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (video.size != null) ...[
                          Icon(
                            Icons.storage,
                            color: Colors.grey.shade600,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatFileSize(video.size!),
                            style: GoogleFonts.lato(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
