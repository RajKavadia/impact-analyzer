import 'dart:convert';
import 'dart:io';

import 'package:impact_analyzer_dashboard/impact_analyzer_dashboard.dart';
import 'impact_report_fixture.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Boots a dashboard server against a throwaway Dart git repo.
///
/// Binds an ephemeral port so tests never collide.
Future<_Harness> _start() async {
  final temp = await Directory.systemTemp.createTemp('impact_dash_');
  final root = temp.path;

  Future<void> write(String rel, String content) async {
    final f = File(p.join(root, p.joinAll(rel.split('/'))));
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  await write('pubspec.yaml', '''
name: dash_sample
publish_to: none
environment:
  sdk: ^3.13.0
''');
  await write('lib/token_service.dart', '''
class TokenService {
  Future<String> refreshToken() async => 'fresh';
}
''');
  await write('lib/repository.dart', '''
import 'token_service.dart';

class Repository {
  Future<String> load() => TokenService().refreshToken();
}
''');
  await write('test/repository_test.dart', '''
import 'repository.dart';

void main() {
  test('loads', () async {
    await Repository().load();
  });
}
''');

  final pubGet = await Process.run('dart', ['pub', 'get'], workingDirectory: root);
  expect(pubGet.exitCode, 0, reason: 'pub get failed: ${pubGet.stderr}');

  for (final args in [
    ['init', '-q'],
    ['config', 'user.email', 't@t.co'],
    ['config', 'user.name', 't'],
    ['add', '-A'],
    ['commit', '-qm', 'init'],
  ]) {
    final r = await Process.run('git', args, workingDirectory: root);
    expect(r.exitCode, 0, reason: 'git $args failed: ${r.stderr}');
  }

  // Leave a working-tree edit so reports are non-empty.
  await write('lib/token_service.dart', '''
class TokenService {
  int refreshes = 0;
  Future<String> refreshToken() async => 'fresh\${refreshes++}';
}
''');

  final server = DashboardServer(rootPath: root, port: 0);
  final handle = await server.start();

  return _Harness(handle, root, temp);
}

class _Harness {
  _Harness(this.handle, this.root, this.temp);

  final HttpServer handle;
  final String root;
  final Directory temp;

  String get base => 'http://127.0.0.1:${handle.port}';

  Future<(int, Map<String, dynamic>)> get(String path) async {
    final r = await HttpClient().getUrl(Uri.parse('$base$path'));
    final resp = await r.close();
    final body = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, jsonDecode(body) as Map<String, dynamic>);
  }

  Future<(int, Map<String, dynamic>)> post(String path, Object? payload) async {
    final client = HttpClient();
    final r = await client.postUrl(Uri.parse('$base$path'));
    r.headers.contentType = ContentType.json;
    r.write(jsonEncode(payload));
    final resp = await r.close();
    final body = await resp.transform(utf8.decoder).join();
    client.close();
    return (resp.statusCode, jsonDecode(body) as Map<String, dynamic>);
  }

  Future<void> stop() async {
    await handle.close(force: true);
    await temp.delete(recursive: true);
  }
}

