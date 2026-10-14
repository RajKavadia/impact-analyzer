import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:impact_analyzer/impact_analyzer.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'report_view.dart';

/// Local dashboard server for Impact Analyzer.
///
/// Binds to loopback by default and never makes outbound network calls: the UI
/// is fully static and the graph library is vendored.
class DashboardServer {
  DashboardServer({
    required this.rootPath,
    this.host = '127.0.0.1',
    this.port = 7788,
    this.assetsPath,
  });

  /// Repository analyzed by the dashboard.
  final String rootPath;

  /// Loopback by default; override only when you understand the exposure.
  final String host;
  final int port;

  /// Directory containing the static UI. Defaults to the package's `web/`.
  final String? assetsPath;

  late final ImpactOrchestrator _orchestrator = ImpactOrchestrator(
    rootPath: rootPath,
    config: ImpactConfig.load(rootPath),
  );

  /// Cached report so repeated UI polls do not re-resolve the analyzer.
  ImpactReport? _cached;
  String? _cachedKey;

  /// Resolved once on first use, then reused.
  Future<String>? _webRootFuture;

  Future<HttpServer> start() => shelf_io.serve(handler, host, port);

  /// The composed request handler.
  ///
  /// Exposed so tests (and embedders) can drive the API without binding a port.
  Handler get handler => const Pipeline()
      .addMiddleware(_jsonErrorMiddleware())
      .addHandler(_router);

  Future<String> _webRoot() =>
      _webRootFuture ??= (assetsPath != null
          ? Future<String>.value(assetsPath!)
          : _resolveWebRoot());

  /// Overrides the asset directory (tests, embedders).
  set webRoot(String? value) => _webRootOverride = value;

  String? _webRootOverride;

/// Locates the bundled `web/` directory.
///
/// Resolution is anchored to this package rather than to the entrypoint script,
/// so the UI is found whether the server is started from the CLI, from this
/// package's own executable, or from a test harness.
///
/// Runs once at startup because `Isolate.resolvePackageUri` is async.
Future<String> _resolveWebRoot() async {
  final override = _webRootOverride;
  if (override != null) return override;

  // `lib/src/server.dart` -> package root -> `web/`
  final self = await Isolate.resolvePackageUri(
    Uri.parse('package:impact_analyzer_dashboard/src/server.dart'),
  );
  if (self != null) {
    final candidate =
        p.normalize(p.join(p.dirname(p.fromUri(self)), '..', '..', 'web'));
    if (Directory(candidate).existsSync()) return candidate;
  }

  // Fallbacks for unusual launch layouts.
  final besideScript = p.join(p.dirname(Platform.script.toFilePath()), 'web');
  if (Directory(besideScript).existsSync()) return besideScript;

  final cwd = p.join(Directory.current.path, 'web');
  if (Directory(cwd).existsSync()) return cwd;

  // Nothing found: return the package-relative guess so the 404 message can
  // point at the expected location.
  return self == null
      ? besideScript
      : p.normalize(p.join(p.dirname(p.fromUri(self)), '..', '..', 'web'));
}

  Handler get _router => (Request request) {
        // `request.url.path` has no leading slash, so normalize before matching.
        var path = request.url.path;
        if (path.isEmpty) path = '/';
        if (!path.startsWith('/')) path = '/$path';

        if (path == '/api/health') return _health();
        if (path == '/api/impact/working-tree') return _workingTree(request);
        if (path == '/api/impact/range') return _range(request);
        if (path == '/api/impact/plan') return _plan(request);
        if (path == '/api/impact/summary') return _summary(request);
        if (path == '/api/impact/graph') return _graph(request);
        if (path == '/api/contract') return _contract();
        return _static(request);
      };

  // ---------------------------------------------------------------- API

  Response _health() => _json(<String, Object?>{
        'status': 'ok',
        'rootPath': rootPath,
        'version': kReportVersion,
      });

