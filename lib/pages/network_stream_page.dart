import 'package:flutter/material.dart';
import 'package:empty_player/pages/video_player.dart';
import 'package:google_fonts/google_fonts.dart';

class NetworkStreamPage extends StatefulWidget {
  const NetworkStreamPage({super.key});

  @override
  State<NetworkStreamPage> createState() => _NetworkStreamPageState();
}

class _NetworkStreamPageState extends State<NetworkStreamPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _playUrl() {
    if (_urlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid URL'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoApp(
          videoUrl: _urlController.text.trim(),
          videoTitle: _titleController.text.trim().isEmpty 
              ? 'Network Stream' 
              : _titleController.text.trim(),
        ),
      ),
    );
  }

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
        title: Text(
          'Stream URL',
          style: GoogleFonts.lato(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              
              // URL Input
              Text(
                'Video URL',
                style: GoogleFonts.lato(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                style: GoogleFonts.lato(color: Colors.white, fontSize: 15),
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'https://example.com/video.mp4',
                  hintStyle: GoogleFonts.lato(
                    color: Colors.grey.shade700,
                    fontSize: 15,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade900,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Title Input
              Text(
                'Title (Optional)',
                style: GoogleFonts.lato(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                style: GoogleFonts.lato(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Video title',
                  hintStyle: GoogleFonts.lato(
                    color: Colors.grey.shade700,
                    fontSize: 15,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade900,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Play Button
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _playUrl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Play Video',
                    style: GoogleFonts.lato(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Quick URLs
              Text(
                'Sample Videos',
                style: GoogleFonts.lato(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              
              _buildQuickUrlButton(
                'Big Buck Bunny',
                'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
              ),
              const SizedBox(height: 8),
              _buildQuickUrlButton(
                'Elephant Dream',
                'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
              ),
              const SizedBox(height: 8),
              _buildQuickUrlButton(
                'For Bigger Blazes',
                'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickUrlButton(String title, String url) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _urlController.text = url;
          _titleController.text = title;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.lato(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward,
                color: Colors.grey.shade700,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
