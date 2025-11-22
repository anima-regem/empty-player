import 'package:flutter_test/flutter_test.dart';
import 'package:empty_player/services/mini_player_service.dart';

void main() {
  group('MiniPlayerService', () {
    late MiniPlayerService service;

    setUp(() {
      service = MiniPlayerService();
    });

    test('is a singleton', () {
      final instance1 = MiniPlayerService();
      final instance2 = MiniPlayerService();

      expect(instance1, same(instance2));
    });

    test('initial state has no video', () {
      expect(service.hasVideo, false);
      expect(service.controller, null);
      expect(service.videoTitle, null);
      expect(service.videoUrl, null);
      expect(service.isMinimized, false);
    });

    test('minimize sets isMinimized to true', () {
      expect(service.isMinimized, false);

      service.minimize();

      expect(service.isMinimized, true);
    });

    test('maximize sets isMinimized to false', () {
      service.minimize();
      expect(service.isMinimized, true);

      service.maximize();

      expect(service.isMinimized, false);
    });

    test('minimize notifies listeners', () {
      bool notified = false;
      service.addListener(() {
        notified = true;
      });

      service.minimize();

      expect(notified, true);
    });

    test('maximize notifies listeners', () {
      service.minimize();

      bool notified = false;
      service.addListener(() {
        notified = true;
      });

      service.maximize();

      expect(notified, true);
    });

    test('clearController resets all state', () {
      // First set some state
      service.minimize();

      service.clearController();

      expect(service.controller, null);
      expect(service.videoTitle, null);
      expect(service.videoUrl, null);
      expect(service.isMinimized, false);
      expect(service.hasVideo, false);
    });

    test('clearController notifies listeners', () {
      bool notified = false;
      service.addListener(() {
        notified = true;
      });

      service.clearController();

      expect(notified, true);
    });
  });
}
