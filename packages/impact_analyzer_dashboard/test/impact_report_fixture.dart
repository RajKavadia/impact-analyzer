import 'package:impact_analyzer/impact_analyzer.dart';

/// Builds a small in-memory report for view-projection tests.
class ImpactReportFixture {
  const ImpactReportFixture._();

  static ImpactReport build() {
    return ImpactReport(
      rootPath: '/repo',
      mode: ImpactMode.workingTree,
      generatedAt: '2026-01-01T00:00:00.000Z',
      git: const GitInfo(branch: 'main', head: 'abc1234', isClean: false),
      changedFiles: const [
        ChangedFile(
          path: 'lib/a.dart',
          status: ChangeStatus.modified,
          symbols: ['Alpha'],
        ),
      ],
      impactedFiles: const [
        ImpactedFile(
          path: 'lib/b.dart',
          relation: ImpactRelation.direct,
          reason: 'references Alpha',
          impactedSymbols: ['Beta'],
        ),
        ImpactedFile(
          path: 'lib/c.dart',
          relation: ImpactRelation.transitive,
          reason: 'imports lib/b.dart',
        ),
      ],
      graph: const ImpactGraph(
        nodes: [
          GraphNode(id: 'lib/a.dart', kind: GraphNodeKind.file, changed: true),
          GraphNode(id: 'Alpha', kind: GraphNodeKind.classType, changed: true, file: 'lib/a.dart'),
          GraphNode(id: 'lib/b.dart', kind: GraphNodeKind.file),
          GraphNode(id: 'lib/c.dart', kind: GraphNodeKind.file),
        ],
        edges: [
          GraphEdge(from: 'lib/b.dart', to: 'Alpha', type: 'references'),
          GraphEdge(from: 'lib/c.dart', to: 'lib/b.dart', type: 'imports'),
        ],
      ),
      metrics: const ImpactMetrics(
        changedFileCount: 1,
        impactedFileCount: 2,
        impactedClassCount: 3,
        directCount: 1,
        transitiveCount: 1,
        publicApiHits: 2,
        impactedTestCount: 1,
        maxDepthReached: 2,
        analyzedFileCount: 20,
      ),
      severity: const SeverityResult(
        band: SeverityBand.high,
        score: 0.62,
        rationale: <String>['3 impacted classes (weight 1.5)'],
      ),
      confidence: const ConfidenceResult(
        band: ConfidenceBand.high,
        score: 0.95,
        notes: <String>[],
      ),
    );
  }
}