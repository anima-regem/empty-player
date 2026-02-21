import 'dart:math' as math;

import 'package:empty_player/models/vector_search_hit.dart';
import 'package:empty_player/models/video_embedding_chunk.dart';

class VectorIndexStats {
  final int chunkCount;
  final int mediaCount;
  final int estimatedBytes;

  const VectorIndexStats({
    required this.chunkCount,
    required this.mediaCount,
    required this.estimatedBytes,
  });
}

abstract interface class VectorIndexRepository {
  Future<void> upsert(Iterable<VideoEmbeddingChunk> chunks);
  Future<List<VectorSearchHit>> query(
    List<double> queryVector, {
    int limit = 20,
    double minScore = 0.0,
  });
  Future<void> prune({required int maxChunks});
  Future<VectorIndexStats> stats();
}

class InMemoryVectorIndexRepository implements VectorIndexRepository {
  final Map<String, List<VideoEmbeddingChunk>> _chunksByMedia = {};

  @override
  Future<void> upsert(Iterable<VideoEmbeddingChunk> chunks) async {
    for (final chunk in chunks) {
      final mediaChunks = _chunksByMedia.putIfAbsent(chunk.mediaId, () => []);
      final existingIndex = mediaChunks.indexWhere(
        (entry) =>
            entry.frameTsMs == chunk.frameTsMs &&
            entry.modelVersion == chunk.modelVersion,
      );
      if (existingIndex >= 0) {
        mediaChunks[existingIndex] = chunk;
      } else {
        mediaChunks.add(chunk);
      }
    }
  }

  @override
  Future<List<VectorSearchHit>> query(
    List<double> queryVector, {
    int limit = 20,
    double minScore = 0.0,
  }) async {
    final hits = <VectorSearchHit>[];
    for (final entry in _chunksByMedia.entries) {
      double bestScore = -1.0;
      final matchedFrames = <int>[];
      for (final chunk in entry.value) {
        final score = _cosine(queryVector, chunk.vector);
        if (score > bestScore) {
          bestScore = score;
        }
        if (score >= minScore) {
          matchedFrames.add(chunk.frameTsMs);
        }
      }
      if (bestScore >= minScore) {
        hits.add(
          VectorSearchHit(
            mediaId: entry.key,
            score: bestScore,
            matchedFrames: matchedFrames..sort(),
          ),
        );
      }
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  @override
  Future<void> prune({required int maxChunks}) async {
    if (maxChunks < 1) {
      _chunksByMedia.clear();
      return;
    }

    final all = <VideoEmbeddingChunk>[];
    for (final chunks in _chunksByMedia.values) {
      all.addAll(chunks);
    }
    if (all.length <= maxChunks) return;

    all.sort((a, b) => a.frameTsMs.compareTo(b.frameTsMs));
    final retained = all.sublist(math.max(0, all.length - maxChunks));
    _chunksByMedia.clear();
    for (final chunk in retained) {
      _chunksByMedia.putIfAbsent(chunk.mediaId, () => []).add(chunk);
    }
  }

  @override
  Future<VectorIndexStats> stats() async {
    var chunks = 0;
    var estimatedBytes = 0;
    for (final values in _chunksByMedia.values) {
      chunks += values.length;
      for (final chunk in values) {
        estimatedBytes += chunk.vector.length * 8;
      }
    }
    return VectorIndexStats(
      chunkCount: chunks,
      mediaCount: _chunksByMedia.length,
      estimatedBytes: estimatedBytes,
    );
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
    if (magA == 0 || magB == 0) return -1.0;
    return dot / (math.sqrt(magA) * math.sqrt(magB));
  }
}
