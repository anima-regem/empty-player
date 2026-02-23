import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:empty_player/components/loading_animation.dart';
import 'package:empty_player/components/mini_player.dart';
import 'package:empty_player/models/media_source.dart';
import 'package:empty_player/models/playback_session.dart';
import 'package:empty_player/models/playback_state.dart';
import 'package:empty_player/models/vector_search_hit.dart';
import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/models/index_job_state.dart';
import 'package:empty_player/pages/about_page.dart';
import 'package:empty_player/pages/network_stream_page.dart';
import 'package:empty_player/pages/settings_page.dart';
import 'package:empty_player/pages/video_list_page.dart';
import 'package:empty_player/pages/video_player.dart';
import 'package:empty_player/services/app_settings_service.dart';
import 'package:empty_player/services/library_preferences_service.dart';
import 'package:empty_player/services/library_repository.dart';
import 'package:empty_player/services/mini_player_service.dart';
import 'package:empty_player/services/playback_repository.dart';
import 'package:empty_player/services/embedding_runtime.dart';
import 'package:empty_player/services/embedding_index_status_service.dart';
import 'package:empty_player/services/default_vector_index_repository.dart';
import 'package:empty_player/services/indexing_scheduler.dart';
import 'package:empty_player/services/vector_index_repository.dart';
import 'package:empty_player/services/video_semantic_search_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:empty_player/ui/app_theme_tokens.dart';
import 'package:empty_player/ui/layout_system.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

enum _HeaderMenuAction { about, refresh, stream }

enum _FolderMenuAction { open, pinToggle }

typedef EmbeddingRuntimeResolver =
    Future<EmbeddingRuntime> Function({EmbeddingRuntimeMode mode});

typedef SemanticSearchServiceBuilder =
    VideoSemanticSearchService Function({
      required EmbeddingRuntime runtime,
      required VectorIndexRepository indexRepository,
    });

class HomePage extends StatefulWidget {
  final LibraryRepository? libraryRepository;
  final PermissionGateway? permissionGateway;
  final LibraryPreferencesService? libraryPreferences;
  final PlaybackRepository? playbackRepository;
  final AppSettingsService? settingsService;
  final MiniPlayerService? miniPlayerService;
  final VectorIndexRepository? vectorIndexRepository;
  final EmbeddingRuntime? initialEmbeddingRuntime;
  final EmbeddingRuntimeResolver? embeddingRuntimeResolver;
  final SemanticSearchServiceBuilder? semanticSearchServiceBuilder;

