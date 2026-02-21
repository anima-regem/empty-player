class VectorSearchHit {
  final String mediaId;
  final double score;
  final List<int> matchedFrames;

  const VectorSearchHit({
    required this.mediaId,
    required this.score,
    required this.matchedFrames,
  });
}
