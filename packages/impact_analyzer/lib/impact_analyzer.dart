/// Dart/Flutter change impact analysis: git diffs, symbol-level blast radius,
/// heuristic severity, and plan preflight.
library;

export 'src/analysis/dart_symbol_index.dart';
export 'src/analysis/impact_graph_builder.dart';
export 'src/config/impact_config.dart';
export 'src/errors/impact_error.dart';
export 'src/git/git_diff_collector.dart';
export 'src/git/git_runner.dart';
export 'src/ignore/ignore_rules.dart';
export 'src/models/impact_report.dart';
export 'src/orchestrator/impact_orchestrator.dart';
export 'src/plan/plan_extractor.dart';
export 'src/severity/severity_scorer.dart';