  const HomePage({
    super.key,
    this.libraryRepository,
    this.permissionGateway,
    this.libraryPreferences,
    this.playbackRepository,
    this.settingsService,
    this.miniPlayerService,
    this.vectorIndexRepository,
    this.initialEmbeddingRuntime,
    this.embeddingRuntimeResolver,
    this.semanticSearchServiceBuilder,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final LibraryRepository _libraryRepository;
  late final PermissionGateway _permissionGateway;
  late final LibraryPreferencesService _libraryPreferences;
  late final PlaybackRepository _playbackRepository;
  late final AppSettingsService _settings;
  late final MiniPlayerService _miniPlayerService;
  late final VectorIndexRepository _vectorIndexRepository;
  late final EmbeddingRuntimeResolver _embeddingRuntimeResolver;
  late final SemanticSearchServiceBuilder _semanticSearchServiceBuilder;
  final EmbeddingIndexStatusService _embeddingIndexStatus =
      EmbeddingIndexStatusService.instance;
  late EmbeddingRuntime _embeddingRuntime;
  final TextEditingController _searchController = TextEditingController();

  late VideoSemanticSearchService _semanticSearchService;
  InProcessIndexingScheduler? _indexingScheduler;
  StreamSubscription<IndexJobState>? _indexingStateSubscription;
  Timer? _semanticDebounceTimer;
  List<String> _semanticRankedVideoIds = const [];
  Map<String, double> _semanticScoreById = const {};
  bool _semanticReady = false;
  bool _semanticIndexing = false;
  String? _semanticError;
  bool _semanticRuntimeAvailable = true;
  bool _imageSearchActive = false;
  String? _imageSearchPath;
  int _lastHandledEmbeddingCommandVersion = 0;
  final Map<String, Future<Uint8List?>> _thumbnailFutures =
      <String, Future<Uint8List?>>{};
  final Set<String> _temporaryImageSearchFiles = <String>{};

  List<VideoFolder> _folders = [];
  List<VideoItem> _allVideos = [];
  Set<String> _pinnedFolderPaths = <String>{};
  Set<String> _favoriteMediaIds = <String>{};
  PlaybackState? _lastPlayed;
  String _searchQuery = '';
  LibrarySortOption _sortOption = LibrarySortOption.nameAsc;
  bool _isLoading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    final defaultLibraryRepository = const DeviceLibraryRepository();
    _libraryRepository = widget.libraryRepository ?? defaultLibraryRepository;
    _permissionGateway =
        widget.permissionGateway ??
        (_libraryRepository is PermissionGateway
            ? _libraryRepository as PermissionGateway
            : defaultLibraryRepository);
    _libraryPreferences =
        widget.libraryPreferences ?? LibraryPreferencesService();
    _playbackRepository = widget.playbackRepository ?? playbackRepository();
    _settings = widget.settingsService ?? AppSettingsService();
    _miniPlayerService = widget.miniPlayerService ?? MiniPlayerService();
    _vectorIndexRepository =
        widget.vectorIndexRepository ?? createDefaultVectorIndexRepository();
    _embeddingRuntime =
        widget.initialEmbeddingRuntime ??
        const DeterministicSpikeEmbeddingRuntime(
          runtimeName: 'deterministic_fallback',
          dimensions: 128,
        );
    _embeddingRuntimeResolver =
        widget.embeddingRuntimeResolver ?? createEmbeddingRuntime;
    _semanticSearchServiceBuilder =
        widget.semanticSearchServiceBuilder ??
        ({
          required EmbeddingRuntime runtime,
          required VectorIndexRepository indexRepository,
        }) => VideoSemanticSearchService(
          runtime: runtime,
          indexRepository: indexRepository,
        );

    _tabController = TabController(length: 2, vsync: this);
    unawaited(_embeddingIndexStatus.ensureInitialized());
    _semanticSearchService = _semanticSearchServiceBuilder(
      runtime: _embeddingRuntime,
      indexRepository: _vectorIndexRepository,
    );
    _setupSemanticSearch();
    unawaited(_initializeEmbeddingRuntime());
    _miniPlayerService.addListener(_onMiniPlayerStateChanged);
    _initializePreferences();
    _loadVideos();
  }

  void _onMiniPlayerStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _setupSemanticSearch() {
    _indexingScheduler = InProcessIndexingScheduler(
      runIncremental: () => _runSemanticIndexing(forceRebuild: false),
      runFull: () => _runSemanticIndexing(forceRebuild: true),
    );
    _lastHandledEmbeddingCommandVersion = _embeddingIndexStatus.commandVersion;
    _embeddingIndexStatus.commands.addListener(_handleEmbeddingCommand);
    _indexingStateSubscription = _indexingScheduler!.state.listen((state) {
      if (!mounted) return;
      setState(() {
        _semanticIndexing = state.status == IndexJobStatus.running;
        _semanticReady =
            state.status == IndexJobStatus.completed || _semanticReady;
        _semanticError = state.error;
      });
      _embeddingIndexStatus.update(state);
      if (state.status == IndexJobStatus.completed &&
          _searchQuery.trim().isNotEmpty) {
        _scheduleSemanticSearch(_searchQuery);
      }
    });
  }

  Future<void> _initializeEmbeddingRuntime() async {
    await _settings.init();
    final mode = EmbeddingRuntimeMode.fromStorageValue(
      _settings.embeddingRuntimeMode,
    );
    final resolvedRuntime = await _embeddingRuntimeResolver(mode: mode);
    final runtimeAvailable = resolvedRuntime is! UnavailableEmbeddingRuntime;
    final unavailableReason = resolvedRuntime is UnavailableEmbeddingRuntime
        ? resolvedRuntime.reason
        : null;
    if (!mounted) return;
    if (resolvedRuntime.runtimeName == _embeddingRuntime.runtimeName &&
        resolvedRuntime.dimensions == _embeddingRuntime.dimensions &&
        runtimeAvailable == _semanticRuntimeAvailable) {
      return;
    }

    setState(() {
      _embeddingRuntime = resolvedRuntime;
      _semanticRuntimeAvailable = runtimeAvailable;
      _semanticReady = false;
      _semanticError = runtimeAvailable ? null : unavailableReason;
      _semanticRankedVideoIds = const [];
      _semanticScoreById = const {};
      _semanticSearchService = _semanticSearchServiceBuilder(
        runtime: _embeddingRuntime,
        indexRepository: _vectorIndexRepository,
      );
    });
    if (runtimeAvailable) {
      _triggerSemanticIndexing();
    }
  }

  void _handleEmbeddingCommand() {
    final version = _embeddingIndexStatus.commandVersion;
    if (version <= _lastHandledEmbeddingCommandVersion) {
      return;
    }
    _lastHandledEmbeddingCommandVersion = version;
    final scheduler = _indexingScheduler;
    if (scheduler != null) {
      unawaited(scheduler.scheduleFull());
    }
  }

  Future<void> _runSemanticIndexing({required bool forceRebuild}) async {
    if (!_semanticRuntimeAvailable) {
      if (mounted) {
        setState(() {
          _semanticReady = false;
          _semanticError =
              'On-device embedding runtime is unavailable on this device.';
        });
      }
      return;
    }
    if (_allVideos.isEmpty) return;
    final targetVideos = _allVideos
        .where((video) => video.path.trim().isNotEmpty)
        .toList(growable: false);

    final indexedCounts = await _semanticSearchService.indexVideos(
      videos: targetVideos,
      framesPerVideo: 8,
      maxVideos: targetVideos.length,
      candidateMultiplier: 5,
      sceneSimilarityThreshold: 0.82,
      includeTemporalAggregate: true,
      forceRebuild: forceRebuild,
      onProgress: (progress) async {
        _embeddingIndexStatus.update(
          IndexJobState(status: IndexJobStatus.running, progress: progress),
        );
      },
    );

    if (!mounted) return;
    final indexedAt = DateTime.now();
    setState(() {
      _allVideos = _allVideos
          .map((video) {
            final count = indexedCounts[video.id];
            if (count == null) return video;
            return video.copyWith(
              indexedAt: indexedAt,
              indexedFrameCount: count,
              visualIndexVersion: _embeddingRuntime.runtimeName,
            );
          })
          .toList(growable: false);
      _semanticReady = indexedCounts.isNotEmpty;
      _semanticError = null;
    });
    final indexedFrames = indexedCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    await _embeddingIndexStatus.saveMetadata(
      lastRunAt: indexedAt,
      indexedVideos: indexedCounts.length,
      indexedFrames: indexedFrames,
    );
    if (_searchQuery.trim().isNotEmpty && indexedCounts.isNotEmpty) {
      _scheduleSemanticSearch(_searchQuery);
    }
  }

  void _triggerSemanticIndexing() {
    if (!_semanticRuntimeAvailable) return;
    _indexingScheduler?.scheduleIncremental();
  }

  void _scheduleSemanticSearch(String rawQuery) {
    _semanticDebounceTimer?.cancel();
    final query = rawQuery.trim();
    if (query.isEmpty) {
      if (_semanticRankedVideoIds.isNotEmpty ||
          _semanticError != null ||
          _semanticScoreById.isNotEmpty) {
        setState(() {
          _semanticRankedVideoIds = const [];
          _semanticScoreById = const {};
          _semanticError = _semanticRuntimeAvailable
              ? null
              : 'On-device embedding runtime is unavailable on this device.';
        });
      }
      return;
    }

    if (!_semanticRuntimeAvailable) {
      setState(() {
        _semanticRankedVideoIds = const [];
        _semanticScoreById = const {};
        _semanticError =
            'On-device embedding runtime is unavailable on this device.';
      });
      return;
    }

    if (_semanticIndexing || !_semanticReady) {
      setState(() {
        _semanticRankedVideoIds = const [];
        _semanticScoreById = const {};
      });
      return;
    }

    _semanticDebounceTimer = Timer(const Duration(milliseconds: 260), () async {
      try {
        final hits = await _semanticSearchService.search(
          query,
          limit: 40,
          minScore: 0.14,
        );
        if (!mounted || _searchQuery.trim() != query) return;
        final scoreMap = _scoreMapFromHits(hits);
        setState(() {
          _semanticRankedVideoIds = hits
              .map((hit) => hit.mediaId)
              .toList(growable: false);
          _semanticScoreById = scoreMap;
          _semanticError = null;
        });
      } catch (error) {
        if (!mounted || _searchQuery.trim() != query) return;
        setState(() {
          _semanticRankedVideoIds = const [];
          _semanticScoreById = const {};
          _semanticError = error.toString();
        });
      }
    });
  }

  Map<String, double> _scoreMapFromHits(List<VectorSearchHit> hits) {
    final map = <String, double>{};
    for (final hit in hits) {
      final current = map[hit.mediaId];
      if (current == null || hit.score > current) {
        map[hit.mediaId] = hit.score;
      }
    }
    return map;
  }

  Future<void> _startImageSearch() async {
    if (!_semanticRuntimeAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Visual search is unavailable: on-device embedding runtime is not ready.',
          ),
        ),
      );
      return;
    }
    if (_semanticIndexing || !_semanticReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Embedding index is still building. Try again shortly.',
          ),
        ),
      );
      return;
    }

    final selection = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (!mounted || selection == null || selection.files.isEmpty) {
      return;
    }

    final picked = selection.files.single;
    final resolvedPath = await _resolveImagePath(picked);
    if (resolvedPath == null || resolvedPath.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read selected image.')),
      );
      return;
    }
    if (!mounted) return;
    _cleanupTempImagePath(_imageSearchPath);

    setState(() {
      _imageSearchActive = true;
      _imageSearchPath = resolvedPath;
      _searchQuery = '';
      _searchController.clear();
      _semanticError = null;
    });
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }

    try {
      final hits = await _semanticSearchService.searchByImagePath(
        resolvedPath,
        limit: 60,
        minScore: 0.12,
      );
      if (!mounted || _imageSearchPath != resolvedPath) return;
      setState(() {
        _semanticRankedVideoIds = hits
            .map((hit) => hit.mediaId)
            .toList(growable: false);
        _semanticScoreById = _scoreMapFromHits(hits);
        _semanticError = hits.isEmpty ? 'No visual matches found.' : null;
      });
    } catch (error) {
      if (!mounted || _imageSearchPath != resolvedPath) return;
      setState(() {
        _semanticRankedVideoIds = const [];
        _semanticScoreById = const {};
        _semanticError = error.toString();
      });
    }
  }

  Future<String?> _resolveImagePath(PlatformFile picked) async {
    final directPath = picked.path?.trim();
    if (directPath != null && directPath.isNotEmpty) {
      return directPath;
    }
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    final tempDir = await getTemporaryDirectory();
    final extension = (picked.extension ?? 'jpg').replaceAll('.', '').trim();
    final file = File(
      '${tempDir.path}/visual_query_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    _temporaryImageSearchFiles.add(file.path);
    return file.path;
  }

  void _clearImageSearch() {
    _cleanupTempImagePath(_imageSearchPath);
    setState(() {
      _imageSearchActive = false;
      _imageSearchPath = null;
      _semanticRankedVideoIds = const [];
      _semanticScoreById = const {};
      _semanticError = _semanticRuntimeAvailable
          ? null
          : 'On-device embedding runtime is unavailable on this device.';
    });
    if (_searchQuery.trim().isNotEmpty) {
      _scheduleSemanticSearch(_searchQuery);
    }
  }

  void _cleanupTempImagePath(String? imagePath) {
    if (imagePath == null || imagePath.trim().isEmpty) return;
    if (!_temporaryImageSearchFiles.remove(imagePath)) return;
    unawaited(_deleteTemporaryImage(imagePath));
  }

  void _cleanupAllTemporaryImageFiles() {
    final paths = _temporaryImageSearchFiles.toList(growable: false);
    _temporaryImageSearchFiles.clear();
    for (final path in paths) {
      unawaited(_deleteTemporaryImage(path));
    }
  }

  Future<void> _deleteTemporaryImage(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Ignore cleanup failures for temporary files.
    }
  }

  Future<void> _initializePreferences() async {
    final pinned = await _libraryPreferences.getPinnedFolders();
    final sort = await _libraryPreferences.getSortOption();
    final lastPlayed = await _playbackRepository.getLastPlayed();
    final favoriteIds = await _playbackRepository.getFavorites();

    if (!mounted) return;
    setState(() {
      _pinnedFolderPaths = pinned;
      _sortOption = sort;
      _lastPlayed = lastPlayed;
      _favoriteMediaIds = favoriteIds;
      _allVideos = _allVideos
          .map(
            (video) =>
                video.copyWith(isFavorite: favoriteIds.contains(video.id)),
          )
          .toList();
    });
  }

  Future<void> _loadVideos() async {
    _thumbnailFutures.clear();
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

    try {
      final hasPermission = await _permissionGateway.hasLibraryPermission();
      if (!hasPermission) {
        final status = await _permissionGateway.requestLibraryPermission();
        if (!status.isGranted) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _permissionDenied = true;
            });
            if (status.isPermanentlyDenied) {
              _showPermissionDialog();
            }
          }
          return;
        }
      }

      final result = await _libraryRepository.getAllVideos();
      final playbackStates = await _playbackRepository.getRecentStates(
        limit: 5000,
      );
      final playbackBySource = <String, PlaybackState>{
        for (final state in playbackStates) state.sourceInput: state,
      };

      if (!mounted) return;
      setState(() {
        _folders = (result['folders'] as List<VideoFolder>).toList();
        _allVideos = (result['videos'] as List<VideoItem>)
            .map(
              (video) => video.copyWith(
                lastPositionMs: playbackBySource[video.path]?.positionMs,
                lastPlayedAt: playbackBySource[video.path]?.updatedAt,
                playCount: playbackBySource[video.path]?.playCount ?? 0,
                isFavorite: _favoriteMediaIds.contains(video.id),
              ),
            )
            .toList();
        _isLoading = false;
        _permissionDenied = false;
      });
      _triggerSemanticIndexing();
    } catch (e) {
      debugPrint('Error loading videos: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _permissionDenied = true;
      });
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeTokens.surface,
        title: Text(
          'Permission Required',
          style: GoogleFonts.lato(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Video access is permanently denied. Please enable it in Settings to view your videos.',
          style: GoogleFonts.lato(color: AppThemeTokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.lato(color: AppThemeTokens.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: Text(
              'Open Settings',
              style: GoogleFonts.lato(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  List<VideoItem> get _visibleVideos {
    final query = _searchQuery.trim().toLowerCase();
    if (_imageSearchActive) {
      if (_semanticScoreById.isEmpty) return const [];
      final byId = <String, VideoItem>{
        for (final video in _allVideos) video.id: video,
      };
      final ids = _semanticScoreById.keys.toList(growable: false)
        ..sort(
          (a, b) => (_semanticScoreById[b] ?? 0).compareTo(
            _semanticScoreById[a] ?? 0,
          ),
        );
      return ids
          .map((id) => byId[id])
          .whereType<VideoItem>()
          .toList(growable: false);
    }

    final lexicalMatches = _allVideos
        .where((video) {
          if (query.isEmpty) return true;
          return video.name.toLowerCase().contains(query);
        })
        .toList(growable: false);

    if (query.isNotEmpty && _semanticScoreById.isNotEmpty) {
      final semanticScores = _semanticScoreById.values.toList(growable: false);
      final minSemantic = semanticScores.reduce(math.min);
      final maxSemantic = semanticScores.reduce(math.max);

      final candidatesById = <String, VideoItem>{
        for (final video in lexicalMatches) video.id: video,
      };
      for (final video in _allVideos) {
        if (_semanticScoreById.containsKey(video.id)) {
          candidatesById[video.id] = video;
        }
      }

      final rankingContext = _HybridRankingContext.build(
        videos: candidatesById.values.toList(growable: false),
        query: query,
        semanticScoreById: _semanticScoreById,
        favoriteMediaIds: _favoriteMediaIds,
        lexicalScore: _lexicalScore,
        completionAffinity: _completionAffinity,
        recencySignal: _recencySignal,
        explicitPreferenceSignal: _explicitPreferenceSignal,
        normalizeSemantic:
            ({
              required double? semanticRaw,
              required double minSemantic,
              required double maxSemantic,
            }) => _normalizeSemantic(
              semanticRaw: semanticRaw,
              minSemantic: minSemantic,
              maxSemantic: maxSemantic,
            ),
        minSemantic: minSemantic,
        maxSemantic: maxSemantic,
      );

      final ranked = candidatesById.values.toList(growable: false)
        ..sort((a, b) {
          final aScore = rankingContext.scoreFor(a);
          final bScore = rankingContext.scoreFor(b);
          if (aScore == bScore) {
            return _librarySortComparator(a, b);
          }
          return bScore.compareTo(aScore);
        });
      return ranked;
    }

    final sorted = lexicalMatches.toList(growable: false)
      ..sort(_librarySortComparator);
    return sorted;
  }

  double _lexicalScore(String title, String query) {
    final normalizedTitle = title.toLowerCase();
    final normalizedQuery = query.toLowerCase();
    if (normalizedTitle == normalizedQuery) return 1.0;
    if (normalizedTitle.startsWith(normalizedQuery)) return 0.95;
    if (normalizedTitle.contains(normalizedQuery)) return 0.72;
    final tokens = normalizedQuery
        .split(RegExp(r'\\s+'))
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return 0;
    var matches = 0;
    for (final token in tokens) {
      if (normalizedTitle.contains(token)) {
        matches += 1;
      }
    }
    return matches / tokens.length;
  }

  double _normalizeSemantic({
    required double? semanticRaw,
    required double minSemantic,
    required double maxSemantic,
  }) {
    if (semanticRaw == null) return 0;
    final spread = maxSemantic - minSemantic;
    if (spread <= 1e-9) return 1;
    return ((semanticRaw - minSemantic) / spread).clamp(0, 1).toDouble();
  }

  double _completionAffinity(VideoItem video) {
    final positionMs = video.lastPositionMs;
    final durationMs = video.duration?.inMilliseconds;
    if (positionMs == null || durationMs == null || durationMs <= 0) return 0;
    final ratio = (positionMs / durationMs).clamp(0.0, 1.0);
    if (ratio < 0.05) return 0;
    if (ratio > 0.97) return 0.45;
    // Prefer unfinished sessions that are likely to be resumed.
    final unfinished = 1.0 - (ratio - 0.72).abs();
    return unfinished.clamp(0.0, 1.0).toDouble();
  }

  double _recencySignal(VideoItem video) {
    final lastPlayedAt = video.lastPlayedAt;
    if (lastPlayedAt == null) return 0;
    final ageHours = DateTime.now().difference(lastPlayedAt).inHours;
    if (ageHours <= 0) return 1.0;
    final ageDays = ageHours / 24.0;
    // 7-day half-life style decay.
    return (1.0 / (1.0 + (ageDays / 7.0))).clamp(0.0, 1.0).toDouble();
  }

  double _explicitPreferenceSignal(VideoItem video) {
    var signal = 0.0;
    if (_favoriteMediaIds.contains(video.id)) {
      signal += 0.65;
    }
    if (video.playCount > 1) {
      final rewatch = ((video.playCount - 1) / 6.0).clamp(0.0, 1.0).toDouble();
      signal += 0.35 * rewatch;
    }
    return signal.clamp(0.0, 1.0).toDouble();
  }

  int _librarySortComparator(VideoItem a, VideoItem b) {
    switch (_sortOption) {
      case LibrarySortOption.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case LibrarySortOption.nameDesc:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
      case LibrarySortOption.dateModifiedDesc:
        final aDate =
            a.lastPlayedAt ??
            a.dateModified ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.lastPlayedAt ??
            b.dateModified ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      case LibrarySortOption.sizeDesc:
        return (b.size ?? 0).compareTo(a.size ?? 0);
      case LibrarySortOption.durationDesc:
        return (b.duration ?? Duration.zero).compareTo(
          a.duration ?? Duration.zero,
        );
    }
  }

  List<VideoFolder> get _visibleFolders {
    if (_imageSearchActive) {
      return const [];
    }
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _folders.where((folder) {
      if (query.isEmpty) return true;
      if (folder.name.toLowerCase().contains(query)) return true;
      return folder.videos.any((v) => v.name.toLowerCase().contains(query));
    }).toList();

    filtered.sort((a, b) {
      final aPinned = _pinnedFolderPaths.contains(a.path);
      final bPinned = _pinnedFolderPaths.contains(b.path);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }

  String _sortLabel(LibrarySortOption option) {
    switch (option) {
      case LibrarySortOption.nameAsc:
        return 'Name (A-Z)';
      case LibrarySortOption.nameDesc:
        return 'Name (Z-A)';
      case LibrarySortOption.dateModifiedDesc:
        return 'Recent';
      case LibrarySortOption.sizeDesc:
        return 'Size';
      case LibrarySortOption.durationDesc:
        return 'Duration';
    }
  }

  Future<void> _setSortOption(LibrarySortOption option) async {
    setState(() => _sortOption = option);
    await _libraryPreferences.setSortOption(option);
  }

  Future<void> _togglePinnedFolder(VideoFolder folder) async {
    await _libraryPreferences.togglePinnedFolder(folder.path);
    final pinned = await _libraryPreferences.getPinnedFolders();
    if (!mounted) return;
    setState(() => _pinnedFolderPaths = pinned);
  }

  Future<void> _toggleFavorite(VideoItem video) async {
    final willBeFavorite = !_favoriteMediaIds.contains(video.id);
    await _playbackRepository.setFavorite(video.id, willBeFavorite);
    final favorites = await _playbackRepository.getFavorites();
    if (!mounted) return;

    setState(() {
      _favoriteMediaIds = favorites;
      _allVideos = _allVideos
          .map(
            (v) =>
                v.id == video.id ? v.copyWith(isFavorite: willBeFavorite) : v,
          )
          .toList();
    });
  }

  Future<void> _openLastPlayed() async {
    final lastPlayed = _lastPlayed;
    if (lastPlayed == null) return;

    try {
      final source = MediaSource.fromInput(lastPlayed.sourceInput);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoApp(
            source: source,
            title: lastPlayed.title,
            start: PlaybackStart(position: lastPlayed.position),
          ),
        ),
      );
      final refreshed = await _playbackRepository.getLastPlayed();
      if (!mounted) return;
      setState(() => _lastPlayed = refreshed);
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the last played source.')),
      );
    }
  }

  Future<void> _handleHeaderMenuAction(_HeaderMenuAction action) async {
    switch (action) {
      case _HeaderMenuAction.about:
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AboutPage()),
        );
        break;
      case _HeaderMenuAction.refresh:
        await _libraryRepository.clearCache();
        await _loadVideos();
        await _initializePreferences();
        break;
      case _HeaderMenuAction.stream:
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const NetworkStreamPage()),
        );
        break;
    }
  }

  @override
  void dispose() {
    _semanticDebounceTimer?.cancel();
    _indexingStateSubscription?.cancel();
    _indexingScheduler?.dispose();
    _embeddingIndexStatus.commands.removeListener(_handleEmbeddingCommand);
    _miniPlayerService.removeListener(_onMiniPlayerStateChanged);
    _cleanupAllTemporaryImageFiles();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = LayoutMetrics.of(context);
    final miniPlayerInset = _miniPlayerService.layoutState.reservedBottomInset;
    final insets = resolveScaffoldInsets(
      context,
      miniPlayerInset: miniPlayerInset,
    );

    return Scaffold(
      backgroundColor: AppThemeTokens.scaffold,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(metrics),
                SizedBox(height: metrics.sectionSpacing),
                _buildTabs(metrics),
                SizedBox(height: metrics.sectionSpacing),
                _buildSearchAndSortBar(metrics),
                if (_lastPlayed != null) ...[
                  SizedBox(height: metrics.sectionSpacing),
                  _buildContinueWatchingCard(metrics),
                ],
                SizedBox(height: metrics.sectionSpacing),
                Expanded(
                  child: _isLoading
                      ? _buildLoadingState()
                      : _permissionDenied
                      ? _buildPermissionDeniedState()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildFoldersView(metrics, insets),
                            _buildAllVideosView(metrics, insets),
                          ],
                        ),
                ),
              ],
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LayoutMetrics metrics) {
    final compact = metrics.isCompact;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.horizontalPadding,
        metrics.sectionSpacing + 8,
        metrics.horizontalPadding,
        metrics.sectionSpacing,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Library',
                  style: GoogleFonts.lato(
                    color: Colors.white,
                    fontSize: compact ? 28 : 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_allVideos.length} videos',
                  style: GoogleFonts.lato(
                    color: AppThemeTokens.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            _buildHeaderAction(
              icon: Icons.link_rounded,
              tooltip: 'Stream URL',
              onTap: () => _handleHeaderMenuAction(_HeaderMenuAction.stream),
            ),
            SizedBox(width: metrics.compactActionSpacing),
          ],
          _buildHeaderAction(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
              await _initializeEmbeddingRuntime();
            },
          ),
          SizedBox(width: metrics.compactActionSpacing),
          PopupMenuButton<_HeaderMenuAction>(
            color: AppThemeTokens.surface,
            onSelected: _handleHeaderMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _HeaderMenuAction.about,
                child: Text('About'),
              ),
              const PopupMenuItem(
                value: _HeaderMenuAction.refresh,
                child: Text('Refresh Library'),
              ),
              if (compact)
                const PopupMenuItem(
                  value: _HeaderMenuAction.stream,
                  child: Text('Stream URL'),
                ),
            ],
            child: _buildHeaderAction(
              icon: Icons.more_horiz_rounded,
              tooltip: 'More',
              onTap: () {},
              absorbTap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool absorbTap = false,
  }) {
    final action = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppThemeTokens.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppThemeTokens.textSecondary, size: 21),
    );
    if (absorbTap) return action;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: action,
      ),
    );
  }

  Widget _buildTabs(LayoutMetrics metrics) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      child: TabBar(
        controller: _tabController,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppThemeTokens.accent, width: 2),
          insets: EdgeInsets.zero,
        ),
        labelStyle: GoogleFonts.lato(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.lato(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        labelColor: Colors.white,
        unselectedLabelColor: AppThemeTokens.textSecondary,
        dividerColor: AppThemeTokens.surface,
        tabs: const [
          Tab(text: 'Folders'),
          Tab(text: 'All Videos'),
        ],
      ),
    );
  }

  Widget _buildSearchAndSortBar(LayoutMetrics metrics) {
    final activeImageSearch = _imageSearchActive && _imageSearchPath != null;
    if (metrics.isCompact) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchField(),
            if (activeImageSearch) ...[
              const SizedBox(height: 8),
              _buildImageSearchBanner(),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _buildSortButton(compact: true),
            ),
            const SizedBox(height: 8),
            _buildSemanticReadinessBanner(),
            if (_semanticError != null &&
                _semanticError!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _semanticError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lato(color: Colors.redAccent, fontSize: 11),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _buildSearchField()),
              if (activeImageSearch) ...[
                const SizedBox(width: 8),
                Flexible(child: _buildImageSearchBanner(compact: true)),
              ],
              const SizedBox(width: 10),
              _buildSortButton(compact: false),
            ],
          ),
          const SizedBox(height: 8),
          _buildSemanticReadinessBanner(),
          if (_semanticError != null && _semanticError!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _semanticError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.lato(color: Colors.redAccent, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSemanticReadinessBanner() {
    return ValueListenableBuilder<EmbeddingIndexMetadata>(
      valueListenable: _embeddingIndexStatus.metadata,
      builder: (context, metadata, _) {
        final hasIndexedContent =
            metadata.indexedVideos > 0 ||
            metadata.indexedFrames > 0 ||
            metadata.lastRunAt != null;
        final isReady =
            _semanticRuntimeAvailable &&
            !_semanticIndexing &&
            (_semanticReady || hasIndexedContent);

        IconData icon;
        Color color;
        String headline;

        if (!_semanticRuntimeAvailable) {
          icon = Icons.error_outline_rounded;
          color = Colors.redAccent;
          headline = 'On-device model unavailable';
        } else if (_semanticIndexing) {
          icon = Icons.sync_rounded;
          color = AppThemeTokens.accent;
          headline = 'Building on-device index...';
        } else if (isReady) {
          icon = Icons.check_circle_outline_rounded;
          color = Colors.green;
          headline = 'On-device index ready';
        } else {
          icon = Icons.hourglass_empty_rounded;
          color = AppThemeTokens.textSecondary;
          headline = 'On-device index not ready';
        }

        final details =
            metadata.indexedVideos > 0 || metadata.indexedFrames > 0
            ? '${metadata.indexedVideos} videos • ${metadata.indexedFrames} frames'
            : null;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppThemeTokens.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppThemeTokens.surfaceAlt),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  details == null ? headline : '$headline • $details',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.lato(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
          if (_imageSearchActive && value.trim().isNotEmpty) {
            _imageSearchActive = false;
            _imageSearchPath = null;
          }
        });
        _scheduleSemanticSearch(value);
      },
      style: GoogleFonts.lato(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search videos or folders',
        hintStyle: GoogleFonts.lato(color: AppThemeTokens.textSecondary),
        prefixIcon: const Icon(
          Icons.search,
          color: AppThemeTokens.textSecondary,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Search by image',
              onPressed: _startImageSearch,
              icon: const Icon(
                Icons.image_search_rounded,
                color: AppThemeTokens.textSecondary,
                size: 20,
              ),
            ),
            if (_searchQuery.trim().isNotEmpty || _imageSearchActive)
              IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _cleanupTempImagePath(_imageSearchPath);
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _semanticRankedVideoIds = const [];
                    _semanticScoreById = const {};
                    _semanticError = _semanticRuntimeAvailable
                        ? null
                        : 'On-device embedding runtime is unavailable on this device.';
                    _imageSearchActive = false;
                    _imageSearchPath = null;
                  });
                },
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppThemeTokens.textSecondary,
                  size: 20,
                ),
              ),
          ],
        ),
        filled: true,
        fillColor: AppThemeTokens.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildImageSearchBanner({bool compact = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppThemeTokens.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppThemeTokens.surfaceAlt),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          const Icon(
            Icons.image_search_rounded,
            color: AppThemeTokens.accent,
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              compact ? 'Image search active' : 'Visual search active',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.lato(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _clearImageSearch,
            child: const Icon(
              Icons.close_rounded,
              color: AppThemeTokens.textSecondary,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortButton({required bool compact}) {
    return PopupMenuButton<LibrarySortOption>(
      initialValue: _sortOption,
      onSelected: _setSortOption,
      color: AppThemeTokens.surface,
      itemBuilder: (context) => LibrarySortOption.values
          .map(
            (option) => PopupMenuItem<LibrarySortOption>(
              value: option,
              child: Text(
                _sortLabel(option),
                style: GoogleFonts.lato(color: Colors.white),
              ),
            ),
          )
          .toList(),
      child: Container(
        height: 46,
        constraints: BoxConstraints(minWidth: compact ? 140 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppThemeTokens.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppThemeTokens.surfaceAlt),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              _sortLabel(_sortOption),
              style: GoogleFonts.lato(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueWatchingCard(LayoutMetrics metrics) {
    final lastPlayed = _lastPlayed;
    if (lastPlayed == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _openLastPlayed,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.isCompact ? 12 : 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: AppThemeTokens.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppThemeTokens.surfaceAlt),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_fill_rounded,
                  color: AppThemeTokens.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!metrics.isCompact)
                        Text(
                          'Continue watching',
                          style: GoogleFonts.lato(
                            color: AppThemeTokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Text(
                        lastPlayed.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lato(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(lastPlayed.position),
                  style: GoogleFonts.lato(
                    color: AppThemeTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFoldersView(
    LayoutMetrics metrics,
    ResponsiveScaffoldInsets insets,
  ) {
    final folders = _visibleFolders;
    if (folders.isEmpty) return _buildEmptyState();

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        0,
        4,
        0,
        insets.reservedBottomInset + metrics.sectionSpacing,
      ),
      itemCount: folders.length,
      separatorBuilder: (context, index) => Divider(
        color: AppThemeTokens.surface.withValues(alpha: 0.7),
        height: 1,
      ),
      itemBuilder: (context, index) =>
          _buildFolderCard(metrics, folders[index]),
    );
  }

  Widget _buildFolderCard(LayoutMetrics metrics, VideoFolder folder) {
    final isPinned = _pinnedFolderPaths.contains(folder.path);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoListPage(folder: folder),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.horizontalPadding,
            vertical: 12,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppThemeTokens.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.folder_outlined,
                  color: AppThemeTokens.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.lato(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isPinned) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: AppThemeTokens.accent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${folder.videoCount} video${folder.videoCount != 1 ? 's' : ''}',
                      style: GoogleFonts.lato(
                        color: AppThemeTokens.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_FolderMenuAction>(
                color: AppThemeTokens.surface,
                onSelected: (action) async {
                  switch (action) {
                    case _FolderMenuAction.open:
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoListPage(folder: folder),
                        ),
                      );
                      break;
                    case _FolderMenuAction.pinToggle:
                      await _togglePinnedFolder(folder);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _FolderMenuAction.open,
                    child: Text('Open'),
                  ),
                  PopupMenuItem(
                    value: _FolderMenuAction.pinToggle,
                    child: Text(isPinned ? 'Unpin folder' : 'Pin folder'),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.more_vert_rounded,
                    color: AppThemeTokens.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllVideosView(
    LayoutMetrics metrics,
    ResponsiveScaffoldInsets insets,
  ) {
    final videos = _visibleVideos;
    if (videos.isEmpty) {
      return _imageSearchActive
          ? _buildImageSearchEmptyState()
          : _buildEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = metrics.isCompact
            ? 152.0
            : metrics.isMedium
            ? 174.0
            : 198.0;
        final computed = (constraints.maxWidth / minWidth).floor();
        final crossAxisCount = math.max(metrics.minGridColumns, computed);
        final aspectRatio = metrics.isCompact ? 0.74 : 0.78;

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            metrics.horizontalPadding,
            8,
            metrics.horizontalPadding,
            insets.reservedBottomInset + metrics.sectionSpacing,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: metrics.cardSpacing,
            mainAxisSpacing: metrics.cardSpacing + 4,
            childAspectRatio: aspectRatio,
          ),
          itemCount: videos.length,
          itemBuilder: (context, index) => _buildVideoCard(videos[index]),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CompactLoadingAnimation(color: AppThemeTokens.accent),
          const SizedBox(height: 20),
          Text(
            'Scanning videos...',
            style: GoogleFonts.lato(
              color: AppThemeTokens.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDeniedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_open_rounded,
              size: 48,
              color: AppThemeTokens.textSecondary,
            ),
            const SizedBox(height: 20),
            Text(
              'Storage Access',
              style: GoogleFonts.lato(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Allow access to display your videos',
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                color: AppThemeTokens.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loadVideos,
              style: FilledButton.styleFrom(
                backgroundColor: AppThemeTokens.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Grant Access',
                style: GoogleFonts.lato(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(VideoItem video) {
    final reasonChips = _resultReasonChips(video);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoApp(
                source: MediaSource.fromInput(video.path),
                title: video.name,
                start: video.lastPositionMs != null
                    ? PlaybackStart(
                        position: Duration(milliseconds: video.lastPositionMs!),
                      )
                    : null,
              ),
            ),
          );
          final refreshed = await _playbackRepository.getLastPlayed();
          if (!mounted) return;
          setState(() => _lastPlayed = refreshed);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  _buildVideoThumbnail(video),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: GestureDetector(
                      onTap: () => _toggleFavorite(video),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          _favoriteMediaIds.contains(video.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: _favoriteMediaIds.contains(video.id)
                              ? Colors.redAccent
                              : Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  if (video.duration != null)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatDuration(video.duration!),
                          style: GoogleFonts.lato(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              video.name,
              style: GoogleFonts.lato(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (reasonChips.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: reasonChips
                    .map(
                      (label) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppThemeTokens.surface,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: AppThemeTokens.surfaceAlt),
                        ),
                        child: Text(
                          label,
                          style: GoogleFonts.lato(
                            color: AppThemeTokens.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            if (video.size != null) ...[
              const SizedBox(height: 2),
              Text(
                _formatFileSize(video.size!),
                style: GoogleFonts.lato(
                  color: AppThemeTokens.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
            if (video.lastPositionMs != null &&
                video.duration != null &&
                video.lastPositionMs! > 0) ...[
              const SizedBox(height: 2),
              Text(
                'Resume ${_formatDuration(Duration(milliseconds: video.lastPositionMs!))}',
                style: GoogleFonts.lato(
                  color: AppThemeTokens.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _resultReasonChips(VideoItem video) {
    if (!_imageSearchActive && _searchQuery.trim().isEmpty) {
      return const [];
    }
    final chips = <String>[];
    if (_semanticScoreById.containsKey(video.id)) {
      chips.add('Visual match');
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty && video.name.toLowerCase() == query) {
      chips.add('Exact title');
    }

    if (_recencySignal(video) >= 0.58) {
      chips.add('Watched recently');
    }
    return chips;
  }

  Widget _buildVideoThumbnail(VideoItem video) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: FutureBuilder<Uint8List?>(
        future: _thumbnailFutureFor(video),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return SizedBox.expand(
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            );
          }

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppThemeTokens.surface, AppThemeTokens.surfaceAlt],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.movie_outlined,
                color: AppThemeTokens.textSecondary,
                size: 24,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<Uint8List?> _thumbnailFutureFor(VideoItem video) {
    return _thumbnailFutures.putIfAbsent(video.id, () => _loadThumbnail(video));
  }

  Future<Uint8List?> _loadThumbnail(VideoItem video) async {
    final assetId = (video.thumbnail ?? video.id).trim();
    if (assetId.isEmpty) return null;
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) return null;
    return asset.thumbnailDataWithSize(
      const ThumbnailSize(360, 202),
      quality: 76,
      format: ThumbnailFormat.jpeg,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/empty.png',
            width: 80,
            height: 80,
            color: AppThemeTokens.textSecondary,
          ),
          const SizedBox(height: 20),
          Text(
            'No videos',
            style: GoogleFonts.lato(
              color: AppThemeTokens.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSearchEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_search_rounded,
              color: AppThemeTokens.textSecondary,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'No visual matches found',
              style: GoogleFonts.lato(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another image or use text search.',
              style: GoogleFonts.lato(
                color: AppThemeTokens.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _clearImageSearch,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppThemeTokens.surfaceAlt),
              ),
              child: Text('Clear visual search', style: GoogleFonts.lato()),
            ),
          ],
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
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

typedef _LexicalScoreFn = double Function(String title, String query);
typedef _VideoSignalFn = double Function(VideoItem video);
typedef _NormalizeSemanticFn =
    double Function({
      required double? semanticRaw,
      required double minSemantic,
      required double maxSemantic,
    });

class _HybridRankingContext {
  final Map<String, double> _scoreById;

  const _HybridRankingContext._(this._scoreById);

  static _HybridRankingContext build({
    required List<VideoItem> videos,
    required String query,
    required Map<String, double> semanticScoreById,
    required Set<String> favoriteMediaIds,
    required _LexicalScoreFn lexicalScore,
    required _VideoSignalFn completionAffinity,
    required _VideoSignalFn recencySignal,
    required _VideoSignalFn explicitPreferenceSignal,
    required _NormalizeSemanticFn normalizeSemantic,
    required double minSemantic,
    required double maxSemantic,
  }) {
    if (videos.isEmpty) {
      return const _HybridRankingContext._(<String, double>{});
    }

    final lexicalById = <String, double>{};
    final semanticById = <String, double>{};
    final behaviorById = <String, double>{};
    for (final video in videos) {
      lexicalById[video.id] = lexicalScore(video.name, query);
      semanticById[video.id] = normalizeSemantic(
        semanticRaw: semanticScoreById[video.id],
        minSemantic: minSemantic,
        maxSemantic: maxSemantic,
      );
      final completion = completionAffinity(video);
      final recency = recencySignal(video);
      final preference = explicitPreferenceSignal(video);
      final favoriteBoost = favoriteMediaIds.contains(video.id) ? 0.08 : 0.0;
      behaviorById[video.id] =
          ((0.42 * completion) + (0.28 * recency) + (0.30 * preference) +
                  favoriteBoost)
              .clamp(0.0, 1.0)
              .toDouble();
    }

    final lexicalRank = _rankByScore(lexicalById);
    final semanticRank = _rankByScore(semanticById);
    final behaviorRank = _rankByScore(behaviorById);
    final scoreById = <String, double>{};
    for (final video in videos) {
      final id = video.id;
      final rrf = _rrf(
        lexicalRank: lexicalRank[id] ?? 100000,
        semanticRank: semanticRank[id] ?? 100000,
        behaviorRank: behaviorRank[id] ?? 100000,
      );
      final lexical = lexicalById[id] ?? 0;
      final semantic = semanticById[id] ?? 0;
      final behavior = behaviorById[id] ?? 0;
      final calibratedLinear =
          (0.35 * lexical) + (0.50 * semantic) + (0.15 * behavior);
      scoreById[id] = (0.65 * rrf) + (0.35 * calibratedLinear);
    }

    return _HybridRankingContext._(scoreById);
  }

  double scoreFor(VideoItem video) => _scoreById[video.id] ?? 0;

  static Map<String, int> _rankByScore(Map<String, double> scores) {
    final entries = scores.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    final rankById = <String, int>{};
    for (var i = 0; i < entries.length; i++) {
      rankById[entries[i].key] = i + 1;
    }
    return rankById;
  }

  static double _rrf({
    required int lexicalRank,
    required int semanticRank,
    required int behaviorRank,
  }) {
    const k = 60.0;
    final lexical = 0.42 / (k + lexicalRank);
    final semantic = 0.43 / (k + semanticRank);
    final behavior = 0.15 / (k + behaviorRank);
    return lexical + semantic + behavior;
  }
}
