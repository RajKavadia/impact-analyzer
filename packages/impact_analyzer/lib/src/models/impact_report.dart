/// Immutable value types describing an [ImpactReport].
///
/// The JSON shape mirrors docs/SPECIFICATION.md section 4.
library;

const String kReportVersion = '1';

/// Which input produced a report.
enum ImpactMode {
  workingTree('working_tree'),
  commitRange('commit_range'),
  plan('plan');

  const ImpactMode(this.jsonValue);

  final String jsonValue;

  static ImpactMode fromJson(String value) {
    for (final mode in values) {
      if (mode.jsonValue == value) return mode;
    }
    throw ArgumentError.value(value, 'value', 'Unknown ImpactMode');
  }
}

/// Git change status for a changed file.
enum ChangeStatus {
  added('added'),
  modified('modified'),
  deleted('deleted'),
  renamed('renamed');

  const ChangeStatus(this.jsonValue);

  final String jsonValue;

  static ChangeStatus fromJson(String value) {
    for (final status in values) {
      if (status.jsonValue == value) return status;
    }
    throw ArgumentError.value(value, 'value', 'Unknown ChangeStatus');
  }
}

/// Whether an impacted file is a direct (one hop) or transitive dependent.
enum ImpactRelation {
  direct('direct'),
  transitive('transitive');

  const ImpactRelation(this.jsonValue);

  final String jsonValue;

  static ImpactRelation fromJson(String value) {
    for (final relation in values) {
      if (relation.jsonValue == value) return relation;
    }
    throw ArgumentError.value(value, 'value', 'Unknown ImpactRelation');
  }
}

/// Heuristic risk band derived from impact metrics.
enum SeverityBand {
  low('low'),
  medium('medium'),
  high('high'),
  critical('critical');

  const SeverityBand(this.jsonValue);

  final String jsonValue;

  int get rank => index + 1;

  static SeverityBand fromJson(String value) {
    for (final band in values) {
      if (band.jsonValue == value) return band;
    }
    throw ArgumentError.value(value, 'value', 'Unknown SeverityBand');
  }

  static SeverityBand fromScore(double score) {
    if (score >= 0.75) return SeverityBand.critical;
    if (score >= 0.5) return SeverityBand.high;
    if (score >= 0.25) return SeverityBand.medium;
    return SeverityBand.low;
  }
}

/// How trustworthy an analysis is (distinct from severity).
enum ConfidenceBand {
  low('low'),
  medium('medium'),
  high('high');

  const ConfidenceBand(this.jsonValue);

  final String jsonValue;

  static ConfidenceBand fromJson(String value) {
    for (final band in values) {
      if (band.jsonValue == value) return band;
    }
    throw ArgumentError.value(value, 'value', 'Unknown ConfidenceBand');
  }

  static ConfidenceBand fromScore(double score) {
    if (score >= 0.75) return ConfidenceBand.high;
    if (score >= 0.4) return ConfidenceBand.medium;
    return ConfidenceBand.low;
  }
}

/// Kind of a graph node.
enum GraphNodeKind {
  file('file'),
  classType('class'),
  enumType('enum'),
  mixin('mixin'),
  extension('extension'),
  typedef('typedef'),
  function('function'),
  variable('variable');

  const GraphNodeKind(this.jsonValue);

  final String jsonValue;

  static GraphNodeKind fromJson(String value) {
    for (final kind in values) {
      if (kind.jsonValue == value) return kind;
    }
    throw ArgumentError.value(value, 'value', 'Unknown GraphNodeKind');
  }
}

/// Git header of a report.
class GitInfo {
  const GitInfo({
    required this.branch,
    required this.head,
    required this.isClean,
  });

  final String? branch;
  final String? head;
  final bool isClean;

  Map<String, Object?> toJson() => <String, Object?>{
        'branch': branch,
        'head': head,
        'isClean': isClean,
      };
}

/// A file reported by git as changed.
class ChangedFile {
  const ChangedFile({
    required this.path,
    required this.status,
    this.oldPath,
    this.symbols = const <String>[],
  });

  /// Repository-relative POSIX path.
  final String path;
  final ChangeStatus status;

  /// Previous path when [status] is renamed.
  final String? oldPath;

  /// Declared public symbols for Dart files; empty for other kinds.
  final List<String> symbols;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'status': status.jsonValue,
        'symbols': symbols,
        if (oldPath != null) 'oldPath': oldPath,
      };
}

/// A file that depends on a changed symbol.
class ImpactedFile {
  const ImpactedFile({
    required this.path,
    required this.relation,
    required this.reason,
    this.impactedSymbols = const <String>[],
    this.depth = 1,
  });

  final String path;
  final ImpactRelation relation;
  final String reason;

  /// Types in this file that reference changed symbols.
  final List<String> impactedSymbols;

  /// BFS depth at which the file was reached (1 = direct).
  final int depth;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'relation': relation.jsonValue,
        'reason': reason,
        'impactedSymbols': impactedSymbols,
        'depth': depth,
      };
}

