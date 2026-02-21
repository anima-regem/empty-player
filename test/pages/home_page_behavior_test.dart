import 'package:empty_player/models/playback_state.dart';
import 'package:empty_player/models/vector_search_hit.dart';
import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/pages/home_page.dart';
import 'package:empty_player/services/embedding_runtime.dart';
import 'package:empty_player/services/library_repository.dart';
import 'package:empty_player/services/playback_repository.dart';
import 'package:empty_player/services/vector_index_repository.dart';
import 'package:empty_player/services/video_semantic_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLibraryRepository implements LibraryRepository, PermissionGateway {
  final List<VideoItem> videos;

  const _FakeLibraryRepository({required this.videos});

  @override
  Future<void> clearCache() async {}

  @override
  Future<Map<String, dynamic>> getAllVideos() async {
    final folder = VideoFolder(name: 'Test', path: '/tmp', videos: videos);
    return <String, dynamic>{
      'videos': videos,
      'folders': <VideoFolder>[folder],
    };
  }

  @override
  Future<bool> hasLibraryPermission() async => true;

  @override
  Future<List<VideoFolder>> organizeIntoFolders(List<VideoItem> videos) async {
    return <VideoFolder>[
      VideoFolder(name: 'Test', path: '/tmp', videos: videos),
    ];
  }

  @override
  Future<PermissionStatus> requestLibraryPermission() async =>
      PermissionStatus.granted;

  @override
  Future<List<VideoItem>> scanAllVideos() async => videos;
}

class _InMemoryPlaybackRepository implements PlaybackRepository {
  final Map<String, PlaybackState> _states = <String, PlaybackState>{};
  PlaybackState? _lastPlayed;
  final Set<String> _favorites = <String>{};

  @override
  Future<void> clearState(String mediaId) async {
    _states.remove(mediaId);
  }

  @override
  Future<Set<String>> getFavorites() async => _favorites;

  @override
  Future<PlaybackState?> getLastPlayed() async => _lastPlayed;

  @override
  Future<List<PlaybackState>> getRecentStates({int limit = 20}) async {
    final values = _states.values.toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (values.length <= limit) return values;
    return values.take(limit).toList(growable: false);
  }

  @override
  Future<PlaybackState?> getState(String mediaId) async => _states[mediaId];

  @override
  Future<bool> isFavorite(String mediaId) async => _favorites.contains(mediaId);

  @override
  Future<void> saveLastPlayed(PlaybackState state) async {
    _lastPlayed = state;
    _states[state.mediaId] = state;
  }

  @override
  Future<void> saveState(PlaybackState state) async {
    _states[state.mediaId] = state;
  }

  @override
  Future<void> setFavorite(String mediaId, bool isFavorite) async {
    if (isFavorite) {
      _favorites.add(mediaId);
    } else {
      _favorites.remove(mediaId);
    }
  }
}

class _ScriptedSemanticSearchService extends VideoSemanticSearchService {
  final Map<String, int> indexCounts;
  final List<VectorSearchHit> scriptedHits;

  _ScriptedSemanticSearchService({
    required super.runtime,
    required super.indexRepository,
    required this.indexCounts,
    required this.scriptedHits,
  });

  @override
  Future<Map<String, int>> indexVideos({
    required List<VideoItem> videos,
    int framesPerVideo = 4,
    int maxVideos = 180,
    int candidateMultiplier = 3,
    double sceneSimilarityThreshold = 0.86,
    bool forceRebuild = false,
    Future<void> Function(double progress)? onProgress,
  }) async {
    await onProgress?.call(1.0);
    return indexCounts;
  }

  @override
  Future<List<VectorSearchHit>> search(
    String query, {
    int limit = 30,
    double minScore = 0.14,
  }) async {
    if (query.toLowerCase().contains('sunset')) {
      return scriptedHits;
    }
    return const <VectorSearchHit>[];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'semantic search shows non-lexical matches in All Videos results',
    (tester) async {
      final videos = <VideoItem>[
        VideoItem(
          id: 'city',
          name: 'City Walkthrough',
          path: '/tmp/city.mp4',
          thumbnail: '',
          duration: const Duration(minutes: 3),
        ),
        VideoItem(
          id: 'ocean',
          name: 'Ocean Clip',
          path: '/tmp/ocean.mp4',
          thumbnail: '',
          duration: const Duration(minutes: 4),
        ),
      ];

      final library = _FakeLibraryRepository(videos: videos);

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            libraryRepository: library,
            permissionGateway: library,
            playbackRepository: _InMemoryPlaybackRepository(),
            initialEmbeddingRuntime: const DeterministicSpikeEmbeddingRuntime(
              runtimeName: 'test-runtime',
              dimensions: 8,
            ),
            embeddingRuntimeResolver:
                ({mode = EmbeddingRuntimeMode.auto}) async {
                  return const DeterministicSpikeEmbeddingRuntime(
                    runtimeName: 'test-runtime',
                    dimensions: 8,
                  );
                },
            semanticSearchServiceBuilder:
                ({
                  required EmbeddingRuntime runtime,
                  required VectorIndexRepository indexRepository,
                }) {
                  return _ScriptedSemanticSearchService(
                    runtime: runtime,
                    indexRepository: indexRepository,
                    indexCounts: const <String, int>{'city': 1, 'ocean': 1},
                    scriptedHits: const <VectorSearchHit>[
                      VectorSearchHit(
                        mediaId: 'ocean',
                        score: 0.95,
                        matchedFrames: <int>[12000],
                      ),
                    ],
                  );
                },
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('All Videos'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'sunset beach');
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pumpAndSettle();

      expect(find.text('Ocean Clip'), findsWidgets);
      expect(find.text('No videos'), findsNothing);
    },
  );

  testWidgets('degraded runtime surfaces explicit unavailability message', (
    tester,
  ) async {
    final library = _FakeLibraryRepository(videos: const <VideoItem>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          libraryRepository: library,
          permissionGateway: library,
          playbackRepository: _InMemoryPlaybackRepository(),
          initialEmbeddingRuntime: const DeterministicSpikeEmbeddingRuntime(
            runtimeName: 'test-runtime',
            dimensions: 8,
          ),
          embeddingRuntimeResolver: ({mode = EmbeddingRuntimeMode.auto}) async {
            return const UnavailableEmbeddingRuntime(
              reason: 'Test unavailable runtime.',
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Test unavailable runtime.'), findsOneWidget);
  });
}
