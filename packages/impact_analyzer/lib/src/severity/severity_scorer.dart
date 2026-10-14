import '../config/impact_config.dart';
import '../models/impact_report.dart';

/// Computes the heuristic severity band per docs/SEVERITY.md.
class SeverityScorer {
  SeverityScorer({required this.config});

  final ImpactConfig config;

  static const double _rawMax = 6.75;

  SeverityResult score(ImpactMetrics metrics, int flutterRootCount) {
    final weights = config.weights;
    final denominators = config.denominators;

    final f = _saturate(metrics.impactedFileCount, denominators.impactedFile);
    final c = _saturate(metrics.impactedClassCount, denominators.impactedClass);
    final p = _saturate(metrics.publicApiHits, denominators.publicApi);
    final u = _saturate(flutterRootCount, denominators.flutterUiRoot);
    final d = _saturate(metrics.maxDepthReached, denominators.depth);
    final t = _saturate(metrics.impactedTestCount, denominators.tests);

    final raw = weights.impactedFile * f +
        weights.impactedClass * c +
        weights.publicApi * p +
        weights.flutterUiRoot * u +
        weights.depth * d +
        weights.tests * t;

    final score = (raw / _rawMax).clamp(0.0, 1.0);
    final rounded = (score * 1000).roundToDouble() / 1000;
    final band = SeverityBand.fromScore(rounded);
    return SeverityResult(
      band: band,
      score: rounded,
      rationale: _rationale(
        weights,
        metrics,
        flutterRootCount,
      ),
    );
  }

  List<String> _rationale(
    SeverityWeights weights,
    ImpactMetrics metrics,
    int flutterRootCount,
  ) {
    final reasons = <String>[];

    if (metrics.impactedClassCount > 0) {
      reasons.add('${metrics.impactedClassCount} impacted classes (weight ${weights.impactedClass})');
    }
    if (metrics.publicApiHits > 0) {
      reasons.add('${metrics.publicApiHits} public API hits (weight ${weights.publicApi})');
    }
    if (metrics.impactedFileCount > 0) {
      reasons.add('${metrics.impactedFileCount} impacted files (weight ${weights.impactedFile})');
    }
    if (flutterRootCount > 0) {
      reasons.add('$flutterRootCount Flutter UI root types in impact set (weight ${weights.flutterUiRoot})');
    }
    if (metrics.maxDepthReached > 0) {
      reasons.add('transitive depth ${metrics.maxDepthReached} (weight ${weights.depth})');
    }
    if (metrics.impactedTestCount > 0) {
      reasons.add('${metrics.impactedTestCount} impacted tests (weight ${weights.tests})');
    }
    if (reasons.isEmpty) {
      reasons.add('no impacted files or classes');
    }
    return reasons;
  }
}

double _saturate(int count, double denominator) {
  if (denominator <= 0) return 0.0;
  if (count <= 0) return 0.0;
  return (count / denominator).clamp(0.0, 1.0);
}
