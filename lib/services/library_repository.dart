import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/services/video_service.dart';
import 'package:permission_handler/permission_handler.dart';

abstract interface class PermissionGateway {
  Future<bool> hasLibraryPermission();
  Future<PermissionStatus> requestLibraryPermission();
}

abstract interface class LibraryRepository {
  Future<void> clearCache();
  Future<List<VideoItem>> scanAllVideos();
  Future<List<VideoFolder>> organizeIntoFolders(List<VideoItem> videos);
  Future<Map<String, dynamic>> getAllVideos();
}

class DeviceLibraryRepository implements LibraryRepository, PermissionGateway {
  const DeviceLibraryRepository();

  @override
  Future<bool> hasLibraryPermission() => VideoService.checkPermission();

  @override
  Future<PermissionStatus> requestLibraryPermission() =>
      VideoService.requestPermission();

  @override
  Future<void> clearCache() => VideoService.clearCache();

  @override
  Future<List<VideoItem>> scanAllVideos() => VideoService.scanAllVideos();

  @override
  Future<List<VideoFolder>> organizeIntoFolders(List<VideoItem> videos) =>
      VideoService.organizeIntoFolders(videos);

  @override
  Future<Map<String, dynamic>> getAllVideos() => VideoService.getAllVideos();
}
