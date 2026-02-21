import 'dart:convert';

import 'package:empty_player/models/playback_state.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LegacyMigrationV2 {
  static const String _legacyStatesKey = 'playback_states_v1';
  static const String _legacyLastPlayedKey = 'playback_last_played_v1';
  static const String _legacyFavoritesKey = 'playback_favorites_v1';
  static const String _migrationMetaKey = 'legacy_migration_v1_done';

  const LegacyMigrationV2();

  Future<void> run(Database db) async {
    final alreadyDone = await _isDone(db);
    if (alreadyDone) return;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final statesRaw = prefs.getString(_legacyStatesKey);
      final states = _decodeStates(statesRaw);

      for (final state in states) {
        await txn.insert('playback_state', <String, Object?>{
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

      final lastPlayedRaw = prefs.getString(_legacyLastPlayedKey);
      final lastPlayed = _decodeState(lastPlayedRaw);
      if (lastPlayed != null) {
        await txn.insert('playback_state', <String, Object?>{
          'media_id': lastPlayed.mediaId,
          'source_input': lastPlayed.sourceInput,
          'title': lastPlayed.title,
          'position_ms': lastPlayed.positionMs,
          'duration_ms': lastPlayed.durationMs,
          'play_count': lastPlayed.playCount,
          'last_played_at_ms': lastPlayed.updatedAt.millisecondsSinceEpoch,
          'updated_at_ms': lastPlayed.updatedAt.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final favorites =
          prefs.getStringList(_legacyFavoritesKey) ?? const <String>[];
      for (final mediaId in favorites) {
        await txn.insert('favorite', <String, Object?>{
          'media_id': mediaId,
          'created_at_ms': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.insert('search_index_meta', <String, Object?>{
        'key': _migrationMetaKey,
        'value_text': 'true',
        'updated_at_ms': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<bool> _isDone(Database db) async {
    final rows = await db.query(
      'search_index_meta',
      columns: <String>['value_text'],
      where: 'key = ?',
      whereArgs: <Object?>[_migrationMetaKey],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final value = rows.first['value_text'] as String?;
    return value == 'true';
  }

  List<PlaybackState> _decodeStates(String? raw) {
    if (raw == null || raw.isEmpty) return const <PlaybackState>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const <PlaybackState>[];
      }
      return decoded.values
          .whereType<Map>()
          .map(
            (entry) => PlaybackState.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false);
    } catch (_) {
      return const <PlaybackState>[];
    }
  }

  PlaybackState? _decodeState(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PlaybackState.fromJson(decoded);
      }
      if (decoded is Map) {
        return PlaybackState.fromJson(Map<String, dynamic>.from(decoded));
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
