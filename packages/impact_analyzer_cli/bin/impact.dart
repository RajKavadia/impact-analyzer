import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:impact_analyzer/impact_analyzer.dart';
import 'package:impact_analyzer_dashboard/impact_analyzer_dashboard.dart';

void main(List<String> args) async {
  final parser = _buildParser();
  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('error[usage]: ${e.message}');
    _printUsage(parser);
    exit(2);
  }

  final command = results.command?.name ?? '';
  switch (command) {
    case 'analyze':
      await _runAnalyze(results);
      break;
    case 'plan':
      await _runPlan(results);
      break;
    case 'serve':
      await _runServe(results);
      break;
    default:
      _printUsage(parser);
      exit(2);
  }
}

ArgParser _buildParser() {
  final parser = ArgParser(allowTrailingOptions: true);
  parser.addFlag('help', abbr: 'h', negatable: false, help: 'Show usage');
  parser.addFlag('version', negatable: false, help: 'Print version');

  // analyze command
  final analyzeCmd = parser.addCommand('analyze');
  analyzeCmd.addOption('path', abbr: 'p', defaultsTo: '.', help: 'Repository path');
  analyzeCmd.addOption('scope', allowed: ['all', 'staged', 'unstaged'], defaultsTo: 'all', help: 'Change scope');
  analyzeCmd.addOption('base', help: 'Base ref for commit range (e.g. main)');
  analyzeCmd.addOption('head', defaultsTo: 'HEAD', help: 'Head ref for commit range');
  analyzeCmd.addOption('depth', abbr: 'd', help: 'Max transitive depth');
  analyzeCmd.addFlag('json', negatable: false, help: 'Output JSON');
  analyzeCmd.addOption('fail-on', allowed: ['low', 'medium', 'high', 'critical'], help: 'Exit 3 if severity >= threshold');

  // plan command
  final planCmd = parser.addCommand('plan');
  planCmd.addOption('path', abbr: 'p', defaultsTo: '.', help: 'Repository path');
  planCmd.addOption('file', abbr: 'f', help: 'Plan file (markdown or JSON)');
  planCmd.addFlag('stdin', negatable: false, help: 'Read plan from stdin');
  planCmd.addOption('depth', abbr: 'd', help: 'Max transitive depth');
  planCmd.addFlag('json', negatable: false, help: 'Output JSON');
  planCmd.addOption('fail-on', allowed: ['low', 'medium', 'high', 'critical'], help: 'Exit 3 if severity >= threshold');

  // serve command (local dashboard)
  final serveCmd = parser.addCommand('serve');
  serveCmd.addOption('path', abbr: 'p', defaultsTo: '.', help: 'Repository path');
  serveCmd.addOption('port', abbr: 'P', defaultsTo: '7788', help: 'HTTP port (loopback only)');
  serveCmd.addFlag('json', negatable: false, help: 'Print startup details as JSON');

  return parser;
}

Future<void> _runAnalyze(ArgResults results) async {
  final cmd = results.command!;
  final path = cmd['path'] as String;
  final scopeStr = cmd['scope'] as String;
  final baseRef = cmd['base'] as String?;
  final headRef = cmd['head'] as String;
  final depth = cmd['depth'] != null ? int.parse(cmd['depth'] as String) : null;
  final asJson = cmd['json'] as bool;
  final failOnStr = cmd['fail-on'] as String?;

  final scope = _parseScope(scopeStr);
  final orchestrator = ImpactOrchestrator(rootPath: path);

  ImpactReport report;
  if (baseRef != null) {
    report = await orchestrator.analyzeCommitRange(
      baseRef: baseRef,
      headRef: headRef,
      maxDepth: depth,
    );
  } else {
    report = await orchestrator.analyzeWorkingTree(
      scope: scope,
      maxDepth: depth,
    );
  }

  _outputReport(report, asJson);

  if (failOnStr != null) {
    final failOn = SeverityBand.values.firstWhere((b) => b.jsonValue == failOnStr);
    if (report.severity.band.rank >= failOn.rank) {
      stderr.writeln('Severity ${report.severity.band.jsonValue} meets or exceeds threshold $failOnStr');
      exit(3);
    }
  }
}

Future<void> _runPlan(ArgResults results) async {
  final cmd = results.command!;
  final path = cmd['path'] as String;
  final file = cmd['file'] as String?;
  final fromStdin = cmd['stdin'] as bool;
  final depth = cmd['depth'] != null ? int.parse(cmd['depth'] as String) : null;
  final asJson = cmd['json'] as bool;
  final failOnStr = cmd['fail-on'] as String?;

  if (file == null && !fromStdin) {
    stderr.writeln('error[usage]: provide --file or --stdin');
    exit(2);
  }

  String planText = '';
  Object? planJson;
  if (fromStdin) {
    planText = await stdin.transform(utf8.decoder).join();
  } else {
    final content = await File(file!).readAsString();
    if (file.endsWith('.json')) {
      planJson = jsonDecode(content);
    } else {
      planText = content;
    }
  }

  final orchestrator = ImpactOrchestrator(rootPath: path);
  final report = await orchestrator.analyzePlan(
    planText: planText,
    planJson: planJson,
    maxDepth: depth,
  );

  _outputReport(report, asJson);

  if (failOnStr != null) {
    final failOn = SeverityBand.values.firstWhere((b) => b.jsonValue == failOnStr);
    if (report.severity.band.rank >= failOn.rank) {
      stderr.writeln('Severity ${report.severity.band.jsonValue} meets or exceeds threshold $failOnStr');
      exit(3);
    }
  }
}