  Future<Response> _workingTree(Request request) async {
    final scope = request.url.queryParameters['scope'] ?? 'all';
    final depth = _intParam(request, 'depth');
    final includeTests = request.url.queryParameters['tests'] != 'false';
    final includeGraph = request.url.queryParameters['graph'] != 'false';

    try {
      final report = await _run(
        () => _orchestrator.analyzeWorkingTree(
          scope: GitChangeScope.fromJson(scope),
          includeTests: includeTests,
          maxDepth: depth,
        ),
        key: 'wt:$scope:$depth:$includeTests',
      );
      return _json(_maybeTrimGraph(report, includeGraph));
    } on ImpactError catch (e) {
      return _error(e);
    } on Object catch (e) {
      return _error(ImpactError(ImpactErrorCodes.analyzerFailed, '$e'));
    }
  }

  Future<Response> _range(Request request) async {
    final base = request.url.queryParameters['base'];
    final head = request.url.queryParameters['head'] ?? 'HEAD';
    if (base == null || base.isEmpty) {
      return _json(
        ReportView.error('invalid_request', 'query parameter "base" is required'),
        status: 400,
      );
    }
    final depth = _intParam(request, 'depth');
    final includeTests = request.url.queryParameters['tests'] != 'false';
    final includeGraph = request.url.queryParameters['graph'] != 'false';

    try {
      final report = await _run(
        () => _orchestrator.analyzeCommitRange(
          baseRef: base,
          headRef: head,
          includeTests: includeTests,
          maxDepth: depth,
        ),
        key: 'range:$base:$head:$depth:$includeTests',
      );
      return _json(_maybeTrimGraph(report, includeGraph));
    } on ImpactError catch (e) {
      return _error(e);
    } on Object catch (e) {
      return _error(ImpactError(ImpactErrorCodes.gitFailed, '$e'));
    }
  }

  Future<Response> _plan(Request request) async {
    String? planText;
    Object? planJson;
    var cacheKey = '';

    try {
      final body = await request.readAsString();
      cacheKey = body;
      if (body.trim().isEmpty) {
        return _json(ReportView.error('invalid_plan', 'request body is empty'));
      }
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded.containsKey('steps')) {
        planJson = decoded;
      } else if (decoded is Map && (decoded.containsKey('planText') || decoded.containsKey('text'))) {
        planText = (decoded['planText'] ?? decoded['text']) as String?;
      } else if (decoded is String) {
        planText = decoded;
      } else {
        planJson = decoded;
      }
    } on FormatException catch (e) {
      return _json(ReportView.error('invalid_plan', 'malformed JSON body: ${e.message}'));
    }

    final includeGraph = request.url.queryParameters['graph'] != 'false';

