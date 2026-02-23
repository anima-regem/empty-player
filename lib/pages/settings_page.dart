import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:empty_player/ui/app_theme_tokens.dart';
import 'package:empty_player/ui/layout_system.dart';
import 'package:empty_player/models/index_job_state.dart';
import 'package:empty_player/services/embedding_runtime.dart';
import 'package:empty_player/services/embedding_index_status_service.dart';
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
  final EmbeddingIndexStatusService _embeddingIndexStatusService =
      EmbeddingIndexStatusService.instance;
  bool _loading = true;
  bool _checkingUpdate = false;

  bool _backgroundPlayback = false;
  bool _pipOnClose = true;
  double _defaultSpeed = 1.0;
  EmbeddingRuntimeMode _embeddingRuntimeMode = EmbeddingRuntimeMode.auto;
  AndroidEmbeddingRuntimeStatus? _runtimeStatus;
  bool _runtimeStatusRefreshing = false;

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
    await _embeddingIndexStatusService.ensureInitialized();
    final packageInfo = await PackageInfo.fromPlatform();
    final runtimeMode = EmbeddingRuntimeMode.fromStorageValue(
      _settings.embeddingRuntimeMode,
    );
    final runtimeStatus = await _fetchRuntimeStatus(runtimeMode);
    setState(() {
      _backgroundPlayback = _settings.backgroundPlaybackEnabled;
      _pipOnClose = _settings.pipOnCloseEnabled;
      _defaultSpeed = _settings.defaultPlaybackSpeed;
      _embeddingRuntimeMode = runtimeMode;
      _runtimeStatus = runtimeStatus;
      _currentVersion = packageInfo.version;
      _loading = false;
    });
  }

  Future<AndroidEmbeddingRuntimeStatus?> _fetchRuntimeStatus(
    EmbeddingRuntimeMode mode,
  ) async {
    if (mode == EmbeddingRuntimeMode.deterministic) {
      return null;
    }
    return const AndroidOnDeviceEmbeddingRuntime().runtimeStatus();
  }

  Future<void> _refreshRuntimeStatus() async {
    if (_runtimeStatusRefreshing) return;
    setState(() {
      _runtimeStatusRefreshing = true;
    });
    final runtimeStatus = await _fetchRuntimeStatus(_embeddingRuntimeMode);
    if (!mounted) return;
    setState(() {
      _runtimeStatus = runtimeStatus;
      _runtimeStatusRefreshing = false;
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

  void _saveEmbeddingRuntimeMode(EmbeddingRuntimeMode mode) {
    setState(() => _embeddingRuntimeMode = mode);
    _settings.embeddingRuntimeMode = mode.toStorageValue();
    _embeddingIndexStatusService.requestFullRebuild();
    unawaited(_refreshRuntimeStatus());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Embedding runtime updated. Full reindex requested.'),
      ),
    );
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
    final metrics = LayoutMetrics.of(context);
    return Scaffold(
      backgroundColor: AppThemeTokens.scaffold,
      appBar: AppBar(
        backgroundColor: AppThemeTokens.scaffold,
        title: Text(
          'Settings',
          style: GoogleFonts.lato(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CompactLoadingAnimation())
          : ListView(
              padding: EdgeInsets.only(bottom: metrics.sectionSpacing + 16),
              children: [
                _sectionHeader('Playback'),
                SwitchListTile(
                  value: _backgroundPlayback,
                  title: Text('Background Playback', style: GoogleFonts.lato()),
                  subtitle: Text(
                    'Keep audio playing when leaving the app',
                    style: GoogleFonts.lato(fontSize: 12),
                  ),
                  onChanged: _saveBackground,
                ),
                SwitchListTile(
                  value: _pipOnClose,
                  title: Text('PiP On Close', style: GoogleFonts.lato()),
                  subtitle: Text(
                    'Enter Picture-in-Picture when leaving video page',
                    style: GoogleFonts.lato(fontSize: 12),
                  ),
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
                      Text(
                        '${_defaultSpeed.toStringAsFixed(2)}x',
                        style: GoogleFonts.lato(),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                _sectionHeader('About'),
                ListTile(
                  title: Text('Version', style: GoogleFonts.lato()),
                  subtitle: Text(
                    _currentVersion,
                    style: GoogleFonts.lato(fontSize: 12),
                  ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _openReleaseUrl,
                      icon: const Icon(Icons.download),
                      label: Text('Download Update', style: GoogleFonts.lato()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeTokens.accent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                const Divider(),
                _sectionHeader('Search Index'),
                ListTile(
                  title: Text('Embedding Runtime', style: GoogleFonts.lato()),
                  subtitle: Text(
                    _embeddingRuntimeDescription(_embeddingRuntimeMode),
                    style: GoogleFonts.lato(fontSize: 12),
                  ),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<EmbeddingRuntimeMode>(
                      value: _embeddingRuntimeMode,
                      onChanged: (mode) {
                        if (mode == null || mode == _embeddingRuntimeMode) {
                          return;
                        }
                        _saveEmbeddingRuntimeMode(mode);
                      },
                      items: EmbeddingRuntimeMode.values
                          .map(
                            (mode) => DropdownMenuItem<EmbeddingRuntimeMode>(
                              value: mode,
                              child: Text(
                                _embeddingRuntimeLabel(mode),
                                style: GoogleFonts.lato(),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ),
                _buildRuntimeStatusCard(),
                _buildEmbeddingIndexProgressCard(),
                const Divider(),
                _sectionHeader('Advanced'),
                ListTile(
                  title: Text('Audio Tracks', style: GoogleFonts.lato()),
                  subtitle: Text(
                    'Depends on source/player capability; unavailable options stay hidden in playback UI.',
                    style: GoogleFonts.lato(fontSize: 12),
                  ),
                ),
                ListTile(
                  title: Text('Subtitles', style: GoogleFonts.lato()),
                  subtitle: Text(
                    'Subtitle loading and offset calibration are available in the video player settings.',
                    style: GoogleFonts.lato(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Runtime status and indexing progress above reflect the current on-device search engine state.',
                    style: GoogleFonts.lato(
                      fontSize: 12,
                      color: AppThemeTokens.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildEmbeddingIndexProgressCard() {
    return ValueListenableBuilder<IndexJobState>(
      valueListenable: _embeddingIndexStatusService.state,
      builder: (context, state, _) {
        final progress = state.progress.clamp(0.0, 1.0).toDouble();
        final isRunning = state.status == IndexJobStatus.running;

        return ValueListenableBuilder<EmbeddingIndexMetadata>(
          valueListenable: _embeddingIndexStatusService.metadata,
          builder: (context, metadata, _) {
            final hasIndexedContent =
                metadata.indexedVideos > 0 ||
                metadata.indexedFrames > 0 ||
                metadata.lastRunAt != null;
            final isReady =
                state.status == IndexJobStatus.completed ||
                (state.status == IndexJobStatus.idle && hasIndexedContent);

            String headline;
            Color color = AppThemeTokens.textSecondary;
            switch (state.status) {
              case IndexJobStatus.idle:
                if (hasIndexedContent) {
                  headline = 'Embedding index ready';
                  color = Colors.green;
                } else {
                  headline = 'Not indexed yet';
                }
                break;
              case IndexJobStatus.running:
                headline = 'Indexing embeddings';
                color = AppThemeTokens.accent;
                break;
              case IndexJobStatus.completed:
                headline = 'Embedding index ready';
                color = Colors.green;
                break;
              case IndexJobStatus.failed:
                headline = 'Indexing failed';
                color = Colors.redAccent;
                break;
              case IndexJobStatus.canceled:
                headline = 'Indexing canceled';
                color = Colors.orangeAccent;
                break;
            }

            final progressLabel = isRunning
                ? '${(progress * 100).toStringAsFixed(0)}%'
                : isReady
                ? '100%'
                : '0%';

            return ListTile(
              title: Text(
                'On-device embedding index',
                style: GoogleFonts.lato(),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: GoogleFonts.lato(fontSize: 12, color: color),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: isRunning
                            ? progress
                            : isReady
                            ? 1
                            : 0,
                        minHeight: 7,
                        backgroundColor: AppThemeTokens.surfaceAlt,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isRunning
                              ? AppThemeTokens.accent
                              : isReady
                              ? Colors.green
                              : AppThemeTokens.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      progressLabel,
                      style: GoogleFonts.lato(
                        fontSize: 12,
                        color: AppThemeTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Last indexed: ${_formatDateTime(metadata.lastRunAt)}',
                      style: GoogleFonts.lato(
                        fontSize: 12,
                        color: AppThemeTokens.textSecondary,
                      ),
                    ),
                    Text(
                      'Indexed videos: ${metadata.indexedVideos} | frames: ${metadata.indexedFrames}',
                      style: GoogleFonts.lato(
                        fontSize: 12,
                        color: AppThemeTokens.textSecondary,
                      ),
                    ),
                    Text(
                      'Search-ready: ${isReady ? 'Yes' : 'No'}',
                      style: GoogleFonts.lato(
                        fontSize: 12,
                        color: isReady ? Colors.green : AppThemeTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: isRunning
                          ? null
                          : () {
                              _embeddingIndexStatusService.requestFullRebuild();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Embedding index rebuild requested.',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Rebuild embedding index'),
                    ),
                    if (state.error != null && state.error!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          state.error!,
                          style: GoogleFonts.lato(
                            fontSize: 11,
                            color: Colors.redAccent,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRuntimeStatusCard() {
    final mode = _embeddingRuntimeMode;
    final status = _runtimeStatus;

    String headline;
    Color color = AppThemeTokens.textSecondary;
    if (mode == EmbeddingRuntimeMode.deterministic) {
      headline = 'Deterministic mode active';
      color = Colors.orangeAccent;
    } else if (_runtimeStatusRefreshing && status == null) {
      headline = 'Checking runtime status...';
    } else if (status == null) {
      headline = 'Runtime status unavailable on this device.';
      color = Colors.orangeAccent;
    } else if (status.ready) {
      headline = 'On-device model runtime ready';
      color = Colors.green;
    } else {
      headline = 'On-device model runtime unavailable';
      color = Colors.redAccent;
    }

    final detailParts = <String>[];
    if (status?.runtimeName != null && status!.runtimeName!.isNotEmpty) {
      detailParts.add(status.runtimeName!);
    }
    if (status?.provider != null && status!.provider!.isNotEmpty) {
      detailParts.add(status.provider!);
    }
    if (status?.dimensions != null) {
      detailParts.add('${status!.dimensions}d');
    }
    if (status != null) {
      detailParts.add(status.quantized ? 'quantized' : 'non-quantized');
    }
    if (mode == EmbeddingRuntimeMode.deterministic) {
      detailParts.add('semantic indexing disabled');
    }

    return ListTile(
      title: Text('On-device model runtime', style: GoogleFonts.lato()),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              headline,
              style: GoogleFonts.lato(fontSize: 12, color: color),
            ),
            if (detailParts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                detailParts.join(' • '),
                style: GoogleFonts.lato(
                  fontSize: 12,
                  color: AppThemeTokens.textSecondary,
                ),
              ),
            ],
            if (status?.reason != null && status!.reason!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                status.reason!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lato(fontSize: 11, color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
      trailing: _runtimeStatusRefreshing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: 'Refresh runtime status',
              onPressed: _refreshRuntimeStatus,
              icon: const Icon(Icons.refresh_rounded),
            ),
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return 'never';
    }
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)} '
        '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
  }

  String _embeddingRuntimeLabel(EmbeddingRuntimeMode mode) {
    switch (mode) {
      case EmbeddingRuntimeMode.auto:
        return 'Auto';
      case EmbeddingRuntimeMode.androidNative:
        return 'Android Model';
      case EmbeddingRuntimeMode.deterministic:
        return 'Deterministic';
    }
  }

  String _embeddingRuntimeDescription(EmbeddingRuntimeMode mode) {
    switch (mode) {
      case EmbeddingRuntimeMode.auto:
        return 'Prefer Android multimodal model runtime; semantic features are disabled if unavailable.';
      case EmbeddingRuntimeMode.androidNative:
        return 'Require quantized Android multimodal runtime (LiteRT/ONNX+NNAPI class providers).';
      case EmbeddingRuntimeMode.deterministic:
        return 'Deterministic fallback for testing and predictable output.';
    }
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text,
        style: GoogleFonts.lato(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildUpdateStatus() {
    if (_checkingUpdate) {
      return Text('Checking...', style: GoogleFonts.lato(fontSize: 12));
    }

    if (_updateAvailable == null) {
      return Text(
        'Tap to check for updates',
        style: GoogleFonts.lato(fontSize: 12),
      );
    }

    if (_updateAvailable == true) {
      return Text(
        'Update available: $_latestVersion',
        style: GoogleFonts.lato(fontSize: 12, color: Colors.green),
      );
    }

    return Text(
      'You are up to date',
      style: GoogleFonts.lato(
        fontSize: 12,
        color: AppThemeTokens.textSecondary,
      ),
    );
  }
}