/// A node of the impact graph (file or symbol).
class GraphNode {
  const GraphNode({
    required this.id,
    required this.kind,
    this.changed = false,
    this.file,
  });

  final String id;
  final GraphNodeKind kind;

  /// True for seed (changed) nodes.
  final bool changed;

  /// Declaring file for symbol nodes.
  final String? file;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.jsonValue,
        'changed': changed,
        if (file != null) 'file': file,
      };
}

/// An edge of the impact graph.
class GraphEdge {
  const GraphEdge({
    required this.from,
    required this.to,
    required this.type,
  });

  final String from;
  final String to;

  /// `imports` (file -> file) or `references` (file -> symbol).
  final String type;

  Map<String, Object?> toJson() => <String, Object?>{
        'from': from,
        'to': to,
        'type': type,
      };
}

/// The impact graph emitted for dashboards and MCP.
class ImpactGraph {
  const ImpactGraph({
    required this.nodes,
    required this.edges,
    this.truncated = false,
  });

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  /// True when the builder or a surface capped the node/edge count.
  final bool truncated;

  Map<String, Object?> toJson() => <String, Object?>{
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'truncated': truncated,
      };
}

/// Counters derived from the impact set.
class ImpactMetrics {
  const ImpactMetrics({
    required this.changedFileCount,
    required this.impactedFileCount,
    required this.impactedClassCount,
    required this.directCount,
    required this.transitiveCount,
    required this.publicApiHits,
    required this.impactedTestCount,
    required this.maxDepthReached,
    required this.analyzedFileCount,
  });

  /// Number of changed Dart files (non-Dart changes are excluded).
  final int changedFileCount;

  /// Impacted files, excluding the changed files themselves.
  final int impactedFileCount;

  /// Distinct changed + referenced class/type count.
  final int impactedClassCount;
  final int directCount;
  final int transitiveCount;
  final int publicApiHits;
  final int impactedTestCount;

  /// Deepest BFS level actually reached (0 when nothing impacted).
  final int maxDepthReached;

  /// Dart files inspected while building the index.
  final int analyzedFileCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'changedFileCount': changedFileCount,
        'impactedFileCount': impactedFileCount,
        'impactedClassCount': impactedClassCount,
        'directCount': directCount,
        'transitiveCount': transitiveCount,
        'publicApiHits': publicApiHits,
        'impactedTestCount': impactedTestCount,
        'maxDepthReached': maxDepthReached,
        'analyzedFileCount': analyzedFileCount,
      };
}

/// Severity score with a transparent rationale.
class SeverityResult {
  const SeverityResult({
    required this.band,
    required this.score,
    required this.rationale,
  });

  final SeverityBand band;

  /// 0.0 - 1.0, rounded to 3 decimals.
  final double score;
  final List<String> rationale;

  Map<String, Object?> toJson() => <String, Object?>{
        'band': band.jsonValue,
        'score': score,
        'rationale': rationale,
      };
}

/// Confidence in the analysis (never a break guarantee).
class ConfidenceResult {
  const ConfidenceResult({
    required this.band,
    required this.score,
    required this.notes,
  });

  final ConfidenceBand band;
  final double score;
  final List<String> notes;

  Map<String, Object?> toJson() => <String, Object?>{
        'band': band.jsonValue,
        'score': score,
        'notes': notes,
      };
}

/// The single report produced by every surface.
class ImpactReport {
  const ImpactReport({
    required this.rootPath,
    required this.mode,
    required this.generatedAt,
    required this.git,
    required this.changedFiles,
    required this.impactedFiles,
    required this.graph,
    required this.metrics,
    required this.severity,
    required this.confidence,
    this.warnings = const <String>[],
  });

  final String version = kReportVersion;
  final String rootPath;
  final ImpactMode mode;
  final String generatedAt;
  final GitInfo git;
  final List<ChangedFile> changedFiles;
  final List<ImpactedFile> impactedFiles;
  final ImpactGraph graph;
  final ImpactMetrics metrics;
  final SeverityResult severity;
  final ConfidenceResult confidence;
  final List<String> warnings;

  /// Graph-free summary used by token-cheap surfaces (MCP summary tool).
  ImpactReport withoutGraph() => ImpactReport(
        rootPath: rootPath,
        mode: mode,
        generatedAt: generatedAt,
        git: git,
        changedFiles: changedFiles,
        impactedFiles: impactedFiles,
        graph: const ImpactGraph(nodes: [], edges: []),
        metrics: metrics,
        severity: severity,
        confidence: confidence,
        warnings: warnings,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'rootPath': rootPath,
        'mode': mode.jsonValue,
        'generatedAt': generatedAt,
        'git': git.toJson(),
        'changedFiles': changedFiles.map((f) => f.toJson()).toList(),
        'impactedFiles': impactedFiles.map((f) => f.toJson()).toList(),
        'graph': graph.toJson(),
        'metrics': metrics.toJson(),
        'severity': severity.toJson(),
        'confidence': confidence.toJson(),
        'warnings': warnings,
      };
}
