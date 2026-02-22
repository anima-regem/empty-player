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

  Future<AndroidEmbeddingRuntimeStatus?> runtimeStatus() async {
    if (!Platform.isAndroid) return null;
    try {
      final payload = await _channel.invokeMethod<dynamic>('runtimeStatus');
      if (payload is! Map) return null;
      final map = Map<String, dynamic>.from(payload);
      final ready = (map['ready'] as bool?) ?? false;
      final runtimeName =
          (map['runtimeName'] as String?)?.trim().isNotEmpty == true
          ? (map['runtimeName'] as String).trim()
          : null;
      final provider = (map['provider'] as String?)?.trim();
      final reason = (map['reason'] as String?)?.trim();
      final quantized = (map['quantized'] as bool?) ?? false;
      final dimensions = (map['dimensions'] as num?)?.toInt();
      return AndroidEmbeddingRuntimeStatus(
        ready: ready,
        runtimeName: runtimeName,
        provider: provider,
        reason: reason,
        quantized: quantized,
        dimensions: dimensions,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> isReady() async {
    if (!Platform.isAndroid) return false;
    final status = await runtimeStatus();
    if (status != null) {
      return status.ready;
    }
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

class UnavailableEmbeddingRuntime implements EmbeddingRuntime {
  @override
  final String runtimeName;

  @override
  final int dimensions;

  final String reason;

  const UnavailableEmbeddingRuntime({
    required this.reason,
    this.runtimeName = 'embedding_unavailable',
    this.dimensions = 128,
  });

  @override
  Future<List<double>> embedText(String query) {
    throw UnsupportedError(reason);
  }

  @override
  Future<List<double>> embedFrame(VideoFrameInput frame) {
    throw UnsupportedError(reason);
  }

  @override
  Future<List<double>> embedImage(ImageEmbeddingInput image) {
    throw UnsupportedError(reason);
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
    final status = await androidRuntime.runtimeStatus();
    if (status != null) {
      if (status.ready && _isProductionMultimodalProvider(status.provider)) {
        final resolvedName = (status.runtimeName?.isNotEmpty ?? false)
            ? status.runtimeName!
            : 'android_native_multimodal';
        final resolvedDimensions =
            (status.dimensions ?? androidRuntime.dimensions)
                .clamp(32, 2048)
                .toInt();
        return AndroidOnDeviceEmbeddingRuntime(
          runtimeName: resolvedName,
          dimensions: resolvedDimensions,
        );
      }
      return UnavailableEmbeddingRuntime(
        reason:
            status.reason ??
            'On-device multimodal embedding runtime is unavailable.',
      );
    }

    final ready = await androidRuntime.isReady();
    if (ready && mode == EmbeddingRuntimeMode.androidNative) {
      return androidRuntime;
    }
  } catch (_) {
    // If native runtime is unavailable, expose degraded mode explicitly.
  }

  return const UnavailableEmbeddingRuntime(
    reason:
        'On-device embedding runtime is unavailable. Install a compatible Android build or switch to deterministic mode in Settings.',
  );
}

class AndroidEmbeddingRuntimeStatus {
  final bool ready;
  final String? runtimeName;
  final String? provider;
  final String? reason;
  final bool quantized;
  final int? dimensions;

  const AndroidEmbeddingRuntimeStatus({
    required this.ready,
    this.runtimeName,
    this.provider,
    this.reason,
    required this.quantized,
    this.dimensions,
  });
}

bool _isProductionMultimodalProvider(String? provider) {
  if (provider == null) return false;
  final normalized = provider.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.contains('onnx') ||
      normalized.contains('nnapi') ||
      normalized.contains('litert') ||
      normalized.contains('tflite') ||
      normalized.contains('mobileclip') ||
      normalized.contains('siglip');
}
