import 'dart:math' as math;
import 'dart:typed_data';

class VideoFrameInput {
  final String mediaId;
  final Duration timestamp;
  final Uint8List bytes;

  const VideoFrameInput({
    required this.mediaId,
    required this.timestamp,
    required this.bytes,
  });
}

abstract interface class EmbeddingRuntime {
  String get runtimeName;
  int get dimensions;

  Future<List<double>> embedText(String query);
  Future<List<double>> embedFrame(VideoFrameInput frame);
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
        frame.timestamp.inMilliseconds,
        frame.bytes.length,
      ),
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
