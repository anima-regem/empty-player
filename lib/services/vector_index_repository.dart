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

class VectorMediaIndexState {
  final String mediaId;
  final String signature;
  final String modelVersion;
  final int framesPerVideo;
  final int frameCount;
  final DateTime indexedAt;

  const VectorMediaIndexState({
    required this.mediaId,
    required this.signature,
    required this.modelVersion,
    required this.framesPerVideo,
    required this.frameCount,
    required this.indexedAt,
  });
}

abstract interface class VectorIndexRepository {
  Future<void> upsert(Iterable<VideoEmbeddingChunk> chunks);
  Future<Map<String, List<VideoEmbeddingChunk>>> getChunksByMediaIds(
    Set<String> mediaIds, {
    int perMediaLimit = 24,
  });
  Future<List<VectorSearchHit>> query(
    List<double> queryVector, {
    int limit = 20,
    double minScore = 0.0,
    bool approximate = true,
    int candidateLimit = 4000,
  });
  Future<VectorMediaIndexState?> getMediaIndexState(String mediaId);
  Future<void> upsertMediaIndexState(VectorMediaIndexState state);
  Future<void> deleteMedia(String mediaId);
  Future<void> removeMediaNotIn(Set<String> mediaIds);
  Future<void> prune({required int maxChunks});
  Future<VectorIndexStats> stats();
}

class InMemoryVectorIndexRepository implements VectorIndexRepository {
  final Map<String, List<_IndexedChunk>> _chunksByMedia = {};
  final Map<String, List<_IndexedChunk>> _annBuckets = {};
  final Map<String, VectorMediaIndexState> _mediaStateById = {};

  static const int _annBits = 12;

  @override
  Future<void> upsert(Iterable<VideoEmbeddingChunk> chunks) async {
    for (final chunk in chunks) {
      final mediaChunks = _chunksByMedia.putIfAbsent(chunk.mediaId, () => []);
      final existingIndex = mediaChunks.indexWhere(
        (entry) =>
            entry.chunk.frameTsMs == chunk.frameTsMs &&
            entry.chunk.modelVersion == chunk.modelVersion,
      );
      final indexed = _IndexedChunk(
        chunk: chunk,
        annKey: _annKey(chunk.vector),
      );

      if (existingIndex >= 0) {
        _removeFromBucket(mediaChunks[existingIndex]);
        mediaChunks[existingIndex] = indexed;
      } else {
        mediaChunks.add(indexed);
      }
      _annBuckets.putIfAbsent(indexed.annKey, () => []).add(indexed);
    }
  }

  @override
  Future<Map<String, List<VideoEmbeddingChunk>>> getChunksByMediaIds(
    Set<String> mediaIds, {
    int perMediaLimit = 24,
  }) async {
    if (mediaIds.isEmpty) {
      return const <String, List<VideoEmbeddingChunk>>{};
    }

    final result = <String, List<VideoEmbeddingChunk>>{};
    for (final mediaId in mediaIds) {
      final chunks = _chunksByMedia[mediaId];
      if (chunks == null || chunks.isEmpty) continue;
      final sorted = chunks.toList(growable: false)
        ..sort((a, b) => a.chunk.frameTsMs.compareTo(b.chunk.frameTsMs));
      final limited = sorted
          .take(math.max(1, perMediaLimit))
          .map((entry) => entry.chunk)
          .toList(growable: false);
      result[mediaId] = limited;
    }
    return result;
  }

