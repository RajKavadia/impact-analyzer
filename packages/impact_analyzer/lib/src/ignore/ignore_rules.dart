import 'dart:io';

import 'package:path/path.dart' as p;

/// A single gitignore-style pattern.
class IgnoreRule {
  IgnoreRule._(this.source, this._regex, {this.negated = false});

  final String source;
  final RegExp _regex;
  final bool negated;

  bool matches(String posixRelativePath) => _regex.hasMatch(posixRelativePath);

  factory IgnoreRule.parse(String rawLine) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      throw ArgumentError('not a rule: $rawLine');
    }
    final negated = line.startsWith('!');
    if (negated) line = line.substring(1);

    var pattern = line;
    final leadingSlash = pattern.startsWith('/');
    if (leadingSlash) pattern = pattern.substring(1);
    final dirOnly = pattern.endsWith('/');
    if (dirOnly) pattern = pattern.substring(0, pattern.length - 1);
    final midSlash = pattern.contains('/');

    final buffer = StringBuffer();
    var i = 0;
    while (i < pattern.length) {
      final ch = pattern[i];
      if (ch == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          if (i + 2 < pattern.length && pattern[i + 2] == '/') {
            buffer.write('(?:.*/)?');
            i += 3;
          } else {
            buffer.write('.*');
            i += 2;
          }
        } else {
          buffer.write(r'[^/]*');
          i += 1;
        }
      } else if (ch == '?') {
        buffer.write(r'[^/]');
        i += 1;
      } else {
        buffer.write(RegExp.escape(ch));
        i += 1;
      }
    }

    final prefix = leadingSlash || midSlash ? '^' : '(?:^|/)';
    final regex = RegExp('$prefix${buffer.toString()}(?:/.*)?\$');
    return IgnoreRule._(line, regex, negated: negated);
  }
}

/// Combined ignore matching used before any path enters analysis.
class IgnoreRules {
  IgnoreRules({List<IgnoreRule> rules = const <IgnoreRule>[]})
      : rules = List<IgnoreRule>.unmodifiable(rules);

  final List<IgnoreRule> rules;

  /// Patterns applied to every repository, even without `.impactignore`.
  static const List<String> builtInPatterns = <String>[
    '.git/',
    '.dart_tool/',
    'build/',
    '.pub/',
    '.pub-cache/',
    'ios/Pods/',
    'android/.gradle/',
    '**/*.g.dart',
    '**/*.freezed.dart',
    '**/*.mocks.dart',
    '**/*.gen.dart',
  ];

  /// Loads `.impactignore` from [repoRoot] on top of the built-in patterns.
  factory IgnoreRules.fromRepository(
    String repoRoot, {
    List<String> configIgnores = const <String>[],
  }) {
    final lines = <String>[];
    final ignoreFile = File(p.join(repoRoot, '.impactignore'));
    if (ignoreFile.existsSync()) {
      lines.addAll(ignoreFile.readAsLinesSync());
    }
    lines.addAll(configIgnores);

    final rules = <IgnoreRule>[];
    for (final pattern in [...builtInPatterns, ...lines]) {
      final trimmed = pattern.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      rules.add(IgnoreRule.parse(trimmed));
    }
    return IgnoreRules(rules: rules);
  }

  /// True when [absolutePath] (inside the repo) is ignored.
  ///
  /// Later rules win, so `.impactignore` can re-include a built-in default.
  bool isIgnored(String absolutePath, {required String repoRoot}) {
    final relative = p.relative(absolutePath, from: repoRoot);
    if (relative.startsWith('..')) return false;
    final posix = p.split(relative).join('/');
    if (posix == '.') return false;

    var ignored = false;
    for (final rule in rules) {
      if (rule.matches(posix)) {
        ignored = !rule.negated;
      }
    }
    return ignored;
  }
}
