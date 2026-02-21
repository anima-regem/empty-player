import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/services/embedding_runtime.dart';
import 'package:empty_player/services/vector_index_repository.dart';
import 'package:empty_player/services/video_semantic_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingEmbeddingRuntime implements EmbeddingRuntime {
  @override
  String get runtimeName => 'counting-runtime';

  @override
  int get dimensions => 3;

  int frameCalls = 0;

  @override
  Future<List<double>> embedFrame(VideoFrameInput frame) async {
    frameCalls += 1;
    return <double>[1, 0, 0];
  }

  @override
  Future<List<double>> embedText(String query) async {
    return <double>[1, 0, 0];
  }

  @override
  Future<List<double>> embedImage(ImageEmbeddingInput image) async {
    return <double>[1, 0, 0];
  }
}

class _FailingEmbeddingRuntime implements EmbeddingRuntime {
  @override
  String get runtimeName => 'failing-runtime';

  @override
  int get dimensions => 4;

  @override
  Future<List<double>> embedFrame(VideoFrameInput frame) async {
    throw StateError('frame embedding failed');
  }

  @override
  Future<List<double>> embedText(String query) async {
    throw StateError('text embedding failed');
  }

  @override
  Future<List<double>> embedImage(ImageEmbeddingInput image) async {
    throw StateError('image embedding failed');
  }
}

void main() {
  test(
    'indexVideos skips unchanged media and reindexes changed media',
    () async {
      final runtime = _CountingEmbeddingRuntime();
      final repository = InMemoryVectorIndexRepository();
      final service = VideoSemanticSearchService(
        runtime: runtime,
        indexRepository: repository,
      );

      final videoA = VideoItem(
        id: 'a',
        name: 'Video A',
        path: '/tmp/a.mp4',
        size: 10,
        duration: const Duration(seconds: 10),
        dateModified: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final videoB = VideoItem(
        id: 'b',
        name: 'Video B',
        path: '/tmp/b.mp4',
        size: 20,
        duration: const Duration(seconds: 10),
        dateModified: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      await service.indexVideos(
        videos: [videoA, videoB],
        framesPerVideo: 2,
        candidateMultiplier: 1,
      );
      expect(runtime.frameCalls, 4);

      await service.indexVideos(
        videos: [videoA, videoB],
        framesPerVideo: 2,
        candidateMultiplier: 1,
      );
      expect(runtime.frameCalls, 4);

      await service.indexVideos(
        videos: [videoA, videoB],
        framesPerVideo: 2,
        candidateMultiplier: 1,
        forceRebuild: true,
      );
      expect(runtime.frameCalls, 8);

      final changedVideoA = videoA.copyWith(size: 11);
      await service.indexVideos(
        videos: [changedVideoA, videoB],
        framesPerVideo: 2,
        candidateMultiplier: 1,
      );
      expect(runtime.frameCalls, 10);
    },
  );

  test(
    'indexVideos falls back to deterministic vectors when embedding fails',
    () async {
      final runtime = _FailingEmbeddingRuntime();
      final repository = InMemoryVectorIndexRepository();
      final service = VideoSemanticSearchService(
        runtime: runtime,
        indexRepository: repository,
      );

      final videos = [
        VideoItem(
          id: 'a',
          name: 'Video A',
          path: '/tmp/a.mp4',
          size: 10,
          duration: const Duration(seconds: 5),
        ),
        VideoItem(
          id: 'b',
          name: 'Video B',
          path: '/tmp/b.mp4',
          size: 12,
          duration: const Duration(seconds: 6),
        ),
      ];

      final counts = await service.indexVideos(
        videos: videos,
        framesPerVideo: 2,
        candidateMultiplier: 1,
      );
      expect(counts['a'], 1);
      expect(counts['b'], 1);

      final stats = await repository.stats();
      expect(stats.mediaCount, 2);
      expect(stats.chunkCount, 2);
    },
  );

  test(
    'scene-aware sampler scans extra candidates but caps stored frames',
    () async {
      final runtime = _CountingEmbeddingRuntime();
      final repository = InMemoryVectorIndexRepository();
      final service = VideoSemanticSearchService(
        runtime: runtime,
        indexRepository: repository,
      );

      final video = VideoItem(
        id: 'scene-1',
        name: 'Scene A',
        path: '/tmp/scene-a.mp4',
        duration: const Duration(seconds: 30),
      );

      final counts = await service.indexVideos(
        videos: [video],
        framesPerVideo: 2,
        candidateMultiplier: 3,
        sceneSimilarityThreshold: 0.8,
        forceRebuild: true,
      );
      expect(runtime.frameCalls, 6);
      expect(counts['scene-1'], 2);
    },
  );

  test('searchByImagePath returns ranked hits from indexed vectors', () async {
    final runtime = _CountingEmbeddingRuntime();
    final repository = InMemoryVectorIndexRepository();
    final service = VideoSemanticSearchService(
      runtime: runtime,
      indexRepository: repository,
    );

    final video = VideoItem(
      id: 'img-1',
      name: 'Ocean Clip',
      path: '/tmp/ocean.mp4',
      duration: const Duration(seconds: 8),
    );

    await service.indexVideos(
      videos: [video],
      framesPerVideo: 2,
      candidateMultiplier: 1,
      forceRebuild: true,
    );

    final hits = await service.searchByImagePath('/tmp/query.jpg');
    expect(hits, isNotEmpty);
    expect(hits.first.mediaId, 'img-1');
  });
}
