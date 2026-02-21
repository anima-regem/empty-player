import 'package:empty_player/models/index_job_state.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EmbeddingIndexCommand { fullRebuild }

class EmbeddingIndexMetadata {
  final DateTime? lastRunAt;
  final int indexedVideos;
  final int indexedFrames;

  const EmbeddingIndexMetadata({
    required this.lastRunAt,
    required this.indexedVideos,
    required this.indexedFrames,
  });

  static const empty = EmbeddingIndexMetadata(
    lastRunAt: null,
    indexedVideos: 0,
    indexedFrames: 0,
  );
}

class _EmbeddingCommandNotifier extends ChangeNotifier {
  void emit() => notifyListeners();
}

class EmbeddingIndexStatusService {
  static const _keyLastRunAtMs = 'embedding_index_last_run_at_ms_v1';
  static const _keyIndexedVideos = 'embedding_index_videos_v1';
  static const _keyIndexedFrames = 'embedding_index_frames_v1';

  EmbeddingIndexStatusService._();

  static final EmbeddingIndexStatusService instance =
      EmbeddingIndexStatusService._();

  final ValueNotifier<IndexJobState> _state = ValueNotifier<IndexJobState>(
    IndexJobState.idle,
  );
  final ValueNotifier<EmbeddingIndexMetadata> _metadata =
      ValueNotifier<EmbeddingIndexMetadata>(EmbeddingIndexMetadata.empty);
  final _EmbeddingCommandNotifier _commands = _EmbeddingCommandNotifier();

  SharedPreferences? _prefs;
  bool _initialized = false;
  int _commandVersion = 0;

  ValueListenable<IndexJobState> get state => _state;
  ValueListenable<EmbeddingIndexMetadata> get metadata => _metadata;

  Listenable get commands => _commands;
  int get commandVersion => _commandVersion;

  Future<void> ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (_initialized) return;
    _initialized = true;
    final lastRunAtMs = _prefs?.getInt(_keyLastRunAtMs);
    final lastRunAt = lastRunAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastRunAtMs);
    _metadata.value = EmbeddingIndexMetadata(
      lastRunAt: lastRunAt,
      indexedVideos: _prefs?.getInt(_keyIndexedVideos) ?? 0,
      indexedFrames: _prefs?.getInt(_keyIndexedFrames) ?? 0,
    );
  }

  void update(IndexJobState state) {
    _state.value = state;
  }

  void requestFullRebuild() {
    _commandVersion += 1;
    _commands.emit();
  }

  Future<void> saveMetadata({
    required DateTime lastRunAt,
    required int indexedVideos,
    required int indexedFrames,
  }) async {
    await ensureInitialized();
    _metadata.value = EmbeddingIndexMetadata(
      lastRunAt: lastRunAt,
      indexedVideos: indexedVideos,
      indexedFrames: indexedFrames,
    );
    await _prefs?.setInt(_keyLastRunAtMs, lastRunAt.millisecondsSinceEpoch);
    await _prefs?.setInt(_keyIndexedVideos, indexedVideos);
    await _prefs?.setInt(_keyIndexedFrames, indexedFrames);
  }
}
