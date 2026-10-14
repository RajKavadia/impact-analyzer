/// Error codes emitted by Impact Analyzer.
///
/// These strings are part of the CLI/MCP/dashboard contract and must stay
/// stable across versions.
class ImpactErrorCodes {
  const ImpactErrorCodes._();

  static const String notGitRepo = 'not_git_repo';
  static const String notDartProject = 'not_dart_project';
  static const String analyzerFailed = 'analyzer_failed';
  static const String invalidPlan = 'invalid_plan';
  static const String gitFailed = 'git_failed';
  static const String notFound = 'not_found';
}

/// Structured error shared by all surfaces (CLI, MCP, dashboard).
class ImpactError implements Exception {
  ImpactError(this.code, this.message, {this.details = const <String, Object?>{}});

  final String code;
  final String message;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'message': message,
        'details': details,
      };

  @override
  String toString() => 'ImpactError($code): $message';
}
