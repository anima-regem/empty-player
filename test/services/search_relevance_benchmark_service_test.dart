import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/services/embedding_runtime.dart';
import 'package:empty_player/services/search_relevance_benchmark_service.dart';
import 'package:empty_player/services/vector_index_repository.dart';
import 'package:empty_player/services/video_semantic_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _SemanticFixtureRuntime implements EmbeddingRuntime {
  @override
  String get runtimeName => 'fixture-runtime';

  @override
  int get dimensions => 3;

  @override
  Future<List<double>> embedFrame(VideoFrameInput frame) async {
    return _vectorFor(frame.sourcePath);
  }

  @override
  Future<List<double>> embedImage(ImageEmbeddingInput image) async {
    return _vectorFor(image.imagePath);
  }

  @override
  Future<List<double>> embedText(String query) async {
    return _vectorFor(query);
  }

  List<double> _vectorFor(String source) {
    final value = source.toLowerCase();
    if (value.contains('ocean')) return const [1, 0, 0];
    if (value.contains('city')) return const [0, 1, 0];
    return const [0, 0, 1];
  }
}

void main() {
  group('SearchRelevanceBenchmarkService', () {
    test('computes recall@k, ndcg@k, mrr, latency and memory', () async {
      final runtime = _SemanticFixtureRuntime();
      final indexRepository = InMemoryVectorIndexRepository();
      final searchService = VideoSemanticSearchService(
        runtime: runtime,
        indexRepository: indexRepository,
      );

      final videos = <VideoItem>[
        VideoItem(
          id: 'ocean-1',
          name: 'Ocean Waves',
          path: '/tmp/ocean.mp4',
          duration: const Duration(minutes: 2),
        ),
        VideoItem(
          id: 'city-1',
          name: 'City Night',
          path: '/tmp/city.mp4',
          duration: const Duration(minutes: 2),
        ),
        VideoItem(
          id: 'forest-1',
          name: 'Forest Walk',
          path: '/tmp/forest.mp4',
          duration: const Duration(minutes: 2),
        ),
      ];

      await searchService.indexVideos(
        videos: videos,
        framesPerVideo: 3,
        candidateMultiplier: 2,
        includeTemporalAggregate: true,
        forceRebuild: true,
      );

      final benchmark = SearchRelevanceBenchmarkService(
        discoveryService: searchService,
        indexRepository: indexRepository,
      );

      final result = await benchmark.run(
        labeledQueries: const <LabeledSearchQuery>[
          LabeledSearchQuery(
            id: 'q1',
            query: 'ocean scene',
            relevantMediaIds: {'ocean-1'},
          ),
          LabeledSearchQuery(
            id: 'q2',
            query: 'city skyline',
            relevantMediaIds: {'city-1'},
          ),
          LabeledSearchQuery(
            id: 'q3',
            query: 'forest trail',
            relevantMediaIds: {'forest-1'},
          ),
        ],
        config: const SearchBenchmarkConfig(k: 10, enforceDatasetSize: false),
      );

      expect(result.queryCount, 3);
      expect(result.recallAtK, 1.0);
      expect(result.ndcgAtK, 1.0);
      expect(result.mrr, 1.0);
      expect(result.latencyP95Ms, greaterThanOrEqualTo(0));
      expect(result.memoryP95Bytes, greaterThanOrEqualTo(0));
      expect(result.toMarkdown(), contains('Recall@10'));
    });

    test('enforces dataset range when strict mode is enabled', () async {
      final runtime = _SemanticFixtureRuntime();
      final indexRepository = InMemoryVectorIndexRepository();
      final searchService = VideoSemanticSearchService(
        runtime: runtime,
        indexRepository: indexRepository,
      );
      final benchmark = SearchRelevanceBenchmarkService(
        discoveryService: searchService,
        indexRepository: indexRepository,
      );

      expect(
        () => benchmark.run(
          labeledQueries: const <LabeledSearchQuery>[
            LabeledSearchQuery(
              id: 'small',
              query: 'sample',
              relevantMediaIds: {'id-1'},
            ),
          ],
          config: const SearchBenchmarkConfig(enforceDatasetSize: true),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
