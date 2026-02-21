class DiscoveryHit {
  final String mediaId;
  final String title;
  final double score;
  final List<String> reasons;

  const DiscoveryHit({
    required this.mediaId,
    required this.title,
    required this.score,
    this.reasons = const <String>[],
  });
}

class DiscoverySection {
  final String id;
  final String title;
  final List<DiscoveryHit> items;

  const DiscoverySection({
    required this.id,
    required this.title,
    required this.items,
  });
}

abstract interface class DiscoveryServiceV2 {
  Future<List<DiscoveryHit>> searchText(String query, {int limit = 100});
  Future<List<DiscoveryHit>> searchImage(String imagePath, {int limit = 100});
  Future<List<DiscoverySection>> homeSections();
}
