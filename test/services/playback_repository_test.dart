import 'package:empty_player/models/playback_state.dart';
import 'package:empty_player/services/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPrefsPlaybackRepository', () {
    late SharedPrefsPlaybackRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repository = SharedPrefsPlaybackRepository();
    });

    test('saveState/getState round trip', () async {
      final state = PlaybackState(
        mediaId: 'FileMediaSource:/storage/emulated/0/Movies/test.mp4',
        sourceInput: '/storage/emulated/0/Movies/test.mp4',
        title: 'test.mp4',
        positionMs: 12000,
        durationMs: 60000,
        updatedAt: DateTime(2026, 1, 1),
        playCount: 3,
      );

      await repository.saveState(state);
      final loaded = await repository.getState(state.mediaId);

      expect(loaded, isNotNull);
      expect(loaded!.positionMs, 12000);
      expect(loaded.playCount, 3);
    });

    test('getRecentStates returns most recent first', () async {
      final older = PlaybackState(
        mediaId: 'a',
        sourceInput: 'a',
        title: 'A',
        positionMs: 1000,
        durationMs: 10000,
        updatedAt: DateTime(2026, 1, 1),
      );
      final newer = PlaybackState(
        mediaId: 'b',
        sourceInput: 'b',
        title: 'B',
        positionMs: 1000,
        durationMs: 10000,
        updatedAt: DateTime(2026, 1, 2),
      );

      await repository.saveState(older);
      await repository.saveState(newer);

      final recent = await repository.getRecentStates();
      expect(recent.length, 2);
      expect(recent.first.mediaId, 'b');
    });

    test('saveLastPlayed/getLastPlayed round trip', () async {
      final state = PlaybackState(
        mediaId: 'x',
        sourceInput: 'https://example.com/video.mp4',
        title: 'video',
        positionMs: 15000,
        durationMs: 75000,
        updatedAt: DateTime(2026, 1, 3),
      );

      await repository.saveLastPlayed(state);
      final loaded = await repository.getLastPlayed();

      expect(loaded, isNotNull);
      expect(loaded!.mediaId, 'x');
      expect(loaded.positionMs, 15000);
    });

    test('favorites can be toggled', () async {
      await repository.setFavorite('video-1', true);
      await repository.setFavorite('video-2', true);
      await repository.setFavorite('video-2', false);

      final favorites = await repository.getFavorites();
      expect(favorites.contains('video-1'), true);
      expect(favorites.contains('video-2'), false);
      expect(await repository.isFavorite('video-1'), true);
    });
  });
}
