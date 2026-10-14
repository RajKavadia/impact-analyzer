import '../config/impact_config.dart';
import '../models/impact_report.dart';
import 'dart_symbol_index.dart';

/// Result of building the impact graph and metrics.
class ImpactAnalysis {
  const ImpactAnalysis({
    required this.impactedFiles,
    required this.graph,
    required this.metrics,
    required this.flutterRootCount,
    required this.warnings,
  });

  final List<ImpactedFile> impactedFiles;
  final ImpactGraph graph;
  final ImpactMetrics metrics;

  /// Distinct changed/impacted types matching configured Flutter UI roots.
  final int flutterRootCount;

  final List<String> warnings;
}

/// Builds the symbol/import impact graph for a set of changed files.
class ImpactGraphBuilder {
  ImpactGraphBuilder({
    required this.index,
    required this.config,
    this.maxDepth = 5,
    this.includeTests = true,
    this.symbolScope = const <String, Set<String>>{},
  });

  final DartSymbolIndex index;
  final ImpactConfig config;
  final int maxDepth;
  final bool includeTests;

  /// Restricts a file to the symbols a plan explicitly named, keyed by
  /// repo-relative file path. Files absent from this map use every declaration.
  final Map<String, Set<String>> symbolScope;

  ImpactAnalysis build(List<ChangedFile> changedFiles) {
    final changedDart = changedFiles
        .where((f) => f.path.endsWith('.dart'))
        .toList(growable: false);

    // 1. Changed symbol keys: top-level declarations plus public members.
    final changedKeys = <String>{};
    final changedTypes = <DeclaredSymbol>[];
    for (final file in changedDart) {
      final unit = index.unitOf(file.path);
      if (unit == null) continue;
      final scoped = symbolScope[file.path];
      for (final symbol in unit.declarations) {
        // A plan that names specific symbols must not mark the whole file.
        if (scoped != null && !scoped.contains(symbol.key)) continue;
        changedKeys.add(symbol.key);
        if (symbol.isTopLevel && symbol.isTypeKind) changedTypes.add(symbol);
      }
    }

    // 2. Reverse import index: library path -> importing files.
    final importers = <String, Set<String>>{};
    for (final unit in index.unitsByPath.values) {
      for (final imported in unit.imports) {
        importers.putIfAbsent(imported, () => <String>{}).add(unit.path);
      }
    }

    // 3. BFS from changed files, up to maxDepth.
    //
    // Seeds are the *library* each changed file belongs to, so a change inside a
    // `part` file still expands through the library that importers depend on.
    final depthOf = <String, int>{};
    final queue = <String>[];
    for (final file in changedDart) {
      final unit = index.unitOf(file.path);
      final seed = unit?.library ?? index.toAbsolute(file.path);
      if (depthOf.containsKey(seed)) continue;
      depthOf[seed] = 0;
      queue.add(seed);
    }
    var maxDepthReached = 0;
    for (var head = 0; head < queue.length; head++) {
      final current = queue[head];
      final currentDepth = depthOf[current]!;
      if (currentDepth >= maxDepth) continue;
      for (final importer in importers[current] ?? const <String>{}) {
        if (depthOf.containsKey(importer)) continue;
        depthOf[importer] = currentDepth + 1;
        if (currentDepth + 1 > maxDepthReached) maxDepthReached = currentDepth + 1;
        queue.add(importer);
      }
    }

    // 4. Impacted files, graph nodes and edges.
    final impacted = <ImpactedFile>[];
    final nodes = <String, GraphNode>{};
    final edges = <String, GraphEdge>{};

    for (final file in changedDart) {
      final absolute = index.toAbsolute(file.path);
      nodes[absolute] = GraphNode(
        id: index.toRelative(absolute),
        kind: GraphNodeKind.file,
        changed: true,
      );
    }

    final impactedNames = <String>{}; // types referenced from dependents
    final apiKeys = <String>{};
    final rootNames = <String>{};

    for (final symbol in changedTypes) {
      final nodeId = _nodeIdFor(symbol, index);
      nodes[symbol.key] = GraphNode(
        id: nodeId,
        kind: _kindOf(symbol.kind),
        changed: true,
        file: index.toRelative(symbol.file),
      );
      if (index.isPublicApiSymbol(symbol)) apiKeys.add(symbol.key);
      if (index.isFlutterRootType(symbol, config.flutterRoots)) {
        rootNames.add(symbol.key);
      }
    }

    final entries = depthOf.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final depthCompare = a.value.compareTo(b.value);
        return depthCompare != 0 ? depthCompare : a.key.compareTo(b.key);
      });

    for (final entry in entries) {
      final filePath = entry.key;
      final relativePath = index.toRelative(filePath);
      final depth = entry.value;
      final isTest = _isTestFile(relativePath);
      if (!includeTests && isTest) continue;

      final unit = index.unitOf(filePath);
      final referencedKeys = <String>{};
      final referencedNames = <String>{};
      if (unit != null) {
        // Types declared in this file, ordered by position so a reference can
        // be attributed to the declaration that encloses it.
        final localTypes = unit.declarations
            .where((s) => s.isTopLevel && s.isTypeKind)
            .toList()
          ..sort((a, b) {
            final ao = a.offset;
            final bo = b.offset;
            if (ao == null || bo == null) return a.name.compareTo(b.name);
            return ao.compareTo(bo);
          });
        final positional = localTypes.where((s) => s.offset != null).toList();

        void attribute(String key) {
          referencedNames.add(key);
          impactedNames.add(key);
          final symbol = index.symbolsByKey[key];
          if (symbol == null) return;
          if (index.isPublicApiSymbol(symbol)) apiKeys.add(key);
          if (index.isFlutterRootType(symbol, config.flutterRoots)) {
            rootNames.add(key);
          }
        }

        for (final reference in unit.references) {
          final matchedKeys = reference.keys.where(changedKeys.contains).toList();
          if (matchedKeys.isEmpty) continue;
          referencedKeys.addAll(matchedKeys);

          final offset = reference.offset;
          if (offset != null && positional.isNotEmpty) {
            // Precise: only the innermost enclosing type is impacted.
            DeclaredSymbol? enclosing;
            for (final candidate in positional) {
              if (candidate.offset! <= offset) {
                enclosing = candidate;
              } else {
                break;
              }
            }
            if (enclosing != null) attribute(enclosing.key);
          } else {
            // Conservative fallback when offsets are unavailable
            // (regex fallback mode): treat the file's types as impacted.
            for (final symbol in localTypes) {
              attribute(symbol.key);
            }
          }
        }

        // An import-level dependency with no symbol-level match still marks
        // the file as impacted, but does not inflate class counts.
        if (referencedKeys.isEmpty && localTypes.isNotEmpty) {
          for (final symbol in localTypes) {
            referencedNames.add(symbol.key);
          }
        }
      }

      final relation =
          depth == 1 ? ImpactRelation.direct : ImpactRelation.transitive;
      final reason = referencedKeys.isNotEmpty
          ? 'references ${referencedKeys.map((k) => _nameOf(k)).join(', ')}'
          : _importReason(index, filePath, changedDart) ?? 'depends on a changed library';

      impacted.add(ImpactedFile(
        path: relativePath,
        relation: relation,
        reason: reason,
        impactedSymbols: referencedNames.map((k) => _nameOf(k)).toList()..sort(),
        depth: depth,
      ));

      nodes[filePath] = GraphNode(
        id: relativePath,
        kind: GraphNodeKind.file,
        changed: false,
      );

      if (unit != null) {
        for (final imported in unit.imports) {
          if (depthOf.containsKey(imported)) {
            final target = index.toRelative(imported);
            edges.putIfAbsent(
              '$relativePath|imports|$target',
              () => GraphEdge(from: relativePath, to: target, type: 'imports'),
            );
          }
        }
      }
      for (final key in referencedKeys.toList()..sort()) {
        final symbol = index.symbolsByKey[key];
        final nodeId = symbol != null ? _nodeIdFor(symbol, index) : _nameOf(key);
        edges.putIfAbsent(
          '$relativePath|references|$nodeId',
          () => GraphEdge(from: relativePath, to: nodeId, type: 'references'),
        );
        if (symbol != null) {
          nodes.putIfAbsent(
            key,
            () => GraphNode(
              id: nodeId,
              kind: _kindOf(symbol.kind),
              changed: true,
              file: index.toRelative(symbol.file),
            ),
          );
        }
      }
    }

    final changedTypeKeys = changedTypes.map((s) => s.key).toSet();
    final classCount = (changedTypeKeys..addAll(impactedNames)).length;
    final directCount = impacted.where((f) => f.relation == ImpactRelation.direct).length;
    final transitiveCount =
        impacted.where((f) => f.relation == ImpactRelation.transitive).length;
    final testCount = impacted.where((f) => _isTestFile(f.path)).length;

    final metrics = ImpactMetrics(
      changedFileCount: changedDart.length,
      impactedFileCount: impacted.length,
      impactedClassCount: classCount,
      directCount: directCount,
      transitiveCount: transitiveCount,
      publicApiHits: apiKeys.length,
      impactedTestCount: testCount,
      maxDepthReached: maxDepthReached,
      analyzedFileCount: index.analyzedFileCount,
    );

    return ImpactAnalysis(
      impactedFiles: impacted,
      graph: ImpactGraph(
        nodes: nodes.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
        edges: edges.values.toList()
          ..sort((a, b) =>
              '${a.from}|${a.to}'.compareTo('${b.from}|${b.to}')),
        truncated: false,
      ),
      metrics: metrics,
      flutterRootCount: rootNames.length,
      warnings: const <String>[],
    );
  }
}

