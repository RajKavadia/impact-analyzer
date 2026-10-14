import 'package:impact_analyzer/impact_analyzer.dart';
import 'package:test/test.dart';

ImpactMetrics _metrics({
  int impactedFiles = 0,
  int impactedClasses = 0,
  int publicApi = 0,
  int tests = 0,
  int depth = 0,
}) {
  return ImpactMetrics(
    changedFileCount: 1,
    impactedFileCount: impactedFiles,
    impactedClassCount: impactedClasses,
    directCount: impactedFiles,
    transitiveCount: 0,
    publicApiHits: publicApi,
    impactedTestCount: tests,
    maxDepthReached: depth,
    analyzedFileCount: 10,
  );
}

void main() {
  group('SeverityScorer', () {
    final scorer = SeverityScorer(config: ImpactConfig.defaults());

    test('no impact is low with an empty-ish rationale', () {
      final result = scorer.score(_metrics(), 0);
      expect(result.band, SeverityBand.low);
      expect(result.score, 0.0);
      expect(result.rationale, ['no impacted files or classes']);
    });

    test('saturated signals produce critical', () {
      // F=25, C=15, P=5, U=5, D=5, T=10 all saturate the normalizers.
      final result = scorer.score(
        _metrics(
          impactedFiles: 25,
          impactedClasses: 15,
          publicApi: 5,
          tests: 10,
          depth: 5,
        ),
        5,
      );
      expect(result.band, SeverityBand.critical);
      expect(result.score, 1.0);
    });

    test('public API hits weigh more than file count', () {
      final files = scorer.score(_metrics(impactedFiles: 25), 0);
      final api = scorer.score(_metrics(publicApi: 5), 0);
      expect(api.score, greaterThan(files.score));
    });

    test('scores are clamped to 0..1 and rounded', () {
      final result = scorer.score(
        _metrics(impactedFiles: 999, impactedClasses: 999, publicApi: 999, tests: 999, depth: 999),
        999,
      );
      expect(result.score, lessThanOrEqualTo(1.0));
      expect(result.score, greaterThanOrEqualTo(0.0));
      expect(result.score * 1000, (result.score * 1000).roundToDouble());
    });

    test('rationale explains every non-zero signal', () {
      final result = scorer.score(
        _metrics(impactedFiles: 3, impactedClasses: 2, publicApi: 1, tests: 1, depth: 2),
        1,
      );
      expect(result.rationale, contains('2 impacted classes (weight 1.5)'));
      expect(result.rationale, contains('1 public API hits (weight 2.0)'));
      expect(result.rationale, contains('3 impacted files (weight 1.0)'));
      expect(result.rationale, contains('transitive depth 2 (weight 0.5)'));
      expect(result.rationale, contains('1 impacted tests (weight 0.25)'));
      expect(result.rationale.any((r) => r.contains('Flutter UI root')), isTrue);
    });

    test('custom weights from config change the score', () {
      final heavy = SeverityScorer(
        config: ImpactConfig(weights: const SeverityWeights(publicApi: 10.0)),
      );
      final result = heavy.score(_metrics(publicApi: 5), 0);
      expect(result.score, greaterThan(0.2));
    });
  });

  group('SeverityBand', () {
    test('maps scores to documented bands', () {
      expect(SeverityBand.fromScore(0.0), SeverityBand.low);
      expect(SeverityBand.fromScore(0.24), SeverityBand.low);
      expect(SeverityBand.fromScore(0.25), SeverityBand.medium);
      expect(SeverityBand.fromScore(0.5), SeverityBand.high);
      expect(SeverityBand.fromScore(0.75), SeverityBand.critical);
      expect(SeverityBand.fromScore(1.0), SeverityBand.critical);
    });

    test('rank orders bands for --fail-on comparisons', () {
      expect(SeverityBand.low.rank, lessThan(SeverityBand.medium.rank));
      expect(SeverityBand.medium.rank, lessThan(SeverityBand.high.rank));
      expect(SeverityBand.high.rank, lessThan(SeverityBand.critical.rank));
    });
  });
}