import 'package:empty_player/services/subtitle_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = SubtitleService();

  group('SubtitleService.parseSrt', () {
    test('parses basic srt cues', () {
      const content = '''
1
00:00:01,000 --> 00:00:02,500
Hello world

2
00:00:03,000 --> 00:00:04,000
Second line
''';

      final cues = service.parseSrt(content);
      expect(cues.length, 2);
      expect(cues[0].text, 'Hello world');
      expect(cues[0].start, const Duration(seconds: 1));
      expect(cues[0].end, const Duration(milliseconds: 2500));
    });

    test('ignores invalid blocks', () {
      const content = '''
1
invalid
text

2
00:00:03,000 --> 00:00:02,000
bad timing
''';

      final cues = service.parseSrt(content);
      expect(cues, isEmpty);
    });
  });

  group('SubtitleService.parseWebVtt', () {
    test('parses webvtt cues', () {
      const content = '''
WEBVTT

00:00:00.500 --> 00:00:02.000
Alpha

cue-id
00:00:03.000 --> 00:00:04.500 align:start
Beta
''';

      final cues = service.parseWebVtt(content);
      expect(cues.length, 2);
      expect(cues[0].text, 'Alpha');
      expect(cues[1].text, 'Beta');
    });
  });

  group('SubtitleService.cueAt', () {
    test('finds cue at position with binary search', () {
      const content = '''
1
00:00:01,000 --> 00:00:03,000
Hello

2
00:00:04,000 --> 00:00:05,000
World
''';
      final cues = service.parseSrt(content);

      final cue = service.cueAt(cues, const Duration(milliseconds: 4500));
      expect(cue, isNotNull);
      expect(cue!.text, 'World');

      final none = service.cueAt(cues, const Duration(milliseconds: 3500));
      expect(none, isNull);
    });

    test('applies positive and negative offsets', () {
      final p = service.applyOffset(const Duration(seconds: 10), 1.5);
      final n = service.applyOffset(const Duration(milliseconds: 800), -1.0);

      expect(p, const Duration(milliseconds: 11500));
      expect(n, Duration.zero);
    });
  });
}
