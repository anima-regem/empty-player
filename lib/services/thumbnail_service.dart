import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// Service for fetching and caching video thumbnails.
/// Uses system-provided thumbnails via photo_manager for efficiency.
class ThumbnailService {
  // In-memory cache for thumbnails
  static final Map<String, Uint8List> _thumbnailCache = {};

  // Set to track thumbnails currently being loaded to avoid duplicate requests
  static final Set<String> _loadingThumbnails = {};

  // Thumbnail dimensions
  static const int thumbnailWidth = 200;
  static const int thumbnailHeight = 150;

  /// Gets the thumbnail for a video asset.
  /// Returns cached thumbnail if available, otherwise fetches from system.
  /// This method is non-blocking and will return null if thumbnail is not
  /// yet available. Use [loadThumbnail] to trigger background loading.
  static Uint8List? getCachedThumbnail(String? assetId) {
    if (assetId == null) return null;
    return _thumbnailCache[assetId];
  }

  /// Loads thumbnail for a video asset asynchronously.
  /// Returns the thumbnail data if successful, null otherwise.
  /// Results are cached for future use.
  static Future<Uint8List?> loadThumbnail(String? assetId) async {
    if (assetId == null) return null;

    // Return cached thumbnail if available
    if (_thumbnailCache.containsKey(assetId)) {
      return _thumbnailCache[assetId];
    }

    // Avoid duplicate loading requests
    if (_loadingThumbnails.contains(assetId)) {
      return null;
    }

    try {
      _loadingThumbnails.add(assetId);

      // Fetch the asset entity by ID
      final asset = await AssetEntity.fromId(assetId);
      if (asset == null) {
        return null;
      }

      // Get the thumbnail using system's native thumbnail generation
      final thumbnailData = await asset.thumbnailDataWithSize(
        const ThumbnailSize(thumbnailWidth, thumbnailHeight),
        quality: 80,
      );

      if (thumbnailData != null) {
        _thumbnailCache[assetId] = thumbnailData;
        return thumbnailData;
      }
    } catch (e) {
      debugPrint('Error loading thumbnail for $assetId: $e');
    } finally {
      _loadingThumbnails.remove(assetId);
    }

    return null;
  }

  /// Preloads thumbnails for a list of asset IDs in the background.
  /// This is useful for preloading thumbnails when entering a folder view.
  static Future<void> preloadThumbnails(List<String?> assetIds) async {
    final nonNullIds = assetIds.whereType<String>().toList();

    // Filter out already cached or loading thumbnails
    final toLoad = nonNullIds.where(
      (id) => !_thumbnailCache.containsKey(id) && !_loadingThumbnails.contains(id),
    ).toList();

    // Load thumbnails in parallel with concurrency limit
    const batchSize = 5;
    for (var i = 0; i < toLoad.length; i += batchSize) {
      final batch = toLoad.skip(i).take(batchSize);
      await Future.wait(batch.map((id) => loadThumbnail(id)));
    }
  }

  /// Clears the thumbnail cache.
  static void clearCache() {
    _thumbnailCache.clear();
    _loadingThumbnails.clear();
    debugPrint('Thumbnail cache cleared');
  }

  /// Gets the number of cached thumbnails.
  static int get cacheSize => _thumbnailCache.length;

  /// Checks if a thumbnail is currently being loaded.
  static bool isLoading(String? assetId) {
    if (assetId == null) return false;
    return _loadingThumbnails.contains(assetId);
  }
}
