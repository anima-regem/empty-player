import 'dart:math' as math;
import 'dart:typed_data';

import 'package:empty_player/models/video_embedding_chunk.dart';
import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/services/embedding_runtime.dart';
import 'package:empty_player/services/vector_index_repository.dart';

class VisualSearchBenchmarkResult {
  final int indexedVideos;
  final int indexedFrames;
  final double indexingFramesPerSecond;
  final double queryP50Ms;
  final double queryP95Ms;
  final int estimatedIndexBytes;
  final double estimatedIndexBytesPerHour;
  final int avgTopResults;
  final String runtimeName;
  final DateTime generatedAt;

  const VisualSearchBenchmarkResult({
    required this.indexedVideos,
    required this.indexedFrames,
    required this.indexingFramesPerSecond,
    required this.queryP50Ms,
    required this.queryP95Ms,
    required this.estimatedIndexBytes,
    required this.estimatedIndexBytesPerHour,
    required this.avgTopResults,
    required this.runtimeName,
    required this.generatedAt,
  });
}

class VisualSearchSpikeService {
  final EmbeddingRuntime runtime;
  final VectorIndexRepository indexRepository;

  const VisualSearchSpikeService({
    required this.runtime,
    required this.indexRepository,
  });

  Future<VisualSearchBenchmarkResult> runSyntheticBenchmark({
    required List<VideoItem> videos,
    int framesPerVideo = 6,
    int measuredQueries = 20,
    int queryLimit = 10,
  }) async {
    if (videos.isEmpty) {
      return VisualSearchBenchmarkResult(
        indexedVideos: 0,
        indexedFrames: 0,
        indexingFramesPerSecond: 0,
        queryP50Ms: 0,
        queryP95Ms: 0,
        estimatedIndexBytes: 0,
        estimatedIndexBytesPerHour: 0,
        avgTopResults: 0,
        runtimeName: runtime.runtimeName,
        generatedAt: DateTime.now(),
      );
    }

    final indexingWatch = Stopwatch()..start();
    var indexedFrames = 0;
    for (final video in videos) {
      final chunks = await _buildSyntheticChunks(
        video: video,
        framesPerVideo: framesPerVideo,
      );
      indexedFrames += chunks.length;
      await indexRepository.upsert(chunks);
    }
    indexingWatch.stop();

    final queryLatencies = <double>[];
    var totalResults = 0;
    final random = math.Random(41);
    final sampleQueries = List<String>.generate(
      measuredQueries,
      (index) => videos[random.nextInt(videos.length)].name,
    );

    for (final query in sampleQueries) {
      final watch = Stopwatch()..start();
      final queryVector = await runtime.embedText(query);
      final hits = await indexRepository.query(queryVector, limit: queryLimit);
      watch.stop();
      queryLatencies.add(watch.elapsedMicroseconds / 1000);
      totalResults += hits.length;
    }

    final stats = await indexRepository.stats();
    final totalDurationSeconds = videos.fold<int>(
      0,
      (sum, video) => sum + (video.duration?.inSeconds ?? 0),
    );
    final durationHours = totalDurationSeconds / 3600.0;
    final indexBytesPerHour = durationHours > 0
        ? stats.estimatedBytes / durationHours
        : 0.0;
    final elapsedSeconds = indexingWatch.elapsedMilliseconds / 1000.0;

    return VisualSearchBenchmarkResult(
      indexedVideos: videos.length,
      indexedFrames: indexedFrames,
      indexingFramesPerSecond: elapsedSeconds == 0
          ? 0
          : indexedFrames / elapsedSeconds,
      queryP50Ms: _percentile(queryLatencies, 0.50),
      queryP95Ms: _percentile(queryLatencies, 0.95),
      estimatedIndexBytes: stats.estimatedBytes,
      estimatedIndexBytesPerHour: indexBytesPerHour,
      avgTopResults: queryLatencies.isEmpty
          ? 0
          : (totalResults / queryLatencies.length).round(),
      runtimeName: runtime.runtimeName,
      generatedAt: DateTime.now(),
    );
  }

  Future<List<VideoEmbeddingChunk>> _buildSyntheticChunks({
    required VideoItem video,
    required int framesPerVideo,
  }) async {
    final durationMs =
        (video.duration ?? const Duration(minutes: 2)).inMilliseconds;
    final frameCount = math.max(1, framesPerVideo);
    final chunks = <VideoEmbeddingChunk>[];

    for (var i = 0; i < frameCount; i++) {
      final progress = (i + 1) / (frameCount + 1);
      final timestampMs = (durationMs * progress).round();
      final frame = VideoFrameInput(
        mediaId: video.id,
        timestamp: Duration(milliseconds: timestampMs),
        bytes: Uint8List.fromList(
          '$timestampMs:${video.path}:${video.name}'.codeUnits,
        ),
      );
      final vector = await runtime.embedFrame(frame);
      chunks.add(
        VideoEmbeddingChunk(
          mediaId: video.id,
          frameTsMs: timestampMs,
          vector: vector,
          modelVersion: runtime.runtimeName,
        ),
      );
    }

    return chunks;
  }

  double _percentile(List<double> values, double percentile) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final index = (percentile * (sorted.length - 1)).round();
    return sorted[index];
  }
}

extension VectorSearchBenchmarkResultReport on VisualSearchBenchmarkResult {
  String toMarkdownReport() {
    return '''
# Visual Search Feasibility Benchmark

- Generated: $generatedAt
- Runtime: $runtimeName
- Indexed videos: $indexedVideos
- Indexed frames: $indexedFrames
- Indexing throughput (frames/s): ${indexingFramesPerSecond.toStringAsFixed(2)}
- Query latency p50 (ms): ${queryP50Ms.toStringAsFixed(2)}
- Query latency p95 (ms): ${queryP95Ms.toStringAsFixed(2)}
- Estimated index bytes: $estimatedIndexBytes
- Estimated index bytes per hour: ${estimatedIndexBytesPerHour.toStringAsFixed(0)}
- Average top hits per query: $avgTopResults
''';
  }
}
