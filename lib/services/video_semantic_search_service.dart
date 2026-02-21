import 'dart:math' as math;

import 'package:empty_player/models/vector_search_hit.dart';
import 'package:empty_player/models/video_embedding_chunk.dart';
import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/services/embedding_runtime.dart';
import 'package:empty_player/services/vector_index_repository.dart';

class VideoSemanticSearchService {
  final EmbeddingRuntime runtime;
  final VectorIndexRepository indexRepository;

  const VideoSemanticSearchService({
    required this.runtime,
    required this.indexRepository,
  });

  Future<Map<String, int>> indexVideos({
    required List<VideoItem> videos,
    int framesPerVideo = 4,
    int maxVideos = 180,
    int candidateMultiplier = 3,
    double sceneSimilarityThreshold = 0.86,
    bool forceRebuild = false,
    Future<void> Function(double progress)? onProgress,
  }) async {
    final allEligible = videos
        .where((video) => video.path.trim().isNotEmpty)
        .toList(growable: false);
    final candidates = allEligible.take(maxVideos).toList(growable: false);
    final frameCountByMediaId = <String, int>{};

    if (candidates.isEmpty) {
      return frameCountByMediaId;
    }
    await indexRepository.removeMediaNotIn(
      allEligible.map((video) => video.id).toSet(),
    );

    for (var index = 0; index < candidates.length; index++) {
      final video = candidates[index];
      final signature = _videoSignature(video);
      final existingState = await indexRepository.getMediaIndexState(video.id);
      if (!forceRebuild &&
          existingState != null &&
          existingState.signature == signature &&
          existingState.modelVersion == runtime.runtimeName &&
          existingState.framesPerVideo == framesPerVideo) {
        frameCountByMediaId[video.id] = existingState.frameCount;
        if (onProgress != null) {
          await onProgress((index + 1) / candidates.length);
        }
        continue;
      }

      final chunks = <VideoEmbeddingChunk>[];
      await indexRepository.deleteMedia(video.id);

      final sceneAwareChunks = await _buildSceneAwareChunks(
        video: video,
        framesPerVideo: framesPerVideo,
        candidateMultiplier: candidateMultiplier,
        sceneSimilarityThreshold: sceneSimilarityThreshold,
      );
      chunks.addAll(sceneAwareChunks);

      if (chunks.isEmpty) {
        final fallbackVector = await _buildFallbackVector(video);
        if (fallbackVector != null && fallbackVector.isNotEmpty) {
          chunks.add(
            VideoEmbeddingChunk(
              mediaId: video.id,
              frameTsMs: 0,
              vector: fallbackVector,
              modelVersion: runtime.runtimeName,
            ),
          );
        }
      }

      if (chunks.isNotEmpty) {
        frameCountByMediaId[video.id] = chunks.length;
        await indexRepository.upsert(chunks);
        await indexRepository.upsertMediaIndexState(
          VectorMediaIndexState(
            mediaId: video.id,
            signature: signature,
            modelVersion: runtime.runtimeName,
            framesPerVideo: framesPerVideo,
            frameCount: chunks.length,
            indexedAt: DateTime.now(),
          ),
        );
      }

      if (onProgress != null) {
        await onProgress((index + 1) / candidates.length);
      }
    }

    return frameCountByMediaId;
  }

  Future<List<VectorSearchHit>> search(
    String query, {
    int limit = 30,
    double minScore = 0.14,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];

    final queryVector = await runtime.embedText(normalized);
    return searchByVector(queryVector, limit: limit, minScore: minScore);
  }

  Future<List<VectorSearchHit>> searchByImagePath(
    String imagePath, {
    int limit = 30,
    double minScore = 0.14,
  }) async {
    final normalized = imagePath.trim();
    if (normalized.isEmpty) return const [];

    final queryVector = await runtime.embedImage(
      ImageEmbeddingInput(imagePath: normalized),
    );
    return searchByVector(queryVector, limit: limit, minScore: minScore);
  }

  Future<List<VectorSearchHit>> searchByVector(
    List<double> queryVector, {
    int limit = 30,
    double minScore = 0.14,
  }) async {
    if (queryVector.isEmpty) return const [];
    return indexRepository.query(queryVector, limit: limit, minScore: minScore);
  }

