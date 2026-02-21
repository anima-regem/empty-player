import 'package:empty_player/models/media_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaSource.fromInput', () {
    test('parses local file path as FileMediaSource', () {
      final source = MediaSource.fromInput(
        '/storage/emulated/0/Movies/test.mp4',
      );

      expect(source, isA<FileMediaSource>());
      expect(source.isFile, true);
      expect(source.toStorageKey(), startsWith('FileMediaSource:'));
    });

    test('parses file:// uri as FileMediaSource', () {
      final source = MediaSource.fromInput(
        'file:///storage/emulated/0/Movies/test.mp4',
      );

      expect(source, isA<FileMediaSource>());
    });

    test('parses content:// uri as ContentMediaSource', () {
      final source = MediaSource.fromInput(
        'content://media/external/video/media/1',
      );

      expect(source, isA<ContentMediaSource>());
      expect(source.isContent, true);
    });

    test('parses https:// uri as NetworkMediaSource', () {
      final source = MediaSource.fromInput('https://example.com/video.mp4');

      expect(source, isA<NetworkMediaSource>());
      expect(source.isNetwork, true);
    });

    test('throws on unsupported scheme', () {
      expect(
        () => MediaSource.fromInput('ftp://example.com/video.mp4'),
        throwsFormatException,
      );
    });
  });
}