void main() {
  late _Harness h;

  setUp(() async => h = await _start());
  tearDown(() async => h.stop());

  group('dashboard API', () {
    test('GET /api/health reports status', () async {
      final (status, body) = await h.get('/api/health');
      expect(status, 200);
      expect(body['status'], 'ok');
      expect(body['version'], '1');
      expect(body['rootPath'], h.root);
    });

    test('GET /api/impact/working-tree returns a full report', () async {
      final (status, body) = await h.get('/api/impact/working-tree');
      expect(status, 200);
      expect(body['version'], '1');
      expect(body['mode'], 'working_tree');
      final metrics = body['metrics'] as Map<String, dynamic>;
      expect(metrics['changedFileCount'], 1);
      expect(metrics['impactedFileCount'], greaterThan(0));
      expect(body['severity'], isA<Map<String, dynamic>>());
      expect((body['severity'] as Map)['band'], isA<String>());
      expect(body['git'], isA<Map<String, dynamic>>());
      expect(body['graph'], isA<Map<String, dynamic>>());
    });

    test('reports repo-relative paths only', () async {
      final (_, body) = await h.get('/api/impact/working-tree');
      final changed = body['changedFiles'] as List;
      for (final entry in changed.cast<Map<String, dynamic>>()) {
        expect(entry['path'], isNot(startsWith('/')));
        expect(entry['path'], isNot(contains(r'\')));
      }
      final impacted = body['impactedFiles'] as List;
      for (final entry in impacted.cast<Map<String, dynamic>>()) {
        expect(entry['path'], isNot(startsWith('/')));
      }
    });

    test('scope and depth params are honoured', () async {
      final (status, body) = await h.get('/api/impact/working-tree?scope=staged&depth=1');
      expect(status, 200);
      // Nothing is staged in this repo.
      expect((body['metrics'] as Map)['changedFileCount'], 0);
    });

    test('graph=false omits the graph', () async {
      final (_, body) = await h.get('/api/impact/working-tree?graph=false');
      final graph = body['graph'] as Map<String, dynamic>;
      expect(graph['nodes'], isEmpty);
      expect(graph['edges'], isEmpty);
    });

    test('GET /api/impact/summary is token-cheap', () async {
      final (status, body) = await h.get('/api/impact/summary?top=2');
      expect(status, 200);
      expect(body['severity'], isA<String>());
      expect(body['confidence'], isA<String>());
      expect(body['changedFileCount'], isA<int>());
      expect((body['topImpactedFiles'] as List).length, lessThanOrEqualTo(2));
      // The summary must not carry the full file lists.
      expect(body.containsKey('changedFiles'), isFalse);
      expect(body.containsKey('impactedFiles'), isFalse);
      expect(body.containsKey('graph'), isFalse);
    });

    test('GET /api/impact/graph caps nodes and flags truncation', () async {
      final (status, body) = await h.get('/api/impact/graph?maxNodes=1');
      expect(status, 200);
      expect((body['nodes'] as List).length, lessThanOrEqualTo(1));
      expect(body['truncated'], isA<bool>());
      expect(body['totalNodes'], isA<int>());
      expect(body['totalEdges'], isA<int>());
    });

    test('POST /api/impact/plan accepts a structured plan', () async {
      final (status, body) = await h.post('/api/impact/plan', {
        'steps': [
          {
            'files': ['lib/token_service.dart'],
            'symbols': ['TokenService.refreshToken'],
          },
        ],
      });
      expect(status, 200);
      expect(body['mode'], 'plan');
      expect((body['metrics'] as Map)['changedFileCount'], 1);
      final changed = (body['changedFiles'] as List).cast<Map<String, dynamic>>().first;
      expect(changed['symbols'], ['refreshToken']);
    });

    test('POST /api/impact/plan accepts markdown', () async {
      final (status, body) = await h.post('/api/impact/plan', {
        'planText': 'Touch `lib/token_service.dart` to refresh faster.',
      });
      expect(status, 200);
      expect(body['mode'], 'plan');
      expect((body['metrics'] as Map)['changedFileCount'], 1);
    });

    test('POST /api/impact/plan rejects an empty body', () async {
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse('${h.base}/api/impact/plan'));
      req.write('{}');
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      expect(resp.statusCode, 400);
      expect(text, contains('invalid_plan'));
      client.close();
    });

    test('errors use the structured contract', () async {
      final (status, body) = await h.get('/api/impact/range');
      expect(status, 400);
      expect(body['code'], 'invalid_request');
      expect(body['message'], contains('base'));
    });

    test('a bad base ref surfaces git_failed', () async {
      final (status, body) = await h.get('/api/impact/range?base=no-such-ref-xyz');
      expect(status, 400);
      expect(body['code'], 'git_failed');
    });

    test('GET /api/contract documents the surface for agents', () async {
      final (status, body) = await h.get('/api/contract');
      expect(status, 200);
      final endpoints = (body['endpoints'] as List).cast<Map<String, dynamic>>();
      final paths = endpoints.map((e) => '${e['method']} ${e['path']}').toList();
      expect(paths, contains('GET /api/impact/working-tree'));
      expect(paths, contains('POST /api/impact/plan'));
      expect(paths, contains('GET /api/impact/summary'));
      expect(paths, contains('GET /api/impact/graph'));
      expect(body['severityBands'], contains('critical'));
      expect(body['errorCodes'], contains('not_dart_project'));
    });

    test('static asset lookup rejects traversal', () async {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('${h.base}/../../pubspec.yaml'));
      final resp = await req.close();
      await resp.drain<void>();
      expect(resp.statusCode, anyOf(400, 404));
      client.close();
    });
  });

  group('report view projections', () {
    test('graph projection never hides truncation', () {
      final report = ImpactReportFixture.build();
      final capped = ReportView.graph(report, maxNodes: 1);
      expect(capped['truncated'], isTrue);
      expect(capped['totalNodes'], greaterThan(1));
    });

    test('summary carries severity and rationale but not file lists', () {
      final report = ImpactReportFixture.build();
      final summary = ReportView.summary(report);
      expect(summary['severity'], 'high');
      expect(summary['rationale'], isA<List>());
      expect(summary.containsKey('impactedFiles'), isFalse);
    });
  });
}