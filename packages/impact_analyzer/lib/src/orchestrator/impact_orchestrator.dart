import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/dart_symbol_index.dart';
import '../analysis/impact_graph_builder.dart';
import '../config/impact_config.dart';
import '../errors/impact_error.dart';
import '../git/git_diff_collector.dart';
import '../git/git_runner.dart';
import '../ignore/ignore_rules.dart';
import '../models/impact_report.dart';
import '../plan/plan_extractor.dart';
import '../severity/severity_scorer.dart';

/// Wires the full pipeline: git -> index -> graph -> score -> report.
///
/// Surfaces (CLI, MCP, dashboard) only call this class so scoring can never
/// diverge between them.
class ImpactOrchestrator {
  ImpactOrchestrator({
    required this.rootPath,
    ImpactConfig? config,
    GitRunner? gitRunner,
  })  : config = config ?? ImpactConfig.defaults(),
        _runner = gitRunner ?? GitRunner();

  /// Path provided by the caller (usually CWD).
  final String rootPath;

  final ImpactConfig config;
  final GitRunner _runner;

  DartSymbolIndex? _cachedIndex;
  String? _cachedIndexFor;

  Future<ImpactReport> analyzeWorkingTree({
    GitChangeScope scope = GitChangeScope.all,
    bool includeTests = true,
    int? maxDepth,
  }) async {
    final collector = _collectorFor(rootPath);
    final repoRoot = await collector.detectRepoRoot(rootPath);
    final changeSet = await _collectorFor(repoRoot).collectWorkingTree(
      repoRoot,
      scope: scope,
    );
    return _run(
      repoRoot: repoRoot,
      mode: ImpactMode.workingTree,
      git: changeSet.git,
      changedFiles: changeSet.changedFiles,
      includeTests: includeTests,
      maxDepth: maxDepth,
    );
  }

  Future<ImpactReport> analyzeCommitRange({
    required String baseRef,
    String headRef = 'HEAD',
    bool includeTests = true,
    int? maxDepth,
  }) async {
    final collector = _collectorFor(rootPath);
    final repoRoot = await collector.detectRepoRoot(rootPath);
    final changeSet = await _collectorFor(repoRoot).collectCommitRange(
      repoRoot,
      baseRef: baseRef,
      headRef: headRef,
    );
    return _run(
      repoRoot: repoRoot,
      mode: ImpactMode.commitRange,
      git: changeSet.git,
      changedFiles: changeSet.changedFiles,
      includeTests: includeTests,
      maxDepth: maxDepth,
    );
  }

  Future<ImpactReport> analyzePlan({
    String? planText,
    Object? planJson,
    bool includeTests = true,
    int? maxDepth,
  }) async {
    if (planText == null && planJson == null) {
      throw ImpactError(
        ImpactErrorCodes.invalidPlan,
        'provide planText or planJson',
      );
    }
    final collector = _collectorFor(rootPath);
    final repoRoot = await collector.detectRepoRoot(rootPath);
    final index = await _index(repoRoot);
    final changeSet =
        await _collectorFor(repoRoot).collectWorkingTree(repoRoot);

    final extractor = PlanExtractor(index);
    final plan = planJson != null
        ? extractor.fromStructured(planJson)
        : extractor.fromMarkdown(planText!);

    final changedFiles = <ChangedFile>[];
    final symbolScope = <String, Set<String>>{};
    for (final candidate in plan.files) {
      final unit = index.unitOf(candidate.path);
      final declared =
          unit?.declarations.where((s) => s.isPublic && !s.name.startsWith('_')).toList() ??
              const <DeclaredSymbol>[];

      // When a plan names symbols, scope the change to those symbols only.
      // Plans may name a symbol bare (`refreshToken`) or qualified
      // (`TokenService.refreshToken`); both forms are accepted.
      final names = candidate.symbols.where((s) => s.isNotEmpty).toSet();
      bool matches(DeclaredSymbol symbol) {
        if (names.contains(symbol.name)) return true;
        final enclosing = symbol.enclosing;
        return enclosing != null && names.contains('$enclosing.${symbol.name}');
      }

      final matched = names.isEmpty
          ? declared
          : declared.where(matches).toList();
      // If none of the named symbols exist, fall back to the whole file rather
      // than reporting a false "no impact".
      final symbols = matched.isEmpty ? declared : matched;
      if (names.isNotEmpty) {
        symbolScope[candidate.path] = {for (final s in symbols) s.key};
      }

      changedFiles.add(ChangedFile(
        path: candidate.path,
        status: candidate.exists ? ChangeStatus.modified : ChangeStatus.added,
        symbols: symbols.map((s) => s.name).toList()..sort(),
      ));
    }

    final report = await _run(
      repoRoot: repoRoot,
      mode: ImpactMode.plan,
      git: changeSet.git,
      changedFiles: changedFiles,
      includeTests: includeTests,
      maxDepth: maxDepth,
      planNotes: plan.notes,
      planKind: plan.kind,
      symbolScope: symbolScope,
    );

    return report;
  }