  @override
  Future<List<VectorSearchHit>> query(
    List<double> queryVector, {
    int limit = 20,
    double minScore = 0.0,
    bool approximate = true,
    int candidateLimit = 4000,
  }) async {
    final candidates = _resolveCandidates(
      queryVector: queryVector,
      approximate: approximate,
      limit: limit,
      candidateLimit: candidateLimit,
    );

    final hitsByMedia = <String, _MutableHit>{};
    for (final indexed in candidates) {
      final score = _cosine(queryVector, indexed.chunk.vector);
      if (score < minScore) continue;

      final hit = hitsByMedia.putIfAbsent(
        indexed.chunk.mediaId,
        _MutableHit.new,
      );
      if (score > hit.bestScore) {
        hit.bestScore = score;
      }
      hit.matchedFrames.add(indexed.chunk.frameTsMs);
    }

    final hits = hitsByMedia.entries.map((entry) {
      final frames = entry.value.matchedFrames.toList()..sort();
      return VectorSearchHit(
        mediaId: entry.key,
        score: entry.value.bestScore,
        matchedFrames: frames,
      );
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    return hits.take(limit).toList(growable: false);
  }

  @override
  Future<VectorMediaIndexState?> getMediaIndexState(String mediaId) async {
    return _mediaStateById[mediaId];
  }

  @override
  Future<void> upsertMediaIndexState(VectorMediaIndexState state) async {
    _mediaStateById[state.mediaId] = state;
  }

  @override
  Future<void> deleteMedia(String mediaId) async {
    final removed = _chunksByMedia.remove(mediaId);
    if (removed != null) {
      for (final chunk in removed) {
        _removeFromBucket(chunk);
      }
    }
    _mediaStateById.remove(mediaId);
  }

  @override
  Future<void> removeMediaNotIn(Set<String> mediaIds) async {
    final staleChunkIds = _chunksByMedia.keys
        .where((mediaId) => !mediaIds.contains(mediaId))
        .toList(growable: false);
    for (final mediaId in staleChunkIds) {
      final removed = _chunksByMedia.remove(mediaId);
      if (removed != null) {
        for (final chunk in removed) {
          _removeFromBucket(chunk);
        }
      }
    }

    final staleStateIds = _mediaStateById.keys
        .where((mediaId) => !mediaIds.contains(mediaId))
        .toList(growable: false);
    for (final mediaId in staleStateIds) {
      _mediaStateById.remove(mediaId);
    }
  }

  @override
  Future<void> prune({required int maxChunks}) async {
    if (maxChunks < 1) {
      _chunksByMedia.clear();
      _annBuckets.clear();
      _mediaStateById.clear();
      return;
    }

    final all = <_IndexedChunk>[];
    for (final chunks in _chunksByMedia.values) {
      all.addAll(chunks);
    }
    if (all.length <= maxChunks) return;

    all.sort((a, b) => a.chunk.frameTsMs.compareTo(b.chunk.frameTsMs));
    final retained = all.sublist(math.max(0, all.length - maxChunks));
    _chunksByMedia.clear();
    _annBuckets.clear();
    for (final indexed in retained) {
      _chunksByMedia.putIfAbsent(indexed.chunk.mediaId, () => []).add(indexed);
      _annBuckets.putIfAbsent(indexed.annKey, () => []).add(indexed);
    }

    final activeMediaIds = _chunksByMedia.keys.toSet();
    final staleStateIds = _mediaStateById.keys
        .where((mediaId) => !activeMediaIds.contains(mediaId))
        .toList(growable: false);
    for (final mediaId in staleStateIds) {
      _mediaStateById.remove(mediaId);
    }
  }

  @override
  Future<VectorIndexStats> stats() async {
    var chunks = 0;
    var estimatedBytes = 0;
    for (final values in _chunksByMedia.values) {
      chunks += values.length;
      for (final indexed in values) {
        estimatedBytes += indexed.chunk.vector.length * 8;
      }
    }
    return VectorIndexStats(
      chunkCount: chunks,
      mediaCount: _chunksByMedia.length,
      estimatedBytes: estimatedBytes,
    );
  }

  Set<_IndexedChunk> _resolveCandidates({
    required List<double> queryVector,
    required bool approximate,
    required int limit,
    required int candidateLimit,
  }) {
    if (!approximate || _annBuckets.isEmpty) {
      return _allIndexedChunks();
    }

    final keys = _annCandidateKeys(queryVector);
    final candidates = <_IndexedChunk>{};
    for (final key in keys) {
      final bucket = _annBuckets[key];
      if (bucket == null || bucket.isEmpty) continue;
      for (final chunk in bucket) {
        candidates.add(chunk);
        if (candidates.length >= candidateLimit) {
          return candidates;
        }
      }
    }

    if (candidates.length < math.max(limit * 3, 40)) {
      return _allIndexedChunks();
    }
    return candidates;
  }

  Set<_IndexedChunk> _allIndexedChunks() {
    final chunks = <_IndexedChunk>{};
    for (final values in _chunksByMedia.values) {
      chunks.addAll(values);
    }
    return chunks;
  }

  void _removeFromBucket(_IndexedChunk chunk) {
    final bucket = _annBuckets[chunk.annKey];
    if (bucket == null) return;
    bucket.remove(chunk);
    if (bucket.isEmpty) {
      _annBuckets.remove(chunk.annKey);
    }
  }

  String _annKey(List<double> vector) {
    final bitCount = math.min(_annBits, vector.length);
    var mask = 0;
    for (var i = 0; i < bitCount; i++) {
      if (vector[i] >= 0) {
        mask |= (1 << i);
      }
    }
    return '$bitCount:$mask';
  }

  List<String> _annCandidateKeys(List<double> vector) {
    final bitCount = math.min(_annBits, vector.length);
    if (bitCount <= 0) return const [];

    var base = 0;
    for (var i = 0; i < bitCount; i++) {
      if (vector[i] >= 0) {
        base |= (1 << i);
      }
    }

    final keys = <String>{'$bitCount:$base'};
    for (var i = 0; i < bitCount; i++) {
      keys.add('$bitCount:${base ^ (1 << i)}');
    }
    return keys.toList(growable: false);
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

class _MutableHit {
  double bestScore = -1.0;
  final Set<int> matchedFrames = <int>{};
}

class _IndexedChunk {
  final VideoEmbeddingChunk chunk;
  final String annKey;

  const _IndexedChunk({required this.chunk, required this.annKey});
}
