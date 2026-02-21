import 'dart:io';

/// Typed media source used by player entry points.
sealed class MediaSource {
  const MediaSource();

  String get rawInput;
  String get id;
  Uri get uri;

  bool get isNetwork => this is NetworkMediaSource;
  bool get isFile => this is FileMediaSource;
  bool get isContent => this is ContentMediaSource;

  String toStorageKey() => '$runtimeType:$id';

  factory MediaSource.fromInput(String input, {Map<String, String>? headers}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Media source cannot be empty.');
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      final scheme = parsed.scheme.toLowerCase();

      if (NetworkMediaSource.supportedSchemes.contains(scheme)) {
        return NetworkMediaSource(parsed, rawInput: trimmed, headers: headers);
      }
      if (scheme == 'content') {
        return ContentMediaSource(parsed, rawInput: trimmed);
      }
      if (scheme == 'file') {
        return FileMediaSource(
          parsed.toFilePath(windows: Platform.isWindows),
          rawInput: trimmed,
        );
      }

      throw FormatException('Unsupported media source scheme: $scheme');
    }

    // No explicit scheme -> treat as local file path.
    return FileMediaSource(trimmed, rawInput: trimmed);
  }
}

class NetworkMediaSource extends MediaSource {
  static const Set<String> supportedSchemes = {'http', 'https', 'rtsp', 'rtmp'};

  @override
  final String rawInput;

  @override
  final Uri uri;

  final Map<String, String> headers;

  const NetworkMediaSource(
    this.uri, {
    required this.rawInput,
    Map<String, String>? headers,
  }) : headers = headers ?? const {};

  @override
  String get id => uri.toString();
}

class FileMediaSource extends MediaSource {
  final String path;

  @override
  final String rawInput;

  const FileMediaSource(this.path, {required this.rawInput});

  @override
  String get id => path;

  @override
  Uri get uri => Uri.file(path);
}

class ContentMediaSource extends MediaSource {
  @override
  final Uri uri;

  @override
  final String rawInput;

  const ContentMediaSource(this.uri, {required this.rawInput});

  @override
  String get id => uri.toString();
}
