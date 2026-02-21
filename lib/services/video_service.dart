import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:empty_player/models/video_item.dart';
import 'package:path/path.dart' as path;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoService {
  static const String _cacheKey = 'video_cache';
  static const String _cacheTimestampKey = 'video_cache_timestamp';
  static const String _cacheSchemaVersionKey = 'video_cache_schema_version';
  static const String _cacheProbeCountKey = 'video_cache_probe_count_v1';
  static const String _cacheProbeSignatureKey =
      'video_cache_probe_signature_v1';
  static const int _currentCacheSchemaVersion = 3;
  static const Duration _cacheExpiry = Duration(hours: 24);
  static const int _scanPageSize = 300;

  // List of valid video file extensions
  static const List<String> _validVideoExtensions = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
    '.3gp',
    '.3g2',
    '.mpg',
    '.mpeg',
    '.m2v',
    '.m4p',
    '.ogv',
    '.ts',
    '.mts',
    '.m2ts',
  ];

  static const Map<String, String> _mimeByExtension = {
    '.mp4': 'video/mp4',
    '.mkv': 'video/x-matroska',
    '.avi': 'video/x-msvideo',
    '.mov': 'video/quicktime',
    '.wmv': 'video/x-ms-wmv',
    '.flv': 'video/x-flv',
    '.webm': 'video/webm',
    '.m4v': 'video/x-m4v',
    '.3gp': 'video/3gpp',
    '.3g2': 'video/3gpp2',
    '.mpg': 'video/mpeg',
    '.mpeg': 'video/mpeg',
    '.m2v': 'video/mpeg',
    '.m4p': 'video/mp4',
    '.ogv': 'video/ogg',
    '.ts': 'video/mp2t',
    '.mts': 'video/mp2t',
    '.m2ts': 'video/mp2t',
  };

  /// Check if a file path has a valid video extension.
  /// Returns false if the file path is null or empty.
  static bool _isValidVideoFile(String filePath) {
    if (filePath.isEmpty) return false;
    final extension = path.extension(filePath).toLowerCase();
    return _validVideoExtensions.contains(extension);
  }

  static String? _inferMimeType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return _mimeByExtension[extension];
  }

  /// Check if we have storage permissions
  static Future<bool> checkPermission() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        // Android 13+ (API 33+)
        if (sdkInt >= 33) {
          final status = await Permission.videos.status;
          return status.isGranted;
        } else {
          // Android 12 and below
          final status = await Permission.storage.status;
          return status.isGranted;
        }
      } else if (Platform.isIOS) {
        final status = await Permission.photos.status;
        return status.isGranted;
      }
    } catch (e) {
      debugPrint('Error checking permission: $e');
    }
    return false;
  }

  /// Request storage permissions
  static Future<PermissionStatus> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        // Android 13+ (API 33+) - use READ_MEDIA_VIDEO
        if (sdkInt >= 33) {
          final status = await Permission.videos.request();
          debugPrint('Android 13+ video permission status: $status');
          return status;
        } else {
          // Android 12 and below - use READ_EXTERNAL_STORAGE
          final status = await Permission.storage.request();
          debugPrint('Android 12- storage permission status: $status');
          return status;
        }
      } else if (Platform.isIOS) {
        final status = await Permission.photos.request();
        return status;
      }
    } catch (e) {
      debugPrint('Error requesting permission: $e');
    }
    return PermissionStatus.denied;
  }

  /// Request storage permissions (deprecated - use requestPermission)
  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await Permission.storage.status;

      // For Android 13+ (API 33+), use photos/videos permissions
      if (Platform.version.contains('13') ||
          Platform.version.contains('14') ||
          Platform.version.contains('15')) {
        final videosStatus = await Permission.videos.request();
        return videosStatus.isGranted;
      } else {
        // For Android 12 and below
        if (androidInfo.isDenied) {
          final result = await Permission.storage.request();
          return result.isGranted;
        }
        return androidInfo.isGranted;
      }
    } else if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted;
    }
    return false;
  }

  /// Save video cache to SharedPreferences
  static Future<void> _saveCache(
    List<VideoItem> videos, {
    required _LibraryProbe probe,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = videos.map((v) => v.toJson()).toList();
      await prefs.setString(_cacheKey, jsonEncode(jsonList));
      await prefs.setInt(
        _cacheTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setInt(_cacheSchemaVersionKey, _currentCacheSchemaVersion);
      await prefs.setInt(_cacheProbeCountKey, probe.uniqueAssetCount);
      await prefs.setInt(_cacheProbeSignatureKey, probe.signature);
    } catch (e) {
      debugPrint('Error saving cache: $e');
    }
  }

  /// Load video cache from SharedPreferences
  static Future<List<VideoItem>?> _loadCache({
    required _LibraryProbe probe,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey);
      final cacheVersion =
          prefs.getInt(_cacheSchemaVersionKey) ?? _currentCacheSchemaVersion;
      final cachedProbeCount = prefs.getInt(_cacheProbeCountKey);
      final cachedProbeSignature = prefs.getInt(_cacheProbeSignatureKey);

      if (timestamp == null) return null;
      if (cacheVersion != _currentCacheSchemaVersion) {
        return null;
      }
      if (cachedProbeCount == null || cachedProbeSignature == null) {
        return null;
      }
      if (cachedProbeCount != probe.uniqueAssetCount ||
          cachedProbeSignature != probe.signature) {
        return null;
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        // Cache expired
        return null;
      }

      final jsonString = prefs.getString(_cacheKey);
      if (jsonString == null) return null;

      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((json) => VideoItem.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading cache: $e');
      return null;
    }
  }

  /// Clear video cache
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      await prefs.remove(_cacheSchemaVersionKey);
      await prefs.remove(_cacheProbeCountKey);
      await prefs.remove(_cacheProbeSignatureKey);
      debugPrint('Video cache cleared');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  /// Scan all videos from device using photo_manager
  static Future<List<VideoItem>> scanAllVideos() async {
    try {
      final probe = await _buildLibraryProbe();
      // Try to load from cache first
      final cachedVideos = await _loadCache(probe: probe);
      if (cachedVideos != null && cachedVideos.isNotEmpty) {
        debugPrint('Loaded ${cachedVideos.length} videos from cache');
        return cachedVideos;
      }

      debugPrint('Scanning videos from device...');
      // Don't check permission here - assume it's already granted
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        hasAll: true,
      );

      final allVideos = <VideoItem>[];
      final seenAssetIds = <String>{};
      final seenPaths = <String>{};
      int processedCount = 0;

      for (final album in albums) {
        var page = 0;
        while (true) {
          final assets = await album.getAssetListPaged(
            page: page,
            size: _scanPageSize,
          );
          if (assets.isEmpty) break;

          for (final asset in assets) {
            if (!seenAssetIds.add(asset.id)) {
              continue;
            }
            processedCount++;

            if (processedCount % 100 == 0) {
              debugPrint('Processing: $processedCount videos');
            }

            try {
              final file = await asset.file;
              if (file == null) continue;
              final normalizedPath = file.path.trim();
              if (normalizedPath.isEmpty) continue;
              if (!seenPaths.add(normalizedPath)) {
                continue;
              }

              // Filter out non-video files (e.g., JPEG, PNG)
              if (!_isValidVideoFile(normalizedPath)) {
                continue;
              }

              allVideos.add(
                VideoItem(
                  id: asset.id,
                  name: asset.title ?? path.basename(normalizedPath),
                  path: normalizedPath,
                  thumbnail: asset.id,
                  mimeType: _inferMimeType(normalizedPath),
                  duration: Duration(seconds: asset.duration),
                  size: await file.length(),
                  dateModified: asset.modifiedDateTime,
                ),
              );
            } catch (_) {
              // Continue with next asset
              continue;
            }
          }

          if (assets.length < _scanPageSize) {
            break;
          }
          page += 1;
        }
      }

      // Save to cache
      if (allVideos.isNotEmpty) {
        await _saveCache(allVideos, probe: probe);
        debugPrint('Completed: ${allVideos.length} videos scanned');
      } else {
        debugPrint('No videos found');
      }

      return allVideos;
    } catch (e) {
      debugPrint('Error scanning videos: $e');
      return [];
    }
  }

  /// Organize videos into folders
  static Future<List<VideoFolder>> organizeIntoFolders(
    List<VideoItem> videos,
  ) async {
    Map<String, List<VideoItem>> folderMap = {};

    for (var video in videos) {
      final directory = path.dirname(video.path);

      if (!folderMap.containsKey(directory)) {
        folderMap[directory] = [];
      }
      folderMap[directory]!.add(video);
    }

    List<VideoFolder> folders = folderMap.entries.map((entry) {
      return VideoFolder(
        name: path.basename(entry.key),
        path: entry.key,
        videos: entry.value,
      );
    }).toList();

    // Sort folders by name
    folders.sort((a, b) => a.name.compareTo(b.name));

    return folders;
  }

  /// Get all videos organized by folders
  static Future<Map<String, dynamic>> getAllVideos() async {
    try {
      final allVideos = await scanAllVideos();
      final folders = await organizeIntoFolders(allVideos);

      return {'videos': allVideos, 'folders': folders};
    } catch (e) {
      debugPrint('Error getting all videos: $e');
      return {'videos': <VideoItem>[], 'folders': <VideoFolder>[]};
    }
  }

  static Future<_LibraryProbe> _buildLibraryProbe() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
    );
    final seenAssetIds = <String>{};
    var signature = 17;

    for (final album in albums) {
      var page = 0;
      while (true) {
        final assets = await album.getAssetListPaged(
          page: page,
          size: _scanPageSize,
        );
        if (assets.isEmpty) break;

        for (final asset in assets) {
          if (!seenAssetIds.add(asset.id)) continue;
          signature = (signature * 37) ^ asset.id.hashCode;
          signature =
              (signature * 37) ^ asset.modifiedDateTime.millisecondsSinceEpoch;
        }

        if (assets.length < _scanPageSize) {
          break;
        }
        page += 1;
      }
    }

    return _LibraryProbe(
      uniqueAssetCount: seenAssetIds.length,
      signature: signature,
    );
  }
}

class _LibraryProbe {
  final int uniqueAssetCount;
  final int signature;

  const _LibraryProbe({
    required this.uniqueAssetCount,
    required this.signature,
  });
}