GraphNodeKind _kindOf(SymbolKind kind) => switch (kind) {
      SymbolKind.classType => GraphNodeKind.classType,
      SymbolKind.enumType => GraphNodeKind.enumType,
      SymbolKind.mixin => GraphNodeKind.mixin,
      SymbolKind.extension => GraphNodeKind.extension,
      SymbolKind.typedef => GraphNodeKind.typedef,
      SymbolKind.function => GraphNodeKind.function,
      SymbolKind.variable => GraphNodeKind.variable,
    };

/// Stable node id: the symbol name when unambiguous, else the full key.
String _nodeIdFor(DeclaredSymbol symbol, DartSymbolIndex index) {
  // `symbolsByName` is prebuilt, so this stays O(1) per symbol instead of
  // rescanning every declaration for each name collision check.
  final sameName = index.symbolsByName[symbol.name];
  if (sameName != null && sameName.length > 1) return symbol.key;
  return symbol.name;
}

String _nameOf(String key) => key.contains('#') ? key.split('#').last : key;

/// True for files under a `test/` directory or named `*_test.dart`.
///
/// Expects a repo-relative POSIX path.
bool _isTestFile(String relativePath) {
  final normalized = relativePath.toLowerCase();
  return normalized.startsWith('test/') ||
      normalized.contains('/test/') ||
      normalized.endsWith('_test.dart');
}

String? _importReason(
  DartSymbolIndex index,
  String filePath,
  List<ChangedFile> changedDart,
) {
  final unit = index.unitOf(filePath);
  if (unit == null) return null;
  final changedPaths = changedDart.map((f) => index.toAbsolute(f.path)).toSet();
  for (final imported in unit.imports) {
    if (changedPaths.contains(imported)) {
      return 'imports ${index.toRelative(imported)}';
    }
  }
  return null;
}