import 'dart:io';
import 'dart:math' as math;

import 'package:empty_player/models/vector_search_hit.dart';
import 'package:empty_player/services/vector_index_repository.dart';
import 'package:empty_player/services/video_semantic_search_service.dart';

class LabeledSearchQuery {
  final String id;
  final String query;
  final Set<String> relevantMediaIds;
  final String? imagePath;

  const LabeledSearchQuery({
    required this.id,
    required this.query,
    required this.relevantMediaIds,
    this.imagePath,
  });
}

class SearchBenchmarkConfig {
  final int k;
  final int minDatasetSize;
  final int maxDatasetSize;
  final bool enforceDatasetSize;

  const SearchBenchmarkConfig({
    this.k = 10,
    this.minDatasetSize = 500,
    this.maxDatasetSize = 2000,
    this.enforceDatasetSize = true,
  });
}

class SearchRelevanceBenchmarkResult {
  final int queryCount;
  final int k;
  final bool datasetWithinTargetRange;
  final double recallAtK;
  final double ndcgAtK;
  final double mrr;
  final double latencyP50Ms;
  final double latencyP95Ms;
  final int memoryP95Bytes;
  final int indexEstimatedBytes;
  final DateTime generatedAt;

  const SearchRelevanceBenchmarkResult({
    required this.queryCount,
    required this.k,
    required this.datasetWithinTargetRange,
    required this.recallAtK,
    required this.ndcgAtK,
    required this.mrr,
    required this.latencyP50Ms,
    required this.latencyP95Ms,
    required this.memoryP95Bytes,
    required this.indexEstimatedBytes,
    required this.generatedAt,
  });
}

class SearchRelevanceBenchmarkService {
  final VideoSemanticSearchService discoveryService;
  final VectorIndexRepository indexRepository;

  const SearchRelevanceBenchmarkService({
    required this.discoveryService,
    required this.indexRepository,
  });

  Future<SearchRelevanceBenchmarkResult> run({
    required List<LabeledSearchQuery> labeledQueries,
    SearchBenchmarkConfig config = const SearchBenchmarkConfig(),
  }) async {
    final k = math.max(1, config.k);
    final withinTargetRange =
        labeledQueries.length >= config.minDatasetSize &&
        labeledQueries.length <= config.maxDatasetSize;
    if (config.enforceDatasetSize && !withinTargetRange) {
      throw ArgumentError(
        'Expected ${config.minDatasetSize}-${config.maxDatasetSize} labeled '
        'queries, got ${labeledQueries.length}.',
      );
    }

    if (labeledQueries.isEmpty) {
      final stats = await indexRepository.stats();
      return SearchRelevanceBenchmarkResult(
        queryCount: 0,
        k: k,
        datasetWithinTargetRange: withinTargetRange,
        recallAtK: 0,
        ndcgAtK: 0,
        mrr: 0,
        latencyP50Ms: 0,
        latencyP95Ms: 0,
        memoryP95Bytes: _currentRss(),
        indexEstimatedBytes: stats.estimatedBytes,
        generatedAt: DateTime.now(),
      );
    }

    var recallSum = 0.0;
    var ndcgSum = 0.0;
    var mrrSum = 0.0;
    final latenciesMs = <double>[];
    final memorySamples = <int>[];

    for (final labeled in labeledQueries) {
      final watch = Stopwatch()..start();
      final hits = await _runQuery(labeled, limit: k);
      watch.stop();

      latenciesMs.add(watch.elapsedMicroseconds / 1000.0);
      memorySamples.add(_currentRss());

      final topHits = hits.take(k).map((hit) => hit.mediaId).toList(growable: false);
      recallSum += _recallAtK(topHits, labeled.relevantMediaIds, k);
      ndcgSum += _ndcgAtK(topHits, labeled.relevantMediaIds, k);
      mrrSum += _mrr(topHits, labeled.relevantMediaIds);
    }

    final stats = await indexRepository.stats();
    final count = labeledQueries.length;
    return SearchRelevanceBenchmarkResult(
      queryCount: count,
      k: k,
      datasetWithinTargetRange: withinTargetRange,
      recallAtK: recallSum / count,
      ndcgAtK: ndcgSum / count,
      mrr: mrrSum / count,
      latencyP50Ms: _percentile(latenciesMs, 0.50),
      latencyP95Ms: _percentile(latenciesMs, 0.95),
      memoryP95Bytes: _percentileInt(memorySamples, 0.95),
      indexEstimatedBytes: stats.estimatedBytes,
      generatedAt: DateTime.now(),
    );
  }