  Future<List<VideoEmbeddingChunk>> _buildSceneAwareChunks({
    required VideoItem video,
    required int framesPerVideo,
    required int candidateMultiplier,
    required double sceneSimilarityThreshold,
  }) async {
    final targetCount = math.max(1, framesPerVideo);
    final durationMs =
        (video.duration ?? const Duration(minutes: 2)).inMilliseconds;
    final candidateCount = math
        .max(targetCount, targetCount * math.max(1, candidateMultiplier))
        .toInt();
    final sampledFrames = _sampleFrameTimestamps(
      durationMs: durationMs,
      frameCount: candidateCount,
    );
    final selected = <VideoEmbeddingChunk>[];
    final fallbackPool = <_CandidateChunk>[];

    for (var index = 0; index < sampledFrames.length; index++) {
      final timestampMs = sampledFrames[index];
      try {
        final vector = await runtime.embedFrame(
          VideoFrameInput(
            mediaId: video.id,
            sourcePath: video.path,
            timestamp: Duration(milliseconds: timestampMs),
          ),
        );
        final chunk = VideoEmbeddingChunk(
          mediaId: video.id,
          frameTsMs: timestampMs,
          vector: vector,
          modelVersion: runtime.runtimeName,
        );
        if (selected.isEmpty) {
          selected.add(chunk);
          continue;
        }

        final maxSimilarity = _maxSimilarity(vector, selected);
        final remainingCandidates = sampledFrames.length - index - 1;
        final remainingSlots = targetCount - selected.length;
        final shouldForceFill = remainingCandidates < remainingSlots;
        if (maxSimilarity <= sceneSimilarityThreshold || shouldForceFill) {
          selected.add(chunk);
          if (selected.length >= targetCount) break;
        } else {
          fallbackPool.add(
            _CandidateChunk(chunk: chunk, novelty: 1.0 - maxSimilarity),
          );
        }
      } catch (_) {
        // Skip frames that fail extraction and continue indexing.
      }
    }

    if (selected.length < targetCount && fallbackPool.isNotEmpty) {
      fallbackPool.sort((a, b) => b.novelty.compareTo(a.novelty));
      for (final candidate in fallbackPool) {
        selected.add(candidate.chunk);
        if (selected.length >= targetCount) break;
      }
    }

    return selected;
  }

  double _maxSimilarity(
    List<double> candidateVector,
    List<VideoEmbeddingChunk> selected,
  ) {
    var maxSimilarity = -1.0;
    for (final chunk in selected) {
      final similarity = _cosine(candidateVector, chunk.vector);
      if (similarity > maxSimilarity) {
        maxSimilarity = similarity;
      }
    }
    return maxSimilarity;
  }

  List<int> _sampleFrameTimestamps({
    required int durationMs,
    required int frameCount,
  }) {
    final effectiveDuration = math.max(durationMs, 1000);
    final effectiveFrames = math.max(1, frameCount);
    final timestamps = <int>[];
    for (var i = 0; i < effectiveFrames; i++) {
      final progress = (i + 1) / (effectiveFrames + 1);
      timestamps.add((effectiveDuration * progress).round());
    }
    return timestamps;
  }

  double _cosine(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return -1.0;
    var dot = 0.0;
    var magA = 0.0;
    var magB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    if (magA <= 1e-9 || magB <= 1e-9) return -1.0;
    return dot / (math.sqrt(magA) * math.sqrt(magB));
  }

  String _videoSignature(VideoItem video) {
    return [
      video.path,
      video.size ?? -1,
      video.duration?.inMilliseconds ?? -1,
      video.dateModified?.millisecondsSinceEpoch ?? -1,
      video.mimeType ?? '',
    ].join('|');
  }

  Future<List<double>?> _buildFallbackVector(VideoItem video) async {
    final seedText = [
      video.name,
      video.mimeType ?? '',
      video.path,
      video.duration?.inMilliseconds ?? -1,
      video.size ?? -1,
    ].join(' ');
    try {
      final textVector = await runtime.embedText(seedText);
      if (textVector.isNotEmpty) {
        return textVector;
      }
    } catch (_) {
      // Fall through to deterministic fallback.
    }

    final dimensions = runtime.dimensions > 0 ? runtime.dimensions : 128;
    final random = math.Random(seedText.hashCode);
    final vector = List<double>.generate(
      dimensions,
      (_) => random.nextDouble() - 0.5,
    );
    final magnitude = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + (value * value)),
    );
    if (magnitude <= 1e-9) {
      return vector;
    }
    return vector.map((value) => value / magnitude).toList(growable: false);
  }
}

class _CandidateChunk {
  final VideoEmbeddingChunk chunk;
  final double novelty;

  const _CandidateChunk({required this.chunk, required this.novelty});
}
