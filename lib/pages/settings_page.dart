import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_settings_service.dart';
import '../components/loading_animation.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AppSettingsService _settings = AppSettingsService();
  bool _loading = true;

  bool _backgroundPlayback = false;
  bool _pipOnClose = true;
  double _defaultSpeed = 1.0;
  String _loadingAnimationType = 'pulsating';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settings.init();
    setState(() {
      _backgroundPlayback = _settings.backgroundPlaybackEnabled;
      _pipOnClose = _settings.pipOnCloseEnabled;
      _defaultSpeed = _settings.defaultPlaybackSpeed;
      _loadingAnimationType = _settings.loadingAnimationType;
      _loading = false;
    });
  }

  void _saveBackground(bool v) {
    setState(() => _backgroundPlayback = v);
    _settings.backgroundPlaybackEnabled = v;
  }

  void _savePip(bool v) {
    setState(() => _pipOnClose = v);
    _settings.pipOnCloseEnabled = v;
  }

  void _saveSpeed(double v) {
    setState(() => _defaultSpeed = v);
    _settings.defaultPlaybackSpeed = v;
  }

  void _saveLoadingAnimationType(String? v) {
    if (v == null) return;
    setState(() => _loadingAnimationType = v);
    _settings.loadingAnimationType = v;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.lato()),
      ),
      body: _loading
          ? const Center(child: CompactLoadingAnimation())
          : ListView(
              children: [
                _sectionHeader('Playback'),
                SwitchListTile(
                  value: _backgroundPlayback,
                  title: Text('Background Playback', style: GoogleFonts.lato()),
                  subtitle: Text('Keep audio playing when leaving the app', style: GoogleFonts.lato(fontSize: 12)),
                  onChanged: _saveBackground,
                ),
                SwitchListTile(
                  value: _pipOnClose,
                  title: Text('PiP On Close', style: GoogleFonts.lato()),
                  subtitle: Text('Enter Picture-in-Picture when leaving video page', style: GoogleFonts.lato(fontSize: 12)),
                  onChanged: _savePip,
                ),
                ListTile(
                  title: Text('Default Speed', style: GoogleFonts.lato()),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Slider(
                        value: _defaultSpeed,
                        min: 0.25,
                        max: 3.0,
                        divisions: 11, // 0.25 increments up to 3.0
                        label: _defaultSpeed.toStringAsFixed(2),
                        onChanged: _saveSpeed,
                      ),
                      Text('${_defaultSpeed.toStringAsFixed(2)}x', style: GoogleFonts.lato()),
                    ],
                  ),
                ),
                const Divider(),
                _sectionHeader('Appearance'),
                ListTile(
                  title: Text('Loading Animation', style: GoogleFonts.lato()),
                  subtitle: Text('Choose your preferred loading animation style', style: GoogleFonts.lato(fontSize: 12)),
                  trailing: DropdownButton<String>(
                    value: _loadingAnimationType,
                    items: const [
                      DropdownMenuItem(
                        value: 'pulsating',
                        child: Text('Pulsating Circles'),
                      ),
                      DropdownMenuItem(
                        value: 'rive',
                        child: Text('Anime Cat'),
                      ),
                    ],
                    onChanged: _saveLoadingAnimationType,
                  ),
                ),
                const Divider(),
                _sectionHeader('Advanced'),
                ListTile(
                  title: Text('Audio Tracks', style: GoogleFonts.lato()),
                  subtitle: Text('Multiple audio tracks not supported with current player.', style: GoogleFonts.lato(fontSize: 12)),
                ),
                ListTile(
                  title: Text('Subtitles', style: GoogleFonts.lato()),
                  subtitle: Text('Subtitle loading & calibration UI lives in video page.', style: GoogleFonts.lato(fontSize: 12)),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Some features are placeholders pending enhanced player integration.', style: GoogleFonts.lato(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text,
        style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
