import 'package:empty_player/models/playback_state.dart';
import 'package:empty_player/services/playback_repository.dart';
import 'package:empty_player/v2/storage/app_database_v2.dart';
import 'package:sqflite/sqflite.dart';

class DbPlaybackRepositoryV2 implements PlaybackRepository {
  final AppDatabaseV2 database;
  Database? _db;

  DbPlaybackRepositoryV2({required this.database});

  Future<Database> _instance() async {
    _db ??= await database.open();
    return _db!;
  }

  @override
  Future<void> saveState(PlaybackState state) async {
    final db = await _instance();
    await db.insert('playback_state', <String, Object?>{
      'media_id': state.mediaId,
      'source_input': state.sourceInput,
      'title': state.title,
      'position_ms': state.positionMs,
      'duration_ms': state.durationMs,
      'play_count': state.playCount,
      'last_played_at_ms': state.updatedAt.millisecondsSinceEpoch,
      'updated_at_ms': state.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<PlaybackState?> getState(String mediaId) async {
    final db = await _instance();
    final rows = await db.query(
      'playback_state',
      where: 'media_id = ?',
      whereArgs: <Object?>[mediaId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromPlaybackRow(rows.first);
  }

  @override
  Future<List<PlaybackState>> getRecentStates({int limit = 20}) async {
    final db = await _instance();
    final rows = await db.query(
      'playback_state',
      orderBy: 'updated_at_ms DESC',
      limit: limit,
    );
    return rows.map(_fromPlaybackRow).toList(growable: false);
  }

  @override
  Future<void> clearState(String mediaId) async {
    final db = await _instance();
    await db.delete(
      'playback_state',
      where: 'media_id = ?',
      whereArgs: <Object?>[mediaId],
    );
  }

  @override
  Future<void> saveLastPlayed(PlaybackState state) async {
    final db = await _instance();
    await db.insert('search_index_meta', <String, Object?>{
      'key': 'last_played_media_id_v2',
      'value_text': state.mediaId,
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await saveState(state);
  }

  @override
  Future<PlaybackState?> getLastPlayed() async {
    final db = await _instance();
    final lastPlayedMeta = await db.query(
      'search_index_meta',
      columns: <String>['value_text'],
      where: 'key = ?',
      whereArgs: const <Object?>['last_played_media_id_v2'],
      limit: 1,
    );

    if (lastPlayedMeta.isNotEmpty) {
      final mediaId = lastPlayedMeta.first['value_text'] as String?;
      if (mediaId != null && mediaId.isNotEmpty) {
        final state = await getState(mediaId);
        if (state != null) return state;
      }
    }

    final rows = await db.query(
      'playback_state',
      orderBy: 'last_played_at_ms DESC, updated_at_ms DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromPlaybackRow(rows.first);
  }

  @override
  Future<Set<String>> getFavorites() async {
    final db = await _instance();
    final rows = await db.query(
      'favorite',
      columns: <String>['media_id'],
      orderBy: 'media_id ASC',
    );
    return rows.map((row) => row['media_id']).whereType<String>().toSet();
  }

  @override
  Future<bool> isFavorite(String mediaId) async {
    final db = await _instance();
    final rows = await db.query(
      'favorite',
      columns: <String>['media_id'],
      where: 'media_id = ?',
      whereArgs: <Object?>[mediaId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> setFavorite(String mediaId, bool isFavorite) async {
    final db = await _instance();
    if (isFavorite) {
      await db.insert('favorite', <String, Object?>{
        'media_id': mediaId,
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }

    await db.delete(
      'favorite',
      where: 'media_id = ?',
      whereArgs: <Object?>[mediaId],
    );
  }

  PlaybackState _fromPlaybackRow(Map<String, Object?> row) {
    final mediaId = row['media_id'] as String;
    final sourceInput = row['source_input'] as String? ?? mediaId;
    final title = row['title'] as String? ?? 'Unknown';
    final positionMs = (row['position_ms'] as num?)?.toInt() ?? 0;
    final durationMs = (row['duration_ms'] as num?)?.toInt() ?? 0;
    final playCount = (row['play_count'] as num?)?.toInt() ?? 0;
    final updatedAtMs =
        (row['updated_at_ms'] as num?)?.toInt() ??
        DateTime.fromMillisecondsSinceEpoch(0).millisecondsSinceEpoch;

    return PlaybackState(
      mediaId: mediaId,
      sourceInput: sourceInput,
      title: title,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      playCount: playCount,
    );
  }
}
