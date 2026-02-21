class VideoEmbeddingChunk {
  final String mediaId;
  final int frameTsMs;
  final List<double> vector;
  final String modelVersion;

  const VideoEmbeddingChunk({
    required this.mediaId,
    required this.frameTsMs,
    required this.vector,
    required this.modelVersion,
  });

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'frameTsMs': frameTsMs,
    'vector': vector,
    'modelVersion': modelVersion,
  };

  factory VideoEmbeddingChunk.fromJson(Map<String, dynamic> json) {
    return VideoEmbeddingChunk(
      mediaId: json['mediaId'] as String,
      frameTsMs: json['frameTsMs'] as int,
      vector: (json['vector'] as List<dynamic>).cast<double>(),
      modelVersion: json['modelVersion'] as String,
    );
  }
}