    try {
      final report = await _run(
        () => _orchestrator.analyzePlan(
          planText: planText,
          planJson: planJson,
          maxDepth: _intParam(request, 'depth'),
        ),
        key: 'plan:$cacheKey',
      );
      return _json(_maybeTrimGraph(report, includeGraph));
    } on ImpactError catch (e) {
      return _error(e);
    } on Object catch (e) {
      return _error(ImpactError(ImpactErrorCodes.analyzerFailed, '$e'));
    }
  }

  /// Token-cheap view for agents polling the dashboard.
  Future<Response> _summary(Request request) async {
    final top = _intParam(request, 'top') ?? 5;
    try {
      final report = await _run(
        () => _orchestrator.analyzeWorkingTree(),
        key: 'summary',
      );
      return _json(ReportView.summary(report, topFiles: top));
    } on ImpactError catch (e) {
      return _error(e);
    } on Object catch (e) {
      return _error(ImpactError(ImpactErrorCodes.analyzerFailed, '$e'));
    }
  }

  Future<Response> _graph(Request request) async {
    final maxNodes = _intParam(request, 'maxNodes');
    try {
      final report = await _run(() => _orchestrator.analyzeWorkingTree(), key: 'graph');
      return _json(ReportView.graph(report, maxNodes: maxNodes));
    } on ImpactError catch (e) {
      return _error(e);
    } on Object catch (e) {
      return _error(ImpactError(ImpactErrorCodes.analyzerFailed, '$e'));
    }
  }

  /// Self-describing API contract so an agent can discover the surface.
  Response _contract() => _json(<String, Object?>{
        'name': 'impact-analyzer-dashboard',
        'description':
            'Read-only HTTP API for Dart/Flutter change impact analysis. '
                'Every endpoint returns JSON. Errors use '
                '{code, message, details}.',
        'endpoints': <Map<String, Object?>>[
          _ep('GET', '/api/health', 'Liveness probe.'),
          _ep('GET', '/api/impact/working-tree',
              'Impact report for uncommitted changes.',
              params: <String, String>{
                'scope': 'all | staged | unstaged (default all)',
                'depth': 'max transitive hops (default 5)',
                'tests': 'false to exclude test files (default true)',
                'graph': 'false to omit the graph (default true)',
              }),
          _ep('GET', '/api/impact/range', 'Impact report for a commit range.',
              params: <String, String>{
                'base': 'required base ref, e.g. main',
                'head': 'head ref (default HEAD)',
                'depth': 'max transitive hops',
              }),
          _ep('POST', '/api/impact/plan',
              'Impact report for a proposed plan, before edits are applied. '
                  'Body is either {"steps":[{"files":[...],"symbols":[...]}]}, '
                  '{"planText":"markdown"}, or a bare JSON string.',
              hasBody: true),
          _ep('GET', '/api/impact/summary',
              'Token-cheap counts and severity for frequent polling.',
              params: <String, String>{'top': 'how many impacted files to list (default 5)'}),
          _ep('GET', '/api/impact/graph', 'Graph only, with an optional node cap.',
              params: <String, String>{
                'maxNodes': 'cap nodes; response reports truncated + totals'
              }),
          _ep('GET', '/api/contract', 'This document.'),
        ],
        'severityBands': <String>['low', 'medium', 'high', 'critical'],
        'confidenceBands': <String>['low', 'medium', 'high'],
        'errorCodes': <String>[
          ImpactErrorCodes.notGitRepo,
          ImpactErrorCodes.notDartProject,
          ImpactErrorCodes.analyzerFailed,
          ImpactErrorCodes.invalidPlan,
          ImpactErrorCodes.gitFailed,
          ImpactErrorCodes.notFound,
          'invalid_request',
        ],
      });

  static Map<String, Object?> _ep(
    String method,
    String path,
    String description, {
    Map<String, String> params = const <String, String>{},
    bool hasBody = false,
  }) =>
      <String, Object?>{
        'method': method,
        'path': path,
        'description': description,
        'queryParams': ?(params.isEmpty ? null : params),
        if (hasBody) 'hasBody': true,
      };

  // ------------------------------------------------------------- helpers

  Future<ImpactReport> _run(Future<ImpactReport> Function() task, {required String key}) async {
    if (_cached != null && _cachedKey == key) return _cached!;
    final report = await task();
    _cached = report;
    _cachedKey = key;
    return report;
  }

  Map<String, Object?> _maybeTrimGraph(ImpactReport report, bool includeGraph) {
    if (includeGraph) return ReportView.full(report);
    return ReportView.full(report.withoutGraph());
  }

  int? _intParam(Request request, String name) {
    final raw = request.url.queryParameters[name];
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  Response _json(Object? payload, {int status = 200}) => Response(
        status,
        body: ReportView.encode(payload),
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
        },
      );

  Response _error(ImpactError error, {int status = 400}) =>
      _json(error.toJson(), status: status);

  // --------------------------------------------------------------- static

  Future<Response> _static(Request request) async {
    var relative = request.url.path;
    if (relative == '/' || relative.isEmpty) relative = '/index.html';

    // Contain path traversal: the resolved path must stay under the web root.
    final root = p.normalize(p.absolute(await _webRoot()));
    final target = p.normalize(p.join(root, p.joinAll(relative.split('/'))));
    if (!p.isWithin(root, target) && target != root) {
      return _json(ReportView.error('not_found', 'no such asset: $relative'), status: 404);
    }

    final file = File(target);
    if (!file.existsSync()) {
      return _json(
        ReportView.error(
          ImpactErrorCodes.notFound,
          'no such asset: $relative. Is the dashboard "web/" directory present?',
        ),
        status: 404,
      );
    }

    final contentType = lookupMimeType(target) ?? 'application/octet-stream';
    return Response.ok(
      file.openRead(),
      headers: <String, String>{
        'content-type': contentType,
        'cache-control': 'no-store',
      },
    );
  }

  /// Converts an unhandled throwable into the structured error contract.
  Middleware _jsonErrorMiddleware() => (innerHandler) => (request) async {
        try {
          return await innerHandler(request);
        } on ImpactError catch (e) {
          return _error(e);
        } on Object catch (e) {
          return _error(ImpactError('internal_error', '$e'), status: 500);
        }
      };
}