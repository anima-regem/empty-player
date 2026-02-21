import 'package:flutter/material.dart';
import 'package:empty_player/models/media_source.dart';
import 'package:empty_player/pages/video_player.dart';
import 'package:empty_player/services/url_validation_service.dart';
import 'package:empty_player/ui/app_theme_tokens.dart';
import 'package:empty_player/ui/layout_system.dart';
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
    final validation = UrlValidationService.validateNetworkUrl(
      _urlController.text.trim(),
    );
    if (!validation.isValid || validation.uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation.error ?? 'Please enter a valid URL'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoApp(
          source: MediaSource.fromInput(validation.uri.toString()),
          title: _titleController.text.trim().isEmpty
              ? validation.uri!.host
              : _titleController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = LayoutMetrics.of(context);
    return Scaffold(
      backgroundColor: AppThemeTokens.scaffold,
      appBar: AppBar(
        backgroundColor: AppThemeTokens.scaffold,
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
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(metrics.horizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // URL Input
              Text(
                'Video URL',
                style: GoogleFonts.lato(
                  color: AppThemeTokens.textSecondary,
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
                    color: AppThemeTokens.textSecondary,
                    fontSize: 15,
                  ),
                  filled: true,
                  fillColor: AppThemeTokens.surface,
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
                  color: AppThemeTokens.textSecondary,
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
                    color: AppThemeTokens.textSecondary,
                    fontSize: 15,
                  ),
                  filled: true,
                  fillColor: AppThemeTokens.surface,
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
                    backgroundColor: AppThemeTokens.accent,
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
                  color: AppThemeTokens.textSecondary,
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
                  color: AppThemeTokens.surfaceAlt,
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
              Icon(Icons.arrow_forward, color: Colors.grey.shade700, size: 16),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}
