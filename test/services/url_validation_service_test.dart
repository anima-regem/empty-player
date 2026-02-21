import 'package:empty_player/services/url_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UrlValidationService.validateNetworkUrl', () {
    test('accepts valid https url', () {
      final result = UrlValidationService.validateNetworkUrl(
        'https://example.com/video.mp4',
      );

      expect(result.isValid, true);
      expect(result.uri?.scheme, 'https');
    });

    test('accepts valid rtsp url', () {
      final result = UrlValidationService.validateNetworkUrl(
        'rtsp://example.com/live',
      );

      expect(result.isValid, true);
      expect(result.uri?.scheme, 'rtsp');
    });

    test('rejects empty input', () {
      final result = UrlValidationService.validateNetworkUrl('   ');

      expect(result.isValid, false);
      expect(result.error, isNotNull);
    });

    test('rejects unsupported scheme', () {
      final result = UrlValidationService.validateNetworkUrl(
        'ftp://example.com/video.mp4',
      );

      expect(result.isValid, false);
      expect(result.error, contains('Unsupported scheme'));
    });

    test('rejects url with missing host', () {
      final result = UrlValidationService.validateNetworkUrl(
        'https:///video.mp4',
      );

      expect(result.isValid, false);
      expect(result.error, contains('host is missing'));
    });
  });
}
