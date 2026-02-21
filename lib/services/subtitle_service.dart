import 'dart:io';

import 'package:empty_player/models/subtitle_cue.dart';

class SubtitleService {
  const SubtitleService();

  Future<List<SubtitleCue>> parseFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Subtitle file not found', path);
    }
    final content = await file.readAsString();
    final normalizedPath = path.toLowerCase();
    if (normalizedPath.endsWith('.vtt')) {
      return parseWebVtt(content);
    }
    return parseSrt(content);
  }

  List<SubtitleCue> parseSrt(String content) {
    final normalized = content.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const [];

    final blocks = normalized.split(RegExp(r'\n\s*\n'));
    final cues = <SubtitleCue>[];

    for (final block in blocks) {
      final lines = block
          .split('\n')
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;

      var timingIndex = 0;
      if (RegExp(r'^\d+$').hasMatch(lines.first) && lines.length > 1) {
        timingIndex = 1;
      }

      if (timingIndex >= lines.length) continue;
      final timing = lines[timingIndex];
      if (!timing.contains('-->')) continue;

      final parts = timing.split('-->');
      if (parts.length != 2) continue;

      final start = _parseTimestamp(parts[0].trim());
      final end = _parseTimestamp(parts[1].trim().split(' ').first);
      if (start == null || end == null || end <= start) continue;

      final textLines = lines.skip(timingIndex + 1).toList();
      final text = textLines.join('\n').trim();
      if (text.isEmpty) continue;

      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  List<SubtitleCue> parseWebVtt(String content) {
    final normalized = content
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .trim();
    if (normalized.isEmpty) return const [];

    final lines = normalized.split('\n');
    final cues = <SubtitleCue>[];
    var index = 0;

    if (lines.isNotEmpty &&
        lines.first.trim().toUpperCase().startsWith('WEBVTT')) {
      index = 1;
    }

    while (index < lines.length) {
      final line = lines[index].trim();
      if (line.isEmpty) {
        index++;
        continue;
      }

      String timingLine = line;
      if (!timingLine.contains('-->')) {
        index++;
        if (index >= lines.length) break;
        timingLine = lines[index].trim();
      }

      if (!timingLine.contains('-->')) {
        index++;
        continue;
      }

      final parts = timingLine.split('-->');
      if (parts.length != 2) {
        index++;
        continue;
      }

      final start = _parseTimestamp(parts[0].trim());
      final end = _parseTimestamp(parts[1].trim().split(' ').first);
      if (start == null || end == null || end <= start) {
        index++;
        continue;
      }

      index++;
      final textLines = <String>[];
      while (index < lines.length && lines[index].trim().isNotEmpty) {
        textLines.add(lines[index].trimRight());
        index++;
      }

      final text = textLines.join('\n').trim();
      if (text.isEmpty) continue;

      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  SubtitleCue? cueAt(List<SubtitleCue> cues, Duration position) {
    if (cues.isEmpty) return null;

    var low = 0;
    var high = cues.length - 1;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final cue = cues[mid];

      if (position < cue.start) {
        high = mid - 1;
      } else if (position > cue.end) {
        low = mid + 1;
      } else {
        return cue;
      }
    }

    return null;
  }

  Duration applyOffset(Duration position, double offsetSeconds) {
    final offset = Duration(milliseconds: (offsetSeconds * 1000).round());
    final adjusted = position + offset;
    if (adjusted < Duration.zero) {
      return Duration.zero;
    }
    return adjusted;
  }

  Duration? _parseTimestamp(String value) {
    final cleaned = value.trim().replaceAll(',', '.');
    final match = RegExp(
      r'^(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?$',
    ).firstMatch(cleaned);
    if (match == null) return null;

    final hasHours = match.group(1) != null;
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    final millisRaw = match.group(4) ?? '0';
    final millis =
        int.tryParse(millisRaw.padRight(3, '0').substring(0, 3)) ?? 0;

    if (!hasHours && minutes > 59) return null;
    if (seconds > 59) return null;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }
}
