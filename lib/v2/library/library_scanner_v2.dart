import 'package:empty_player/models/video_item.dart';

class ScanProgress {
  final int scannedAssets;
  final int indexedVideos;
  final double progress;
  final bool isCompleted;
  final String? message;

  const ScanProgress({
    required this.scannedAssets,
    required this.indexedVideos,
    required this.progress,
    required this.isCompleted,
    this.message,
  });
}

abstract interface class LibraryScannerV2 {
  Stream<ScanProgress> scan({required bool fullRescan});
  Future<void> cancelScan();
}

abstract interface class LibraryReadRepositoryV2 {
  Future<List<VideoItem>> allVideos();
  Future<List<VideoFolder>> allFolders();
}
