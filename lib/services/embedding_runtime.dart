import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/services.dart';

class VideoFrameInput {
  final String mediaId;
  final String sourcePath;
  final Duration timestamp;

  const VideoFrameInput({
    required this.mediaId,
    required this.sourcePath,
    required this.timestamp,
  });
}

class ImageEmbeddingInput {
  final String imagePath;

  const ImageEmbeddingInput({required this.imagePath});
}

enum EmbeddingRuntimeMode {
  auto,
  androidNative,
  deterministic;

  String toStorageValue() {
    switch (this) {
      case EmbeddingRuntimeMode.auto:
        return 'auto';
      case EmbeddingRuntimeMode.androidNative:
        return 'android_native';
      case EmbeddingRuntimeMode.deterministic:
        return 'deterministic';
    }
  }

  static EmbeddingRuntimeMode fromStorageValue(String? raw) {
    switch (raw) {
      case 'android_native':
        return EmbeddingRuntimeMode.androidNative;
      case 'deterministic':
        return EmbeddingRuntimeMode.deterministic;
      case 'auto':
      default:
        return EmbeddingRuntimeMode.auto;
    }
  }
}

abstract interface class EmbeddingRuntime {
  String get runtimeName;
  int get dimensions;

  Future<List<double>> embedText(String query);
  Future<List<double>> embedFrame(VideoFrameInput frame);
  Future<List<double>> embedImage(ImageEmbeddingInput image);
}

class DeterministicSpikeEmbeddingRuntime implements EmbeddingRuntime {
  @override
  final String runtimeName;

  @override
  final int dimensions;

  const DeterministicSpikeEmbeddingRuntime({
    this.runtimeName = 'deterministic_spike',
    this.dimensions = 256,
  });

  @override
  Future<List<double>> embedText(String query) async {
    return _generateVector(query.hashCode);
  }

  @override
  Future<List<double>> embedFrame(VideoFrameInput frame) async {
    return _generateVector(
      Object.hash(
        frame.mediaId,
        frame.sourcePath,
        frame.timestamp.inMilliseconds,
      ),
    );
  }

  @override
  Future<List<double>> embedImage(ImageEmbeddingInput image) async {
    return _generateVector(
      Object.hash(image.imagePath, image.imagePath.length),
    );
  }

  List<double> _generateVector(int seed) {
    final random = math.Random(seed);
    final vector = List<double>.generate(
      dimensions,
      (_) => random.nextDouble() - 0.5,
    );
    final magnitude = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + (value * value)),
    );
    if (magnitude == 0) return vector;
    return vector.map((value) => value / magnitude).toList(growable: false);
  }
}

class AndroidOnDeviceEmbeddingRuntime implements EmbeddingRuntime {
  static const MethodChannel _channel = MethodChannel(
    'com.example.empty_player/embedding',
  );

  @override
  final String runtimeName;

  @override
  final int dimensions;

  const AndroidOnDeviceEmbeddingRuntime({
    this.runtimeName = 'android_native_embedding',
    this.dimensions = 128,
  });

  Future<bool> isReady() async {
    if (!Platform.isAndroid) return false;
    final ready = await _channel.invokeMethod<bool>('isReady');
    return ready ?? false;
  }

  @override
  Future<List<double>> embedText(String query) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Android embedding runtime is only available on Android.',
      );
    }
    final raw = await _channel.invokeMethod<dynamic>('embedText', {
      'text': query,
      'dimensions': dimensions,
    });
    return _asVector(raw);
  }

  @override
  Future<List<double>> embedFrame(VideoFrameInput frame) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Android embedding runtime is only available on Android.',
      );
    }
    final raw = await _channel.invokeMethod<dynamic>('embedFrame', {
      'sourcePath': frame.sourcePath,
      'timestampMs': frame.timestamp.inMilliseconds,
      'dimensions': dimensions,
    });
    return _asVector(raw);
  }

  @override
  Future<List<double>> embedImage(ImageEmbeddingInput image) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Android embedding runtime is only available on Android.',
      );
    }
    final raw = await _channel.invokeMethod<dynamic>('embedImage', {
      'imagePath': image.imagePath,
      'dimensions': dimensions,
    });
    return _asVector(raw);
  }

  List<double> _asVector(dynamic raw) {
    if (raw is List) {
      return raw
          .map((value) => (value as num).toDouble())
          .toList(growable: false);
    }
    throw StateError('Embedding runtime returned an invalid vector payload.');
  }
}

EmbeddingRuntime createDefaultEmbeddingRuntime() {
  if (Platform.isAndroid) {
    return const AndroidOnDeviceEmbeddingRuntime();
  }
  return const DeterministicSpikeEmbeddingRuntime(
    runtimeName: 'deterministic_fallback',
    dimensions: 128,
  );
}

Future<EmbeddingRuntime> createEmbeddingRuntime({
  EmbeddingRuntimeMode mode = EmbeddingRuntimeMode.auto,
}) async {
  final fallback = const DeterministicSpikeEmbeddingRuntime(
    runtimeName: 'deterministic_fallback',
    dimensions: 128,
  );
  if (!Platform.isAndroid) {
    return fallback;
  }
  if (mode == EmbeddingRuntimeMode.deterministic) {
    return fallback;
  }

  final androidRuntime = const AndroidOnDeviceEmbeddingRuntime();
  try {
    final ready = await androidRuntime.isReady();
    if (ready) {
      return androidRuntime;
    }
  } catch (_) {
    // If native runtime is unavailable, fall back to deterministic runtime.
  }

  if (mode == EmbeddingRuntimeMode.androidNative) {
    return fallback;
  }
  return fallback;
}
