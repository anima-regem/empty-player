import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabaseV2 {
  static const String _dbName = 'empty_player_v2.db';
  static const int _version = 1;

  Database? _db;

  Future<Database> open() async {
    if (_db != null) {
      return _db!;
    }

    final supportDir = await getApplicationSupportDirectory();
    final dbPath = p.join(supportDir.path, _dbName);
    _db = await openDatabase(dbPath, version: _version, onCreate: _onCreate);
    return _db!;
  }

  Future<void> close() async {
    if (_db == null) return;
    await _db!.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE media_item (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        path TEXT NOT NULL,
        mime_type TEXT,
        duration_ms INTEGER,
        size_bytes INTEGER,
        date_modified_ms INTEGER,
        last_indexed_at_ms INTEGER,
        indexed_frame_count INTEGER,
        visual_index_version TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_media_item_path ON media_item(path)');
    await db.execute(
      'CREATE INDEX idx_media_item_updated_at ON media_item(updated_at_ms DESC)',
    );

    await db.execute('''
      CREATE TABLE media_folder (
        path TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        video_count INTEGER NOT NULL DEFAULT 0,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE playback_state (
        media_id TEXT PRIMARY KEY,
        source_input TEXT NOT NULL,
        title TEXT NOT NULL,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        play_count INTEGER NOT NULL DEFAULT 0,
        last_played_at_ms INTEGER,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_playback_state_updated_at ON playback_state(updated_at_ms DESC)',
    );

    await db.execute('''
      CREATE TABLE playback_event (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        position_ms INTEGER,
        payload_json TEXT,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_playback_event_media ON playback_event(media_id, created_at_ms DESC)',
    );

    await db.execute('''
      CREATE TABLE favorite (
        media_id TEXT PRIMARY KEY,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE search_chunk (
        media_id TEXT NOT NULL,
        frame_ts_ms INTEGER NOT NULL,
        model_version TEXT NOT NULL,
        vector_json TEXT NOT NULL,
        ann_key TEXT NOT NULL,
        PRIMARY KEY (media_id, frame_ts_ms, model_version)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_search_chunk_ann_key ON search_chunk(ann_key)',
    );

    await db.execute('''
      CREATE TABLE search_index_meta (
        key TEXT PRIMARY KEY,
        value_text TEXT,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE session_resume (
        session_id TEXT PRIMARY KEY,
        media_id TEXT NOT NULL,
        source_input TEXT NOT NULL,
        title TEXT NOT NULL,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        is_playing INTEGER NOT NULL,
        is_minimized INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
  }
}