  GitDiffCollector _collectorFor(String basePath) => GitDiffCollector(
        runner: _runner,
        ignoreRules: IgnoreRules.fromRepository(
          basePath,
          configIgnores: config.ignores,
        ),
      );

  Future<String> _verifyDartProject(String repoRoot) async {
    final rootPubspec = File(p.join(repoRoot, 'pubspec.yaml'));
    if (rootPubspec.existsSync()) return repoRoot;
    // Workspace-style repos: any member pubspec is enough.
    final entities = Directory(repoRoot).listSync(followLinks: false);
    for (final entity in entities) {
      if (entity is Directory && File(p.join(entity.path, 'pubspec.yaml')).existsSync()) {
        return repoRoot;
      }
    }
    throw ImpactError(
      ImpactErrorCodes.notDartProject,
      'no pubspec.yaml found at $repoRoot (or its immediate members)',
    );
  }

  Future<DartSymbolIndex> _index(String repoRoot) async {
    await _verifyDartProject(repoRoot);
    if (_cachedIndex != null && _cachedIndexFor == repoRoot) {
      return _cachedIndex!;
    }
    final index = await DartSymbolIndex.build(
      repoRoot: repoRoot,
      ignoreRules: IgnoreRules.fromRepository(repoRoot, configIgnores: config.ignores),
    );
    _cachedIndex = index;
    _cachedIndexFor = repoRoot;
    return index;
  }

  Future<ImpactReport> _run({
    required String repoRoot,
    required ImpactMode mode,
    required GitInfo git,
    required List<ChangedFile> changedFiles,
    required bool includeTests,
    required int? maxDepth,
    List<String> planNotes = const <String>[],
    PlanExtractionKind? planKind,
    Map<String, Set<String>> symbolScope = const <String, Set<String>>{},
  }) async {
    final index = await _index(repoRoot);

    final builder = ImpactGraphBuilder(
      index: index,
      config: config,
      maxDepth: maxDepth ?? config.maxDepth,
      includeTests: includeTests,
      symbolScope: symbolScope,
    );
    final analysis = builder.build(changedFiles);

    final scorer = SeverityScorer(config: config);
    final severity = scorer.score(analysis.metrics, analysis.flutterRootCount);
    final confidence = _confidence(
      index: index,
      analysis: analysis,
      planKind: planKind,
      planNotes: planNotes,
    );

    final warnings = <String>[...index.warnings, ...planNotes];

    return ImpactReport(
      rootPath: repoRoot,
      mode: mode,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      git: git,
      changedFiles: changedFiles,
      impactedFiles: analysis.impactedFiles,
      graph: analysis.graph,
      metrics: analysis.metrics,
      severity: severity,
      confidence: confidence,
      warnings: warnings,
    );
  }

  ConfidenceResult _confidence({
    required DartSymbolIndex index,
    required ImpactAnalysis analysis,
    PlanExtractionKind? planKind,
    List<String> planNotes = const <String>[],
  }) {
    final notes = <String>[];
    var score = 1.0;

    if (index.fallback) {
      score = 0.3;
      notes.add('package_config.json missing; using import-level fallback analysis');
    } else if (index.warnings.isNotEmpty) {
      score = 0.65;
      notes.add('${index.warnings.length} file(s) could not be fully resolved');
    }

    if (planKind == PlanExtractionKind.freeText) {
      if (score > 0.55) score = 0.55;
      notes.add('plan parsed from free text; inferred paths may be ambiguous');
    }
    if (analysis.graph.truncated) {
      if (score > 0.5) score = 0.5;
      notes.add('impact graph truncated');
    }
    for (final note in planNotes) {
      if (note.startsWith('path in plan not found')) {
        score -= 0.1;
      }
    }
    notes.addAll(planNotes);

    score = score.clamp(0.0, 1.0);
    return ConfidenceResult(
      band: ConfidenceBand.fromScore(score),
      score: (score * 100).roundToDouble() / 100,
      notes: notes,
    );
  }
}