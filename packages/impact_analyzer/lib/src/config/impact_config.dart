import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/impact_report.dart';

/// Weights used by the severity formula (see docs/SEVERITY.md).
class SeverityWeights {
  const SeverityWeights({
    this.impactedFile = 1.0,
    this.impactedClass = 1.5,
    this.publicApi = 2.0,
    this.flutterUiRoot = 1.5,
    this.depth = 0.5,
    this.tests = 0.25,
  });

  final double impactedFile;
  final double impactedClass;
  final double publicApi;
  final double flutterUiRoot;
  final double depth;
  final double tests;

  double get sum =>
      impactedFile + impactedClass + publicApi + flutterUiRoot + depth + tests;

  factory SeverityWeights.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const SeverityWeights();
    double read(String key, double fallback) =>
        (map[key] as num?)?.toDouble() ?? fallback;
    return SeverityWeights(
      impactedFile: read('impactedFile', 1.0),
      impactedClass: read('impactedClass', 1.5),
      publicApi: read('publicApi', 2.0),
      flutterUiRoot: read('flutterUiRoot', 1.5),
      depth: read('depth', 0.5),
      tests: read('tests', 0.25),
    );
  }
}

/// Saturating denominators for the severity signals.
class SeverityDenominators {
  const SeverityDenominators({
    this.impactedFile = 25,
    this.impactedClass = 15,
    this.publicApi = 5,
    this.flutterUiRoot = 5,
    this.depth = 5,
    this.tests = 10,
  });

  final double impactedFile;
  final double impactedClass;
  final double publicApi;
  final double flutterUiRoot;
  final double depth;
  final double tests;

  factory SeverityDenominators.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const SeverityDenominators();
    double read(String key, double fallback) =>
        (map[key] as num?)?.toDouble() ?? fallback;
    return SeverityDenominators(
      impactedFile: read('impactedFile', 25),
      impactedClass: read('impactedClass', 15),
      publicApi: read('publicApi', 5),
      flutterUiRoot: read('flutterUiRoot', 5),
      depth: read('depth', 5),
      tests: read('tests', 10),
    );
  }
}

/// Optional `impact.yaml` configuration (see docs/SPECIFICATION.md section 10).
class ImpactConfig {
  ImpactConfig({
    this.maxDepth = 5,
    this.weights = const SeverityWeights(),
    this.denominators = const SeverityDenominators(),
    this.ignores = const <String>[],
    this.flutterRoots = const <String>[
      'Widget',
      'StatefulWidget',
      'StatelessWidget',
      'State',
    ],
    this.failOnSeverity,
  });

  final int maxDepth;
  final SeverityWeights weights;
  final SeverityDenominators denominators;
  final List<String> ignores;
  final List<String> flutterRoots;
  final SeverityBand? failOnSeverity;

  static const String fileName = 'impact.yaml';

  /// Defaults when no `impact.yaml` exists.
  factory ImpactConfig.defaults() => ImpactConfig();

  /// Loads `impact.yaml` from [repoRoot]; unknown keys are ignored.
  factory ImpactConfig.load(String repoRoot) {
    final file = File(p.join(repoRoot, fileName));
    if (!file.existsSync()) return ImpactConfig.defaults();

    final YamlMap root;
    try {
      root = loadYaml(file.readAsStringSync()) as YamlMap;
    } on Object catch (_) {
      return ImpactConfig.defaults();
    }

    int readInt(String key, int fallback) => (root[key] as num?)?.toInt() ?? fallback;

    SeverityBand? failOn;
    final failOnRaw = root['failOnSeverity'];
    if (failOnRaw is String) {
      try {
        failOn = SeverityBand.values.firstWhere((b) => b.jsonValue == failOnRaw);
      } on StateError {
        failOn = null;
      }
    }

    final ignoresRaw = root['ignores'];
    final ignores = <String>[];
    if (ignoresRaw is List) {
      for (final entry in ignoresRaw) {
        if (entry is String) ignores.add(entry);
      }
    }

    final rootsRaw = root['flutterRoots'];
    final roots = <String>[
      'Widget',
      'StatefulWidget',
      'StatelessWidget',
      'State',
    ];
    if (rootsRaw is List) {
      roots.clear();
      for (final entry in rootsRaw) {
        if (entry is String) roots.add(entry);
      }
    }

    return ImpactConfig(
      maxDepth: readInt('maxDepth', 5),
      weights: SeverityWeights.fromMap(root['weights'] as Map?),
      denominators: SeverityDenominators.fromMap(root['denominators'] as Map?),
      ignores: ignores,
      flutterRoots: roots,
      failOnSeverity: failOn,
    );
  }
}
