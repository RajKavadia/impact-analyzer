import 'dart:convert';
import 'dart:io';

import '../errors/impact_error.dart';

/// Thin, structured wrapper around the `git` CLI.
///
/// Shelling out keeps behaviour identical to the user's own git and avoids a
/// pure-Dart reimplementation of index/status edge cases.
class GitRunner {
  GitRunner({this._executable = 'git'});

  final String _executable;

  /// Runs `git` and returns stdout, throwing [ImpactError] on failure.
  Future<String> runText(
    List<String> args, {
    required String workingDirectory,
  }) async {
    final result = await _run(args, workingDirectory);
    if (result.$1 != 0) {
      throw ImpactError(
        ImpactErrorCodes.gitFailed,
        'git ${args.join(' ')} exited with ${result.$1}: ${result.$2}',
        details: <String, Object?>{'args': args, 'exitCode': result.$1},
      );
    }
    return result.$3;
  }

  Future<(int, String, String)> _run(
    List<String> args,
    String workingDirectory,
  ) async {
    try {
      final process = await Process.start(
        _executable,
        ['-c', 'core.quotePath=false', ...args],
        workingDirectory: workingDirectory,
      );
      final stdout = await process.stdout.transform(utf8.decoder).join();
      final stderr = await process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      return (exitCode, stderr.trim(), stdout);
    } on ProcessException catch (e) {
      throw ImpactError(
        ImpactErrorCodes.gitFailed,
        'failed to execute git: ${e.message}',
      );
    }
  }

  static final String _nul = String.fromCharCode(0);

  /// Splits `-z` output (NUL-terminated entries) into tokens.
  static List<String> splitNul(String raw) =>
      raw.split(_nul).where((t) => t.isNotEmpty).toList();
}
