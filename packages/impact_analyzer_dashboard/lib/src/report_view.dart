import 'dart:convert';

import 'package:impact_analyzer/impact_analyzer.dart';

/// Serializes an [ImpactReport] into the shapes the dashboard serves.
///
/// Every endpoint returns JSON that is valid for humans *and* agents: the same
/// document powers the UI and is copyable for scripted use.
class ReportView {
  const ReportView._();

  /// Full report document (identical to the CLI's `--json` output).
  static Map<String, Object?> full(ImpactReport report) => report.toJson();

  /// Token-cheap summary, mirroring the MCP `get_impact_summary` contract.
  ///
  /// Sized for an agent to poll frequently without flooding its context.
  static Map<String, Object?> summary(
    ImpactReport report, {
    int topFiles = 5,
  }) {
    final top = report.impactedFiles.take(topFiles).map((f) => f.path).toList();
    return <String, Object?>{
      'mode': report.mode.jsonValue,
      'generatedAt': report.generatedAt,
      'git': report.git.toJson(),
      'changedFileCount': report.metrics.changedFileCount,
      'impactedFileCount': report.metrics.impactedFileCount,
      'impactedClassCount': report.metrics.impactedClassCount,
      'directCount': report.metrics.directCount,
      'transitiveCount': report.metrics.transitiveCount,
      'publicApiHits': report.metrics.publicApiHits,
      'impactedTestCount': report.metrics.impactedTestCount,
      'severity': report.severity.band.jsonValue,
      'score': report.severity.score,
      'confidence': report.confidence.band.jsonValue,
      'topImpactedFiles': top,
      'rationale': report.severity.rationale,
      'notes': report.confidence.notes,
      'warnings': report.warnings,
    };
  }

  /// Graph projection with an optional node cap.
  ///
  /// Truncation is explicit so a consumer never mistakes a capped graph for a
  /// complete one.
  static Map<String, Object?> graph(ImpactReport report, {int? maxNodes}) {
    var nodes = report.graph.nodes;
    var edges = report.graph.edges;
    final truncated = report.graph.truncated;

    if (maxNodes != null && nodes.length > maxNodes) {
      // Keep changed files (the seeds) plus as many impacted nodes as fit, so
      // the truncated view still explains the blast radius.
      final changed = nodes.where((n) => n.changed).toList();
      final impacted = nodes.where((n) => !n.changed).toList();
      final room = maxNodes > changed.length ? maxNodes - changed.length : 0;
      final kept = <GraphNode>[...changed.take(maxNodes), ...impacted.take(room)];
      final keptIds = kept.map((n) => n.id).toSet();
      nodes = kept;
      edges = edges
          .where((e) => keptIds.contains(e.from) || keptIds.contains(e.to))
          .toList();
      return <String, Object?>{
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'truncated': true,
        'totalNodes': report.graph.nodes.length,
        'totalEdges': report.graph.edges.length,
      };
    }

    return <String, Object?>{
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
      'truncated': truncated,
      'totalNodes': report.graph.nodes.length,
      'totalEdges': report.graph.edges.length,
    };
  }

  /// Structured error body.
  ///
  /// Uses the flat `{code, message, details}` shape from
  /// docs/SPECIFICATION.md section 11 so dashboard, CLI and MCP all agree.
  static Map<String, Object?> error(
    String code,
    String message, {
    Map<String, Object?> details = const <String, Object?>{},
  }) =>
      <String, Object?>{
        'code': code,
        'message': message,
        'details': details,
      };

  static String encode(Object? value) => const JsonEncoder.withIndent('  ').convert(value);
}