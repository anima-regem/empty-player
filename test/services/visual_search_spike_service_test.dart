import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/services/embedding_runtime.dart';
import 'package:empty_player/services/vector_index_repository.dart';
import 'package:empty_player/services/visual_search_spike_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisualSearchSpikeService', () {
    test('produces benchmark metrics with deterministic runtime', () async {
      final service = VisualSearchSpikeService(
        runtime: const DeterministicSpikeEmbeddingRuntime(dimensions: 32),
        indexRepository: InMemoryVectorIndexRepository(),
      );

      final videos = [
        VideoItem(
          id: 'video-a',
          name: 'Ocean Waves',
          path: '/storage/ocean.mp4',
          duration: const Duration(minutes: 2),
        ),
        VideoItem(
          id: 'video-b',
          name: 'City Timelapse',
          path: '/storage/city.mp4',
          duration: const Duration(minutes: 3),
        ),
      ];

      final result = await service.runSyntheticBenchmark(
        videos: videos,
        framesPerVideo: 4,
        measuredQueries: 8,
      );

      expect(result.indexedVideos, 2);
      expect(result.indexedFrames, 8);
      expect(result.queryP95Ms, greaterThanOrEqualTo(0));
      expect(result.estimatedIndexBytes, greaterThan(0));
      expect(result.runtimeName, 'deterministic_spike');
      expect(
        result.toMarkdownReport(),
        contains('Visual Search Feasibility Benchmark'),
      );
    });
  });
}
