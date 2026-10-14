import 'dart:io';

import 'package:impact_analyzer_dashboard/impact_analyzer_dashboard.dart';

/// Starts the local Impact Analyzer dashboard.
///
/// ```bash
/// dart run impact_analyzer_dashboard:impact_serve --path . --port 7788
/// ```
Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final root = _normalize(options['path'] ?? Directory.current.path);

  if (!File('$root${Platform.pathSeparator}pubspec.yaml').existsSync() &&
      !_hasMemberPubspec(root)) {
    stderr.writeln('error[not_dart_project]: no pubspec.yaml found at $root');
    exit(1);
  }

  final server = DashboardServer(rootPath: root, port: int.parse(options['port'] ?? '7788'));
  HttpServer handle;
  try {
    handle = await server.start();
  } on SocketException catch (e) {
    stderr.writeln('error[bind_failed]: cannot bind ${server.host}:${server.port} - ${e.message}');
    exit(1);
  }

  stdout.writeln('Impact Analyzer dashboard');
  stdout.writeln('  repo : $root');
  stdout.writeln('  url  : http://${handle.address.host}:${handle.port}');
  stdout.writeln('  api  : http://${handle.address.host}:${handle.port}/api/contract');
  stdout.writeln('');
  stdout.writeln('Loopback only. Press Ctrl+C to stop.');

  // Keep serving until interrupted.
  await ProcessSignal.sigint.watch().first;
  stdout.writeln('\nshutting down...');
  await handle.close(force: true);
}

String _normalize(String path) => path.replaceAll('/', Platform.pathSeparator);

Map<String, String> _parseArgs(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--path' || arg == '-p') {
      if (i + 1 < args.length) result['path'] = args[++i];
    } else if (arg == '--port' || arg == '-P') {
      if (i + 1 < args.length) result['port'] = args[++i];
    } else if (arg.startsWith('--path=')) {
      result['path'] = arg.substring('--path='.length);
    } else if (arg.startsWith('--port=')) {
      result['port'] = arg.substring('--port='.length);
    }
  }
  return result;
}

bool _hasMemberPubspec(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return false;
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is Directory && File('${entity.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
      return true;
    }
  }
  return false;
}