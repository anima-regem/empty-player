import 'package:flutter_test/flutter_test.dart';
import 'package:empty_player/models/video_item.dart';

void main() {
  group('VideoItem', () {
    test('creates VideoItem with required fields', () {
      final videoItem = VideoItem(
        name: 'test_video.mp4',
        path: '/storage/videos/test_video.mp4',
      );

      expect(videoItem.name, 'test_video.mp4');
      expect(videoItem.path, '/storage/videos/test_video.mp4');
      expect(videoItem.thumbnail, null);
      expect(videoItem.duration, null);
      expect(videoItem.size, null);
      expect(videoItem.dateModified, null);
    });

    test('creates VideoItem with all fields', () {
      final dateTime = DateTime(2024, 1, 1);
      final duration = Duration(seconds: 120);

      final videoItem = VideoItem(
        name: 'test_video.mp4',
        path: '/storage/videos/test_video.mp4',
        thumbnail: '/storage/thumbnails/test.jpg',
        duration: duration,
        size: 1024000,
        dateModified: dateTime,
      );

      expect(videoItem.name, 'test_video.mp4');
      expect(videoItem.path, '/storage/videos/test_video.mp4');
      expect(videoItem.thumbnail, '/storage/thumbnails/test.jpg');
      expect(videoItem.duration, duration);
      expect(videoItem.size, 1024000);
      expect(videoItem.dateModified, dateTime);
    });

    test('toJson converts VideoItem to Map correctly', () {
      final dateTime = DateTime(2024, 1, 1);
      final duration = Duration(seconds: 120);

      final videoItem = VideoItem(
        name: 'test_video.mp4',
        path: '/storage/videos/test_video.mp4',
        thumbnail: '/storage/thumbnails/test.jpg',
        duration: duration,
        size: 1024000,
        dateModified: dateTime,
      );

      final json = videoItem.toJson();

      expect(json['name'], 'test_video.mp4');
      expect(json['path'], '/storage/videos/test_video.mp4');
      expect(json['thumbnail'], '/storage/thumbnails/test.jpg');
      expect(json['duration'], 120);
      expect(json['size'], 1024000);
      expect(json['dateModified'], dateTime.toIso8601String());
    });

    test('toJson handles null fields correctly', () {
      final videoItem = VideoItem(
        name: 'test_video.mp4',
        path: '/storage/videos/test_video.mp4',
      );

      final json = videoItem.toJson();

      expect(json['name'], 'test_video.mp4');
      expect(json['path'], '/storage/videos/test_video.mp4');
      expect(json['thumbnail'], null);
      expect(json['duration'], null);
      expect(json['size'], null);
      expect(json['dateModified'], null);
    });

    test('fromJson creates VideoItem from Map correctly', () {
      final dateTime = DateTime(2024, 1, 1);
      final json = {
        'name': 'test_video.mp4',
        'path': '/storage/videos/test_video.mp4',
        'thumbnail': '/storage/thumbnails/test.jpg',
        'duration': 120,
        'size': 1024000,
        'dateModified': dateTime.toIso8601String(),
      };

      final videoItem = VideoItem.fromJson(json);

      expect(videoItem.name, 'test_video.mp4');
      expect(videoItem.path, '/storage/videos/test_video.mp4');
      expect(videoItem.thumbnail, '/storage/thumbnails/test.jpg');
      expect(videoItem.duration, Duration(seconds: 120));
      expect(videoItem.size, 1024000);
      expect(videoItem.dateModified, dateTime);
    });

    test('fromJson handles null fields correctly', () {
      final json = {
        'name': 'test_video.mp4',
        'path': '/storage/videos/test_video.mp4',
        'thumbnail': null,
        'duration': null,
        'size': null,
        'dateModified': null,
      };

      final videoItem = VideoItem.fromJson(json);

      expect(videoItem.name, 'test_video.mp4');
      expect(videoItem.path, '/storage/videos/test_video.mp4');
      expect(videoItem.thumbnail, null);
      expect(videoItem.duration, null);
      expect(videoItem.size, null);
      expect(videoItem.dateModified, null);
    });

    test('toJson and fromJson round trip preserves data', () {
      final dateTime = DateTime(2024, 1, 1);
      final originalVideo = VideoItem(
        name: 'test_video.mp4',
        path: '/storage/videos/test_video.mp4',
        thumbnail: '/storage/thumbnails/test.jpg',
        duration: Duration(seconds: 120),
        size: 1024000,
        dateModified: dateTime,
      );

      final json = originalVideo.toJson();
      final restoredVideo = VideoItem.fromJson(json);

      expect(restoredVideo.name, originalVideo.name);
      expect(restoredVideo.path, originalVideo.path);
      expect(restoredVideo.thumbnail, originalVideo.thumbnail);
      expect(restoredVideo.duration, originalVideo.duration);
      expect(restoredVideo.size, originalVideo.size);
      expect(restoredVideo.dateModified, originalVideo.dateModified);
    });
  });

  group('VideoFolder', () {
    test('creates VideoFolder with empty videos list', () {
      final folder = VideoFolder(
        name: 'Downloads',
        path: '/storage/emulated/0/Download',
        videos: [],
      );

      expect(folder.name, 'Downloads');
      expect(folder.path, '/storage/emulated/0/Download');
      expect(folder.videos, isEmpty);
      expect(folder.videoCount, 0);
    });

    test('creates VideoFolder with videos and counts them correctly', () {
      final videos = [
        VideoItem(name: 'video1.mp4', path: '/storage/video1.mp4'),
        VideoItem(name: 'video2.mp4', path: '/storage/video2.mp4'),
        VideoItem(name: 'video3.mp4', path: '/storage/video3.mp4'),
      ];

      final folder = VideoFolder(
        name: 'Movies',
        path: '/storage/emulated/0/Movies',
        videos: videos,
      );

      expect(folder.name, 'Movies');
      expect(folder.path, '/storage/emulated/0/Movies');
      expect(folder.videos, videos);
      expect(folder.videoCount, 3);
    });

    test('videoCount reflects the actual number of videos', () {
      final videos = List.generate(
        10,
        (index) => VideoItem(
          name: 'video$index.mp4',
          path: '/storage/video$index.mp4',
        ),
      );

      final folder = VideoFolder(
        name: 'TestFolder',
        path: '/storage/test',
        videos: videos,
      );

      expect(folder.videoCount, 10);
      expect(folder.videos.length, 10);
    });
  });
}
