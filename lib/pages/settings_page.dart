import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/app_settings_service.dart';
import '../services/update_check_service.dart';
import '../components/loading_animation.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AppSettingsService _settings = AppSettingsService();
  final UpdateCheckService _updateService = UpdateCheckService();
  bool _loading = true;
  bool _checkingUpdate = false;

  bool _backgroundPlayback = false;
  bool _pipOnClose = true;
  double _defaultSpeed = 1.0;

  String _currentVersion = '';
  String? _latestVersion;
  String? _latestReleaseUrl;
  bool? _updateAvailable;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settings.init();
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _backgroundPlayback = _settings.backgroundPlaybackEnabled;
      _pipOnClose = _settings.pipOnCloseEnabled;
      _defaultSpeed = _settings.defaultPlaybackSpeed;
      _currentVersion = packageInfo.version;
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

  Future<void> _checkForUpdates() async {
    setState(() {
      _checkingUpdate = true;
      _updateAvailable = null;
    });

    final releaseInfo = await _updateService.fetchLatestRelease();

    if (releaseInfo != null && releaseInfo['tag_name'] != null) {
      final latestTag = releaseInfo['tag_name'] as String;
      final isNewer = _updateService.isNewerVersion(_currentVersion, latestTag);

      setState(() {
        _latestVersion = latestTag;
        _latestReleaseUrl = releaseInfo['html_url'] as String?;
        _updateAvailable = isNewer;
        _checkingUpdate = false;
      });
    } else {
      setState(() {
        _checkingUpdate = false;
        _updateAvailable = null;
      });
    }
  }

  Future<void> _openReleaseUrl() async {
    if (_latestReleaseUrl != null) {
      final url = Uri.parse(_latestReleaseUrl!);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        // ignore: avoid_print
        print('Could not launch $_latestReleaseUrl');
      }
    }
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
                _sectionHeader('About'),
                ListTile(
                  title: Text('Version', style: GoogleFonts.lato()),
                  subtitle: Text(_currentVersion, style: GoogleFonts.lato(fontSize: 12)),
                ),
                ListTile(
                  title: Text('Check for Updates', style: GoogleFonts.lato()),
                  subtitle: _buildUpdateStatus(),
                  trailing: _checkingUpdate
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _checkForUpdates,
                          tooltip: 'Check for updates',
                        ),
                  onTap: _checkingUpdate ? null : _checkForUpdates,
                ),
                if (_updateAvailable == true && _latestReleaseUrl != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ElevatedButton.icon(
                      onPressed: _openReleaseUrl,
                      icon: const Icon(Icons.download),
                      label: Text('Download Update', style: GoogleFonts.lato()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
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

  Widget _buildUpdateStatus() {
    if (_checkingUpdate) {
      return Text('Checking...', style: GoogleFonts.lato(fontSize: 12));
    }

    if (_updateAvailable == null) {
      return Text('Tap to check for updates', style: GoogleFonts.lato(fontSize: 12));
    }

    if (_updateAvailable == true) {
      return Text(
        'Update available: $_latestVersion',
        style: GoogleFonts.lato(fontSize: 12, color: Colors.green),
      );
    }

    return Text(
      'You are up to date',
      style: GoogleFonts.lato(fontSize: 12, color: Colors.grey),
    );
  }
}
