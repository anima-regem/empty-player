import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:empty_player/services/thumbnail_service.dart';

void main() {
  group('ThumbnailService', () {
    setUp(() {
      // Clear cache before each test
      ThumbnailService.clearCache();
    });

    test('getCachedThumbnail returns null for null assetId', () {
      final result = ThumbnailService.getCachedThumbnail(null);
      expect(result, isNull);
    });

    test('getCachedThumbnail returns null for uncached assetId', () {
      final result = ThumbnailService.getCachedThumbnail('uncached_asset');
      expect(result, isNull);
    });

    test('cacheSize returns 0 initially', () {
      expect(ThumbnailService.cacheSize, 0);
    });

    test('clearCache resets cache size to 0', () {
      ThumbnailService.clearCache();
      expect(ThumbnailService.cacheSize, 0);
    });

    test('isLoading returns false for null assetId', () {
      expect(ThumbnailService.isLoading(null), false);
    });

    test('isLoading returns false for non-loading assetId', () {
      expect(ThumbnailService.isLoading('some_asset'), false);
    });

    test('loadThumbnail returns null for null assetId', () async {
      final result = await ThumbnailService.loadThumbnail(null);
      expect(result, isNull);
    });

    test('thumbnailWidth and thumbnailHeight are reasonable values', () {
      // These are the default sizes used for thumbnails
      expect(ThumbnailService.thumbnailWidth, greaterThan(0));
      expect(ThumbnailService.thumbnailHeight, greaterThan(0));
    });
  });
}
