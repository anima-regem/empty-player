import 'package:empty_player/services/playback_repository.dart';
import 'package:empty_player/v2/storage/app_database_v2.dart';
import 'package:empty_player/v2/storage/legacy_migration_v2.dart';
import 'package:empty_player/v2/storage/playback_repository_v2.dart';

class AppBootstrapV2 {
  AppBootstrapV2._();

  static final AppDatabaseV2 _database = AppDatabaseV2();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    final db = await _database.open();
    await const LegacyMigrationV2().run(db);

    configurePlaybackRepository(DbPlaybackRepositoryV2(database: _database));
    _initialized = true;
  }
}
