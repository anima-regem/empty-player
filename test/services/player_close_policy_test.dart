import 'package:empty_player/services/player_close_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerClosePolicy.resolve', () {
    test('returns close when not playing', () {
      final action = PlayerClosePolicy.resolve(
        isPlaying: false,
        pipOnCloseEnabled: true,
        pipSupported: true,
      );

      expect(action, PlayerCloseAction.close);
    });

    test('returns enterPip when playing and pip enabled/supported', () {
      final action = PlayerClosePolicy.resolve(
        isPlaying: true,
        pipOnCloseEnabled: true,
        pipSupported: true,
      );

      expect(action, PlayerCloseAction.enterPip);
    });

    test('returns minimize when pip is disabled', () {
      final action = PlayerClosePolicy.resolve(
        isPlaying: true,
        pipOnCloseEnabled: false,
        pipSupported: true,
      );

      expect(action, PlayerCloseAction.minimize);
    });

    test('returns minimize when pip unsupported', () {
      final action = PlayerClosePolicy.resolve(
        isPlaying: true,
        pipOnCloseEnabled: true,
        pipSupported: false,
      );

      expect(action, PlayerCloseAction.minimize);
    });
  });
}