Future<void> _runServe(ArgResults results) async {
  final cmd = results.command!;
  final port = int.parse(cmd['port'] as String);
  final path = cmd['path'] as String? ?? Directory.current.path;
  final asJson = cmd['json'] as bool;

  final server = DashboardServer(rootPath: path, port: port);
  HttpServer handle;
  try {
    handle = await server.start();
  } on SocketException catch (e) {
    stderr.writeln('error[bind_failed]: cannot bind 127.0.0.1:$port - ${e.message}');
    exit(1);
  }

  if (asJson) {
    print(jsonEncode({
      'status': 'listening',
      'host': handle.address.host,
      'port': handle.port,
      'rootPath': server.rootPath,
      'ui': 'http://${handle.address.host}:${handle.port}/',
      'api': 'http://${handle.address.host}:${handle.port}/api/contract',
    }));
  } else {
    stdout.writeln('Impact Analyzer dashboard');
    stdout.writeln('  repo : ${server.rootPath}');
    stdout.writeln('  ui   : http://${handle.address.host}:${handle.port}/');
    stdout.writeln('  api  : http://${handle.address.host}:${handle.port}/api/contract');
    stdout.writeln('');
    stdout.writeln('Loopback only. Press Ctrl+C to stop.');
  }

  await ProcessSignal.sigint.watch().first;
  await handle.close(force: true);
}

void _outputReport(ImpactReport report, bool asJson) {
  if (asJson) {
    print(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } else {
    _printHumanReadable(report);
  }
}

void _printHumanReadable(ImpactReport report) {
  final buf = StringBuffer();
  buf.writeln('Impact Analyzer Report');
  buf.writeln('======================');
  buf.writeln('');
  buf.writeln('Repository: ${report.rootPath}');
  buf.writeln('Mode: ${report.mode.jsonValue}');
  buf.writeln('Generated: ${report.generatedAt}');
  buf.writeln('Git: branch=${report.git.branch}, head=${report.git.head}, clean=${report.git.isClean}');
  buf.writeln('');

  if (report.changedFiles.isNotEmpty) {
    buf.writeln('Changed Files (${report.changedFiles.length}):');
    for (final f in report.changedFiles) {
      buf.writeln('  ${f.status.jsonValue}: ${f.path}${f.oldPath != null ? ' (was ${f.oldPath})' : ''}');
      if (f.symbols.isNotEmpty) {
        buf.writeln('    symbols: ${f.symbols.join(', ')}');
      }
    }
    buf.writeln('');
  }

  if (report.impactedFiles.isNotEmpty) {
    buf.writeln('Impacted Files (${report.impactedFiles.length}):');
    for (final f in report.impactedFiles) {
      buf.writeln('  ${f.relation.jsonValue} (depth ${f.depth}): ${f.path}');
      buf.writeln('    reason: ${f.reason}');
      if (f.impactedSymbols.isNotEmpty) {
        buf.writeln('    symbols: ${f.impactedSymbols.join(', ')}');
      }
    }
    buf.writeln('');
  }

  buf.writeln('Metrics:');
  buf.writeln('  Changed files: ${report.metrics.changedFileCount}');
  buf.writeln('  Impacted files: ${report.metrics.impactedFileCount}');
  buf.writeln('  Impacted classes: ${report.metrics.impactedClassCount}');
  buf.writeln('  Direct: ${report.metrics.directCount}');
  buf.writeln('  Transitive: ${report.metrics.transitiveCount}');
  buf.writeln('  Public API hits: ${report.metrics.publicApiHits}');
  buf.writeln('  Impacted tests: ${report.metrics.impactedTestCount}');
  buf.writeln('  Max depth: ${report.metrics.maxDepthReached}');
  buf.writeln('  Analyzed files: ${report.metrics.analyzedFileCount}');
  buf.writeln('');

  buf.writeln('Severity: ${report.severity.band.jsonValue} (score: ${report.severity.score})');
  for (final reason in report.severity.rationale) {
    buf.writeln('  - $reason');
  }
  buf.writeln('');

  buf.writeln('Confidence: ${report.confidence.band.jsonValue} (score: ${report.confidence.score})');
  for (final note in report.confidence.notes) {
    buf.writeln('  - $note');
  }

  if (report.warnings.isNotEmpty) {
    buf.writeln('');
    buf.writeln('Warnings:');
    for (final w in report.warnings) {
      buf.writeln('  - $w');
    }
  }

  print(buf.toString());
}

GitChangeScope _parseScope(String scope) {
  switch (scope) {
    case 'staged':
      return GitChangeScope.staged;
    case 'unstaged':
      return GitChangeScope.unstaged;
    default:
      return GitChangeScope.all;
  }
}

void _printUsage(ArgParser parser) {
  print('Impact Analyzer - Dart/Flutter change impact analysis');
  print('');
  print('Usage: impact <command> [options]');
  print('');
  print('Commands:');
  print('  analyze    Analyze working tree or commit range');
  print('  plan       Analyze an AI plan');
  print('  serve      Start the local dashboard (loopback only)');
  print('');
  print(parser.usage);
}