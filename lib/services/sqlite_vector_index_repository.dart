import 'dart:convert';
import 'dart:math' as math;

import 'package:empty_player/models/vector_search_hit.dart';
import 'package:empty_player/models/video_embedding_chunk.dart';
import 'package:empty_player/services/vector_index_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class SqliteVectorIndexRepository implements VectorIndexRepository {
  final String databaseName;
  Database? _database;

  static const int _annBits = 12;

  SqliteVectorIndexRepository({this.databaseName = 'vector_index_v1.db'});

  Future<Database> _db() async {
    if (_database != null) {
      await _backfillAnnKeysIfNeeded(_database!);
      return _database!;
    }

    final supportDir = await getApplicationSupportDirectory();
    final path = p.join(supportDir.path, databaseName);
    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE embedding_chunks (
            media_id TEXT NOT NULL,
            frame_ts_ms INTEGER NOT NULL,
            model_version TEXT NOT NULL,
            vector_json TEXT NOT NULL,
            ann_key TEXT NOT NULL,
            PRIMARY KEY (media_id, frame_ts_ms, model_version)
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_embedding_chunks_media ON embedding_chunks(media_id)',
        );
        await db.execute(
          'CREATE INDEX idx_embedding_chunks_ann_key ON embedding_chunks(ann_key)',
        );

        await db.execute('''
          CREATE TABLE indexed_media (
            media_id TEXT PRIMARY KEY,
            signature TEXT NOT NULL,
            model_version TEXT NOT NULL,
            frames_per_video INTEGER NOT NULL,
            frame_count INTEGER NOT NULL,
            indexed_at_ms INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE embedding_chunks ADD COLUMN ann_key TEXT',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_embedding_chunks_ann_key ON embedding_chunks(ann_key)',
          );
        }
      },
    );
    await _backfillAnnKeysIfNeeded(_database!);
    return _database!;
  }

  @override
  Future<void> upsert(Iterable<VideoEmbeddingChunk> chunks) async {
    final db = await _db();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final chunk in chunks) {
        batch.insert('embedding_chunks', <String, Object?>{
          'media_id': chunk.mediaId,
          'frame_ts_ms': chunk.frameTsMs,
          'model_version': chunk.modelVersion,
          'vector_json': jsonEncode(chunk.vector),
          'ann_key': _annKey(chunk.vector),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<VectorSearchHit>> query(
    List<double> queryVector, {
    int limit = 20,
    double minScore = 0.0,
    bool approximate = true,
    int candidateLimit = 4000,
  }) async {
    final db = await _db();
    final rows = await _loadCandidateRows(
      db,
      queryVector: queryVector,
      approximate: approximate,
      candidateLimit: candidateLimit,
      minResults: math.max(limit * 3, 50),
    );

    final hitsByMedia = <String, _MutableHit>{};
    for (final row in rows) {
      final mediaId = row['media_id'] as String;
      final frameTsMs = (row['frame_ts_ms'] as num).toInt();
      final vector = _vectorFromJson(row['vector_json'] as String);
      final score = _cosine(queryVector, vector);
      if (score < minScore) continue;

      final current = hitsByMedia.putIfAbsent(mediaId, _MutableHit.new);
      if (score > current.bestScore) {
        current.bestScore = score;
      }
      current.matchedFrames.add(frameTsMs);
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
    final db = await _db();
    final rows = await db.query(
      'indexed_media',
      where: 'media_id = ?',
      whereArgs: [mediaId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return VectorMediaIndexState(
      mediaId: row['media_id'] as String,
      signature: row['signature'] as String,
      modelVersion: row['model_version'] as String,
      framesPerVideo: (row['frames_per_video'] as num).toInt(),
      frameCount: (row['frame_count'] as num).toInt(),
      indexedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['indexed_at_ms'] as num).toInt(),
      ),
    );
  }

  @override
  Future<void> upsertMediaIndexState(VectorMediaIndexState state) async {
    final db = await _db();
    await db.insert('indexed_media', <String, Object?>{
      'media_id': state.mediaId,
      'signature': state.signature,
      'model_version': state.modelVersion,
      'frames_per_video': state.framesPerVideo,
      'frame_count': state.frameCount,
      'indexed_at_ms': state.indexedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteMedia(String mediaId) async {
    final db = await _db();
    await db.transaction((txn) async {
      await txn.delete(
        'embedding_chunks',
        where: 'media_id = ?',
        whereArgs: [mediaId],
      );
      await txn.delete(
        'indexed_media',
        where: 'media_id = ?',
        whereArgs: [mediaId],
      );
    });
  }

  @override
  Future<void> removeMediaNotIn(Set<String> mediaIds) async {
    final db = await _db();
    if (mediaIds.isEmpty) {
      await db.transaction((txn) async {
        await txn.delete('embedding_chunks');
        await txn.delete('indexed_media');
      });
      return;
    }

    final knownRows = await db.rawQuery('''
      SELECT DISTINCT media_id FROM embedding_chunks
      UNION
      SELECT media_id FROM indexed_media
    ''');
    final staleIds = knownRows
        .map((row) => row['media_id'] as String)
        .where((mediaId) => !mediaIds.contains(mediaId))
        .toList(growable: false);

    if (staleIds.isEmpty) return;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final mediaId in staleIds) {
        batch.delete(
          'embedding_chunks',
          where: 'media_id = ?',
          whereArgs: [mediaId],
        );
        batch.delete(
          'indexed_media',
          where: 'media_id = ?',
          whereArgs: [mediaId],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> prune({required int maxChunks}) async {
    final db = await _db();
    if (maxChunks < 1) {
      await db.transaction((txn) async {
        await txn.delete('embedding_chunks');
        await txn.delete('indexed_media');
      });
      return;
    }

    final keepRows = await db.rawQuery(
      'SELECT rowid FROM embedding_chunks ORDER BY rowid DESC LIMIT ?',
      [maxChunks],
    );
    final keepIds = keepRows
        .map((row) => (row['rowid'] as num).toInt())
        .toList(growable: false);

    await db.transaction((txn) async {
      if (keepIds.isEmpty) {
        await txn.delete('embedding_chunks');
      } else {
        final placeholders = List.filled(keepIds.length, '?').join(',');
        await txn.rawDelete(
          'DELETE FROM embedding_chunks WHERE rowid NOT IN ($placeholders)',
          keepIds,
        );
      }
      await txn.rawDelete('''
        DELETE FROM indexed_media
        WHERE media_id NOT IN (SELECT DISTINCT media_id FROM embedding_chunks)
      ''');
    });
  }

  @override
  Future<VectorIndexStats> stats() async {
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS chunk_count,
        COUNT(DISTINCT media_id) AS media_count,
        COALESCE(SUM(LENGTH(vector_json)), 0) AS estimated_bytes
      FROM embedding_chunks
    ''');
    final row = rows.first;
    return VectorIndexStats(
      chunkCount: (row['chunk_count'] as num).toInt(),
      mediaCount: (row['media_count'] as num).toInt(),
      estimatedBytes: (row['estimated_bytes'] as num).toInt(),
    );
  }

  Future<List<Map<String, Object?>>> _loadCandidateRows(
    Database db, {
    required List<double> queryVector,
    required bool approximate,
    required int candidateLimit,
    required int minResults,
  }) async {
    if (!approximate) {
      return db.query(
        'embedding_chunks',
        columns: ['media_id', 'frame_ts_ms', 'vector_json'],
      );
    }

    final annKeys = _annCandidateKeys(queryVector);
    if (annKeys.isEmpty) {
      return db.query(
        'embedding_chunks',
        columns: ['media_id', 'frame_ts_ms', 'vector_json'],
      );
    }

    final placeholders = List.filled(annKeys.length, '?').join(',');
    final approxRows = await db.rawQuery(
      'SELECT media_id, frame_ts_ms, vector_json FROM embedding_chunks '
      'WHERE ann_key IN ($placeholders) LIMIT ?',
      [...annKeys, candidateLimit],
    );

    if (approxRows.length >= minResults) {
      return approxRows;
    }

    return db.query(
      'embedding_chunks',
      columns: ['media_id', 'frame_ts_ms', 'vector_json'],
    );
  }

  Future<void> _backfillAnnKeysIfNeeded(Database db) async {
    final rows = await db.query(
      'embedding_chunks',
      columns: ['media_id', 'frame_ts_ms', 'model_version', 'vector_json'],
      where: 'ann_key IS NULL OR ann_key = ?',
      whereArgs: [''],
      limit: 1500,
    );
    if (rows.isEmpty) return;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        final mediaId = row['media_id'] as String;
        final frameTsMs = (row['frame_ts_ms'] as num).toInt();
        final modelVersion = row['model_version'] as String;
        final vector = _vectorFromJson(row['vector_json'] as String);
        batch.rawUpdate(
          'UPDATE embedding_chunks SET ann_key = ? '
          'WHERE media_id = ? AND frame_ts_ms = ? AND model_version = ?',
          [_annKey(vector), mediaId, frameTsMs, modelVersion],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  List<double> _vectorFromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .map((value) => (value as num).toDouble())
        .toList(growable: false);
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
