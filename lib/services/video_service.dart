import 'dart:io';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:empty_player/models/video_item.dart';
import 'package:path/path.dart' as path;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoService {
  static const String _cacheKey = 'video_cache';
  static const String _cacheTimestampKey = 'video_cache_timestamp';
  static const Duration _cacheExpiry = Duration(hours: 24);
  
  // List of valid video file extensions
  static const List<String> _validVideoExtensions = [
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', 
    '.webm', '.m4v', '.3gp', '.3g2', '.mpg', '.mpeg',
    '.m2v', '.m4p', '.ogv', '.ts', '.mts', '.m2ts'
  ];
  
  /// Check if a file path has a valid video extension
  static bool _isValidVideoFile(String filePath) {
    if (filePath.isEmpty) return false;
    final extension = path.extension(filePath).toLowerCase();
    return _validVideoExtensions.contains(extension);
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
      print('Error checking permission: $e');
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
          print('Android 13+ video permission status: $status');
          return status;
        } else {
          // Android 12 and below - use READ_EXTERNAL_STORAGE
          final status = await Permission.storage.request();
          print('Android 12- storage permission status: $status');
          return status;
        }
      } else if (Platform.isIOS) {
        final status = await Permission.photos.request();
        return status;
      }
    } catch (e) {
      print('Error requesting permission: $e');
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
  static Future<void> _saveCache(List<VideoItem> videos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = videos.map((v) => v.toJson()).toList();
      await prefs.setString(_cacheKey, jsonEncode(jsonList));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('Error saving cache: $e');
    }
  }

  /// Load video cache from SharedPreferences
  static Future<List<VideoItem>?> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_cacheTimestampKey);
      
      if (timestamp == null) return null;
      
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(cacheTime) > _cacheExpiry) {
        // Cache expired
        return null;
      }
      
      final jsonString = prefs.getString(_cacheKey);
      if (jsonString == null) return null;
      
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList.map((json) => VideoItem.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error loading cache: $e');
      return null;
    }
  }

  /// Clear video cache
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      print('Video cache cleared');
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  /// Scan all videos from device using photo_manager
  static Future<List<VideoItem>> scanAllVideos() async {
    try {
      // Try to load from cache first
      final cachedVideos = await _loadCache();
      if (cachedVideos != null && cachedVideos.isNotEmpty) {
        print('Loaded ${cachedVideos.length} videos from cache');
        return cachedVideos;
      }

      print('Scanning videos from device...');
      // Don't check permission here - assume it's already granted
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        hasAll: true,
      );

      List<VideoItem> allVideos = [];
      int processedCount = 0;

      for (var album in albums) {
        final List<AssetEntity> assets = await album.getAssetListPaged(
          page: 0,
          size: 1000,
        );

        for (var asset in assets) {
          processedCount++;
          
          if (processedCount % 100 == 0) {
            print('Processing: $processedCount videos');
          }

          try {
            final file = await asset.file;
            if (file == null) continue;

            // Filter out non-video files (e.g., JPEG, PNG)
            if (!_isValidVideoFile(file.path)) {
              continue;
            }

            allVideos.add(VideoItem(
              name: asset.title ?? path.basename(file.path),
              path: file.path,
              thumbnail: null,
              duration: Duration(seconds: asset.duration),
              size: await file.length(),
              dateModified: asset.modifiedDateTime,
            ));
          } catch (assetError) {
            // Continue with next asset
            continue;
          }
        }
      }

      // Save to cache
      if (allVideos.isNotEmpty) {
        await _saveCache(allVideos);
        print('Completed: ${allVideos.length} videos scanned');
      } else {
        print('No videos found');
      }

      return allVideos;
    } catch (e) {
      print('Error scanning videos: $e');
      return [];
    }
  }

  /// Organize videos into folders
  static Future<List<VideoFolder>> organizeIntoFolders(List<VideoItem> videos) async {
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

      return {
        'videos': allVideos,
        'folders': folders,
      };
    } catch (e) {
      print('Error getting all videos: $e');
      return {
        'videos': <VideoItem>[],
        'folders': <VideoFolder>[],
      };
    }
  }
}
