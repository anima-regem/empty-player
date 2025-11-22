import 'package:flutter_test/flutter_test.dart';
import 'package:empty_player/models/video_item.dart';
import 'package:empty_player/services/video_service.dart';

void main() {
  group('VideoService.organizeIntoFolders', () {
    test('returns empty list when no videos provided', () async {
      final folders = await VideoService.organizeIntoFolders([]);

      expect(folders, isEmpty);
    });

    test('organizes single video into one folder', () async {
      final videos = [
        VideoItem(
          name: 'video1.mp4',
          path: '/storage/emulated/0/Movies/video1.mp4',
        ),
      ];

      final folders = await VideoService.organizeIntoFolders(videos);

      expect(folders.length, 1);
      expect(folders[0].name, 'Movies');
      expect(folders[0].path, '/storage/emulated/0/Movies');
      expect(folders[0].videos.length, 1);
      expect(folders[0].videoCount, 1);
    });

    test('organizes videos from same directory into one folder', () async {
      final videos = [
        VideoItem(
          name: 'video1.mp4',
          path: '/storage/emulated/0/Movies/video1.mp4',
        ),
        VideoItem(
          name: 'video2.mp4',
          path: '/storage/emulated/0/Movies/video2.mp4',
        ),
        VideoItem(
          name: 'video3.mp4',
          path: '/storage/emulated/0/Movies/video3.mp4',
        ),
      ];

      final folders = await VideoService.organizeIntoFolders(videos);

      expect(folders.length, 1);
      expect(folders[0].name, 'Movies');
      expect(folders[0].videos.length, 3);
      expect(folders[0].videoCount, 3);
    });

    test(
      'organizes videos from different directories into separate folders',
      () async {
        final videos = [
          VideoItem(
            name: 'video1.mp4',
            path: '/storage/emulated/0/Movies/video1.mp4',
          ),
          VideoItem(
            name: 'video2.mp4',
            path: '/storage/emulated/0/Download/video2.mp4',
          ),
          VideoItem(
            name: 'video3.mp4',
            path: '/storage/emulated/0/DCIM/video3.mp4',
          ),
        ];

        final folders = await VideoService.organizeIntoFolders(videos);

        expect(folders.length, 3);

        final folderNames = folders.map((f) => f.name).toSet();
        expect(folderNames, containsAll(['Movies', 'Download', 'DCIM']));

        for (final folder in folders) {
          expect(folder.videoCount, 1);
        }
      },
    );

    test('sorts folders alphabetically by name', () async {
      final videos = [
        VideoItem(
          name: 'video1.mp4',
          path: '/storage/emulated/0/Zebra/video1.mp4',
        ),
        VideoItem(
          name: 'video2.mp4',
          path: '/storage/emulated/0/Alpha/video2.mp4',
        ),
        VideoItem(
          name: 'video3.mp4',
          path: '/storage/emulated/0/Movies/video3.mp4',
        ),
      ];

      final folders = await VideoService.organizeIntoFolders(videos);

      expect(folders.length, 3);
      expect(folders[0].name, 'Alpha');
      expect(folders[1].name, 'Movies');
      expect(folders[2].name, 'Zebra');
    });

    test('handles mixed directory scenarios correctly', () async {
      final videos = [
        VideoItem(
          name: 'video1.mp4',
          path: '/storage/emulated/0/Movies/video1.mp4',
        ),
        VideoItem(
          name: 'video2.mp4',
          path: '/storage/emulated/0/Movies/video2.mp4',
        ),
        VideoItem(
          name: 'video3.mp4',
          path: '/storage/emulated/0/Download/video3.mp4',
        ),
        VideoItem(
          name: 'video4.mp4',
          path: '/storage/emulated/0/DCIM/Camera/video4.mp4',
        ),
      ];

      final folders = await VideoService.organizeIntoFolders(videos);

      expect(folders.length, 3);

      final moviesFolder = folders.firstWhere((f) => f.name == 'Movies');
      expect(moviesFolder.videoCount, 2);

      final downloadFolder = folders.firstWhere((f) => f.name == 'Download');
      expect(downloadFolder.videoCount, 1);

      final cameraFolder = folders.firstWhere((f) => f.name == 'Camera');
      expect(cameraFolder.videoCount, 1);
    });

    test('preserves video data in folders', () async {
      final duration = Duration(seconds: 120);
      final dateTime = DateTime(2024, 1, 1);

      final videos = [
        VideoItem(
          name: 'test_video.mp4',
          path: '/storage/emulated/0/Movies/test_video.mp4',
          thumbnail: '/storage/thumbnails/test.jpg',
          duration: duration,
          size: 1024000,
          dateModified: dateTime,
        ),
      ];

      final folders = await VideoService.organizeIntoFolders(videos);

      expect(folders.length, 1);

      final video = folders[0].videos[0];
      expect(video.name, 'test_video.mp4');
      expect(video.path, '/storage/emulated/0/Movies/test_video.mp4');
      expect(video.thumbnail, '/storage/thumbnails/test.jpg');
      expect(video.duration, duration);
      expect(video.size, 1024000);
      expect(video.dateModified, dateTime);
    });
  });
}
