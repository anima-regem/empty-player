import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static final Uri _repoUrl = Uri.parse(
    'https://github.com/anima-regem/empty-player/',
  );

  Future<void> _openRepo() async {
    if (!await launchUrl(_repoUrl, mode: LaunchMode.externalApplication)) {
      // ignore: avoid_print
      print('Could not launch $_repoUrl');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('About', style: GoogleFonts.lato())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Empty Player',
            style: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'A lightweight video player focused on stability and simplicity. Built with Flutter.',
            style: GoogleFonts.lato(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Text(
            'Features',
            style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '- Local video browsing\n- Picture-in-Picture (PiP)\n- Metadata display\n- Custom playback speed\n- Background playback toggle\n\nPlanned: subtitles, audio track selection, enhancements.',
            style: GoogleFonts.lato(fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openRepo,
            icon: const Icon(Icons.open_in_new),
            label: Text('GitHub Repository', style: GoogleFonts.lato()),
          ),
          const SizedBox(height: 24),
          Text(
            'License',
            style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'This project is open source under the Unlicense. Contributions and issues are welcome.',
            style: GoogleFonts.lato(fontSize: 14),
          ),
          const SizedBox(height: 32),
          Text(
            '© 2025 Empty Player',
            style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