  Future<List<VectorSearchHit>> _runQuery(
    LabeledSearchQuery labeled, {
    required int limit,
  }) async {
    if (labeled.imagePath != null && labeled.imagePath!.trim().isNotEmpty) {
      return discoveryService.searchByImagePath(labeled.imagePath!, limit: limit);
    }
    return discoveryService.search(labeled.query, limit: limit);
  }

  double _recallAtK(List<String> ranked, Set<String> relevant, int k) {
    if (relevant.isEmpty) return 0;
    final hits = ranked.take(k).where(relevant.contains).length;
    return hits / relevant.length;
  }

  double _ndcgAtK(List<String> ranked, Set<String> relevant, int k) {
    if (relevant.isEmpty) return 0;
    var dcg = 0.0;
    final top = ranked.take(k).toList(growable: false);
    for (var i = 0; i < top.length; i++) {
      final gain = relevant.contains(top[i]) ? 1.0 : 0.0;
      if (gain <= 0) continue;
      dcg += gain / _log2(i + 2);
    }

    final idealHits = math.min(k, relevant.length);
    var idcg = 0.0;
    for (var i = 0; i < idealHits; i++) {
      idcg += 1.0 / _log2(i + 2);
    }
    if (idcg <= 1e-9) return 0;
    return dcg / idcg;
  }

  double _mrr(List<String> ranked, Set<String> relevant) {
    if (relevant.isEmpty) return 0;
    for (var i = 0; i < ranked.length; i++) {
      if (relevant.contains(ranked[i])) {
        return 1.0 / (i + 1);
      }
    }
    return 0;
  }

  double _log2(int value) {
    return math.log(value) / math.ln2;
  }

  double _percentile(List<double> values, double percentile) {
    if (values.isEmpty) return 0;
    final sorted = values.toList(growable: false)..sort();
    final index = ((sorted.length - 1) * percentile).round().clamp(0, sorted.length - 1);
    return sorted[index];
  }

  int _percentileInt(List<int> values, double percentile) {
    if (values.isEmpty) return 0;
    final sorted = values.toList(growable: false)..sort();
    final index = ((sorted.length - 1) * percentile).round().clamp(0, sorted.length - 1);
    return sorted[index];
  }

  int _currentRss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }
}

extension SearchRelevanceBenchmarkReport on SearchRelevanceBenchmarkResult {
  String toMarkdown() {
    final recall = (recallAtK * 100).toStringAsFixed(2);
    final ndcg = (ndcgAtK * 100).toStringAsFixed(2);
    final mrrPercent = (mrr * 100).toStringAsFixed(2);
    return '''
# Search Relevance Benchmark

- Generated: $generatedAt
- Queries: $queryCount
- Target dataset range (500-2000): ${datasetWithinTargetRange ? 'within range' : 'outside range'}
- Recall@$k: $recall%
- nDCG@$k: $ndcg%
- MRR: $mrrPercent%
- Latency p50: ${latencyP50Ms.toStringAsFixed(2)} ms
- Latency p95: ${latencyP95Ms.toStringAsFixed(2)} ms
- Memory p95 (RSS): $memoryP95Bytes bytes
- Estimated vector index bytes: $indexEstimatedBytes
''';
  }
}
