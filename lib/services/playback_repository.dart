import 'dart:convert';

import 'package:empty_player/models/playback_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PlaybackRepository {
  Future<void> saveState(PlaybackState state);
  Future<PlaybackState?> getState(String mediaId);
  Future<List<PlaybackState>> getRecentStates({int limit = 20});
  Future<void> clearState(String mediaId);

  Future<void> saveLastPlayed(PlaybackState state);
  Future<PlaybackState?> getLastPlayed();

  Future<Set<String>> getFavorites();
  Future<bool> isFavorite(String mediaId);
  Future<void> setFavorite(String mediaId, bool isFavorite);
}

PlaybackRepository _activePlaybackRepository = SharedPrefsPlaybackRepository();

PlaybackRepository playbackRepository() => _activePlaybackRepository;

void configurePlaybackRepository(PlaybackRepository repository) {
  _activePlaybackRepository = repository;
}

class SharedPrefsPlaybackRepository implements PlaybackRepository {
  static const _statesKey = 'playback_states_v1';
  static const _lastPlayedKey = 'playback_last_played_v1';
  static const _favoritesKey = 'playback_favorites_v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<Map<String, dynamic>> _readStatesMap() async {
    final prefs = await _instance();
    final raw = prefs.getString(_statesKey);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeStatesMap(Map<String, dynamic> map) async {
    final prefs = await _instance();
    await prefs.setString(_statesKey, jsonEncode(map));
  }

  @override
  Future<void> saveState(PlaybackState state) async {
    final map = await _readStatesMap();
    map[state.mediaId] = state.toJson();
    await _writeStatesMap(map);
  }

  @override
  Future<PlaybackState?> getState(String mediaId) async {
    final map = await _readStatesMap();
    final state = map[mediaId];
    if (state is Map<String, dynamic>) {
      return PlaybackState.fromJson(state);
    }
    if (state is Map) {
      return PlaybackState.fromJson(Map<String, dynamic>.from(state));
    }
    return null;
  }

  @override
  Future<List<PlaybackState>> getRecentStates({int limit = 20}) async {
    final map = await _readStatesMap();
    final states =
        map.values
            .whereType<Map>()
            .map(
              (entry) =>
                  PlaybackState.fromJson(Map<String, dynamic>.from(entry)),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (states.length <= limit) {
      return states;
    }
    return states.take(limit).toList();
  }

  @override
  Future<void> clearState(String mediaId) async {
    final map = await _readStatesMap();
    map.remove(mediaId);
    await _writeStatesMap(map);
  }

  @override
  Future<void> saveLastPlayed(PlaybackState state) async {
    final prefs = await _instance();
    await prefs.setString(_lastPlayedKey, jsonEncode(state.toJson()));
  }

  @override
  Future<PlaybackState?> getLastPlayed() async {
    final prefs = await _instance();
    final raw = prefs.getString(_lastPlayedKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PlaybackState.fromJson(decoded);
      }
      if (decoded is Map) {
        return PlaybackState.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  @override
  Future<Set<String>> getFavorites() async {
    final prefs = await _instance();
    final values = prefs.getStringList(_favoritesKey) ?? const <String>[];
    return values.toSet();
  }

  @override
  Future<bool> isFavorite(String mediaId) async {
    final values = await getFavorites();
    return values.contains(mediaId);
  }

  @override
  Future<void> setFavorite(String mediaId, bool isFavorite) async {
    final prefs = await _instance();
    final values = await getFavorites();

    if (isFavorite) {
      values.add(mediaId);
    } else {
      values.remove(mediaId);
    }

    await prefs.setStringList(_favoritesKey, values.toList()..sort());
  }
}
