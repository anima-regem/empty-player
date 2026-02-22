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
    int maxVideos = 5000,
    int candidateMultiplier = 3,
    double sceneSimilarityThreshold = 0.86,
    bool includeTemporalAggregate = true,
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
      if (includeTemporalAggregate && sceneAwareChunks.length >= 3) {
        final aggregateChunk = _buildTemporalAggregateChunk(
          mediaId: video.id,
          chunks: sceneAwareChunks,
        );
        if (aggregateChunk != null) {
          chunks.add(aggregateChunk);
        }
      }

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
    final stage1Limit = math.max(limit * 6, limit);
    final stage1Hits = await indexRepository.query(
      queryVector,
      limit: stage1Limit,
      minScore: math.max(0, minScore * 0.60),
      approximate: true,
      candidateLimit: math.max(stage1Limit * 80, 1200),
    );
    if (stage1Hits.isEmpty) return const [];

    final candidateIds = stage1Hits.map((hit) => hit.mediaId).toSet();
    final chunksByMedia = await indexRepository.getChunksByMediaIds(
      candidateIds,
      perMediaLimit: 24,
    );

    final reranked = stage1Hits
        .map(
          (hit) => _rerankCandidate(
            queryVector: queryVector,
            stage1Hit: hit,
            chunks: chunksByMedia[hit.mediaId] ?? const <VideoEmbeddingChunk>[],
          ),
        )
        .where((hit) => hit.score >= minScore)
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));

    return reranked.take(limit).toList(growable: false);
  }

  Future<List<VideoEmbeddingChunk>> _buildSceneAwareChunks({
    required VideoItem video,
    required int framesPerVideo,
    required int candidateMultiplier,
    required double sceneSimilarityThreshold,
  }) async {
    final durationMs =
        (video.duration ?? const Duration(minutes: 2)).inMilliseconds;
    final targetCount = math.max(
      1,
      math.max(framesPerVideo, _durationAdaptiveFrameCount(durationMs)),
    );
    final candidateCount = math.max(
      targetCount,
      targetCount * math.max(1, candidateMultiplier),
    ).toInt();
    final sampledFrames = _sampleKeyframeTimestamps(
      durationMs: durationMs,
      frameCount: candidateCount,
    );
    final selected = <VideoEmbeddingChunk>[];
    final fallbackPool = <_CandidateChunk>[];
    final minTemporalSpacingMs = math.max(350, (durationMs / (targetCount * 3))
        .round());

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
        final minDistance = _minimumTimestampDistance(
          timestampMs,
          selected.map((chunk) => chunk.frameTsMs),
        );
        final remainingCandidates = sampledFrames.length - index - 1;
        final remainingSlots = targetCount - selected.length;
        final shouldForceFill = remainingCandidates < remainingSlots;
        final satisfiesNovelty = maxSimilarity <= sceneSimilarityThreshold;
        final satisfiesSpacing = minDistance >= minTemporalSpacingMs;
        if ((satisfiesNovelty && satisfiesSpacing) || shouldForceFill) {
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

  int _durationAdaptiveFrameCount(int durationMs) {
    final minutes = durationMs / 60000.0;
    if (minutes <= 3.0) return 2;
    if (minutes <= 10.0) return 4;
    if (minutes <= 30.0) return 8;
    return 12;
  }

  List<int> _sampleKeyframeTimestamps({
    required int durationMs,
    required int frameCount,
  }) {
    final effectiveDuration = math.max(durationMs, 1000);
    final effectiveFrames = math.max(1, frameCount);
    final timestamps = <int>{};

    for (var i = 0; i < effectiveFrames; i++) {
      final progress = (i + 1) / (effectiveFrames + 1);
      timestamps.add((effectiveDuration * progress).round());
    }

    timestamps.add((effectiveDuration * 0.08).round());
    timestamps.add((effectiveDuration * 0.50).round());
    timestamps.add((effectiveDuration * 0.92).round());

    final jitter = math.max(250, (effectiveDuration * 0.015).round());
    final base = timestamps.toList(growable: false);
    for (final ts in base) {
      timestamps.add((ts - jitter).clamp(0, effectiveDuration).toInt());
      timestamps.add((ts + jitter).clamp(0, effectiveDuration).toInt());
    }

    final ordered = timestamps.toList(growable: false)..sort();
    if (ordered.length <= effectiveFrames) {
      return ordered;
    }

    final reduced = <int>{};
    final stride = ordered.length / effectiveFrames;
    for (var i = 0; i < effectiveFrames; i++) {
      final index = (i * stride).floor().clamp(0, ordered.length - 1);
      reduced.add(ordered[index]);
    }
    final compact = reduced.toList(growable: false)..sort();
    return compact;
  }

  int _minimumTimestampDistance(int ts, Iterable<int> existing) {
    var minimum = 1 << 30;
    for (final value in existing) {
      final delta = (value - ts).abs();
      if (delta < minimum) {
        minimum = delta;
      }
    }
    if (minimum == (1 << 30)) {
      return minimum;
    }
    return minimum;
  }

  VideoEmbeddingChunk? _buildTemporalAggregateChunk({
    required String mediaId,
    required List<VideoEmbeddingChunk> chunks,
  }) {
    if (chunks.isEmpty) return null;
    final dimension = chunks.first.vector.length;
    if (dimension <= 0) return null;

    final aggregate = List<double>.filled(dimension, 0);
    var contributors = 0;
    for (final chunk in chunks) {
      if (chunk.vector.length != dimension) continue;
      for (var i = 0; i < dimension; i++) {
        aggregate[i] += chunk.vector[i];
      }
      contributors += 1;
    }
    if (contributors <= 0) return null;

    for (var i = 0; i < aggregate.length; i++) {
      aggregate[i] /= contributors;
    }
    final normalized = _normalize(aggregate);
    return VideoEmbeddingChunk(
      mediaId: mediaId,
      frameTsMs: -1,
      vector: normalized,
      modelVersion: runtime.runtimeName,
    );
  }

  VectorSearchHit _rerankCandidate({
    required List<double> queryVector,
    required VectorSearchHit stage1Hit,
    required List<VideoEmbeddingChunk> chunks,
  }) {
    if (chunks.isEmpty) {
      return stage1Hit;
    }

    final scoredFrames = <_ScoredFrame>[];
    double? aggregateSimilarity;
    for (final chunk in chunks) {
      final score = _cosine(queryVector, chunk.vector);
      if (score < -0.99) continue;
      if (chunk.frameTsMs < 0) {
        aggregateSimilarity = score;
      } else {
        scoredFrames.add(_ScoredFrame(tsMs: chunk.frameTsMs, score: score));
      }
    }
    if (scoredFrames.isEmpty) {
      return stage1Hit;
    }
    scoredFrames.sort((a, b) => b.score.compareTo(a.score));
    final topCount = math.min(3, scoredFrames.length);
    final topMean = scoredFrames
            .take(topCount)
            .fold<double>(0, (sum, frame) => sum + frame.score) /
        topCount;
    final maxScore = scoredFrames.first.score;
    final temporalCoverage = _temporalCoverage(
      scoredFrames.take(6).map((frame) => frame.tsMs).toList(growable: false),
    );
    final aggregate = aggregateSimilarity ?? topMean;

    final rerankScore =
        (0.62 * maxScore) +
        (0.23 * topMean) +
        (0.10 * aggregate) +
        (0.05 * temporalCoverage);
    final finalScore = (0.50 * stage1Hit.score) + (0.50 * rerankScore);
    final matchedFrames = scoredFrames
        .take(6)
        .map((frame) => frame.tsMs)
        .toList(growable: false);
    return VectorSearchHit(
      mediaId: stage1Hit.mediaId,
      score: finalScore,
      matchedFrames: matchedFrames,
    );
  }

  double _temporalCoverage(List<int> timestamps) {
    if (timestamps.length < 2) return 0;
    final sorted = timestamps.toList(growable: false)..sort();
    final minTs = sorted.first;
    final maxTs = sorted.last;
    if (maxTs <= 0) return 0;
    return ((maxTs - minTs) / maxTs).clamp(0.0, 1.0).toDouble();
  }

  List<double> _normalize(List<double> vector) {
    final magnitude = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + (value * value)),
    );
    if (magnitude <= 1e-9) {
      return vector;
    }
    return vector.map((value) => value / magnitude).toList(growable: false);
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

class _ScoredFrame {
  final int tsMs;
  final double score;

  const _ScoredFrame({required this.tsMs, required this.score});
}
