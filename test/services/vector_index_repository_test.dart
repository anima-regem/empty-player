import 'package:empty_player/models/video_embedding_chunk.dart';
import 'package:empty_player/services/vector_index_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryVectorIndexRepository', () {
    late InMemoryVectorIndexRepository repository;

    setUp(() {
      repository = InMemoryVectorIndexRepository();
    });

    test('upsert + query returns best scoring hit first', () async {
      await repository.upsert([
        const VideoEmbeddingChunk(
          mediaId: 'a',
          frameTsMs: 1000,
          vector: [1, 0, 0],
          modelVersion: 'v1',
        ),
        const VideoEmbeddingChunk(
          mediaId: 'b',
          frameTsMs: 1200,
          vector: [0, 1, 0],
          modelVersion: 'v1',
        ),
      ]);

      final hits = await repository.query([1, 0, 0], limit: 5);
      expect(hits, isNotEmpty);
      expect(hits.first.mediaId, 'a');
      expect(hits.first.score, closeTo(1.0, 0.0001));
    });

    test('prune keeps newest chunks by frame timestamp', () async {
      await repository.upsert([
        const VideoEmbeddingChunk(
          mediaId: 'a',
          frameTsMs: 1000,
          vector: [1, 0],
          modelVersion: 'v1',
        ),
        const VideoEmbeddingChunk(
          mediaId: 'a',
          frameTsMs: 2000,
          vector: [1, 0],
          modelVersion: 'v1',
        ),
        const VideoEmbeddingChunk(
          mediaId: 'b',
          frameTsMs: 3000,
          vector: [0, 1],
          modelVersion: 'v1',
        ),
      ]);

      await repository.prune(maxChunks: 2);
      final stats = await repository.stats();
      expect(stats.chunkCount, 2);
    });

    test('media state and removeMediaNotIn keep index in sync', () async {
      await repository.upsert([
        const VideoEmbeddingChunk(
          mediaId: 'a',
          frameTsMs: 1000,
          vector: [1, 0],
          modelVersion: 'v1',
        ),
        const VideoEmbeddingChunk(
          mediaId: 'b',
          frameTsMs: 2000,
          vector: [0, 1],
          modelVersion: 'v1',
        ),
      ]);
      await repository.upsertMediaIndexState(
        VectorMediaIndexState(
          mediaId: 'a',
          signature: 'sig-a',
          modelVersion: 'v1',
          framesPerVideo: 2,
          frameCount: 2,
          indexedAt: DateTime.fromMillisecondsSinceEpoch(123),
        ),
      );
      await repository.upsertMediaIndexState(
        VectorMediaIndexState(
          mediaId: 'b',
          signature: 'sig-b',
          modelVersion: 'v1',
          framesPerVideo: 2,
          frameCount: 1,
          indexedAt: DateTime.fromMillisecondsSinceEpoch(456),
        ),
      );

      await repository.removeMediaNotIn({'a'});

      final stateA = await repository.getMediaIndexState('a');
      final stateB = await repository.getMediaIndexState('b');
      expect(stateA, isNotNull);
      expect(stateA!.signature, 'sig-a');
      expect(stateB, isNull);

      final stats = await repository.stats();
      expect(stats.mediaCount, 1);
    });
  });
}
