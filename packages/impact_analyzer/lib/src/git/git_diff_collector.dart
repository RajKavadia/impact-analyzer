import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/impact_error.dart';
import '../ignore/ignore_rules.dart';
import '../models/impact_report.dart';
import 'git_runner.dart';

/// Which slice of local changes to inspect.
enum GitChangeScope {
  all('all'),
  staged('staged'),
  unstaged('unstaged');

  const GitChangeScope(this.jsonValue);

  final String jsonValue;

  static GitChangeScope fromJson(String value) {
    for (final scope in values) {
      if (scope.jsonValue == value) return scope;
    }
    throw ArgumentError.value(value, 'value', 'Unknown GitChangeScope');
  }
}

/// Changed files plus the git header at collection time.
class GitChangeSet {
  const GitChangeSet({required this.changedFiles, required this.git});

  final List<ChangedFile> changedFiles;
  final GitInfo git;
}

/// Collects changed paths from the working tree or a commit range.
class GitDiffCollector {
  GitDiffCollector({
    required this._runner,
    required IgnoreRules ignoreRules,
  }) : _ignores = ignoreRules;

  final GitRunner _runner;
  final IgnoreRules _ignores;

  /// Resolves the repository root for [path], verifying it is a git repo.
  Future<String> detectRepoRoot(String path) async {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      throw ImpactError(
        ImpactErrorCodes.notFound,
        'path does not exist: $path',
      );
    }
    try {
      final topLevel = await _runner.runText(
        ['rev-parse', '--show-toplevel'],
        workingDirectory: path,
      );
      return p.normalize(topLevel.trim());
    } on ImpactError catch (e) {
      throw ImpactError(
        ImpactErrorCodes.notGitRepo,
        'not a git repository: $path',
        details: e.details,
      );
    }
  }

  Future<GitChangeSet> collectWorkingTree(
    String repoRoot, {
    GitChangeScope scope = GitChangeScope.all,
  }) async {
    final raw = switch (scope) {
      GitChangeScope.all => await _runner.runText(
          ['status', '--porcelain=v1', '-z', '-uall'],
          workingDirectory: repoRoot,
        ),
      GitChangeScope.staged => await _runner.runText(
          ['diff', '--cached', '--name-status', '-z', '-M'],
          workingDirectory: repoRoot,
        ),
      GitChangeScope.unstaged => await _runner.runText(
          ['diff', '--name-status', '-z', '-M'],
          workingDirectory: repoRoot,
        ),
    };

    final files = scope == GitChangeScope.all
        ? _parseStatusTokens(GitRunner.splitNul(raw))
        : _parseNameStatusTokens(GitRunner.splitNul(raw));

    return GitChangeSet(
      changedFiles: _filter(files, repoRoot),
      git: await _gitInfo(repoRoot),
    );
  }

  Future<GitChangeSet> collectCommitRange(
    String repoRoot, {
    required String baseRef,
    String headRef = 'HEAD',
  }) async {
    final raw = await _runner.runText(
      ['diff', '--name-status', '-z', '-M', '$baseRef...$headRef'],
      workingDirectory: repoRoot,
    );
    return GitChangeSet(
      changedFiles: _filter(_parseNameStatusTokens(GitRunner.splitNul(raw)), repoRoot),
      git: await _gitInfo(repoRoot),
    );
  }

  Future<GitInfo> _gitInfo(String repoRoot) async {
    String? branch;
    String? head;
    try {
      branch = (await _runner.runText(
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: repoRoot,
      ))
          .trim();
    } on ImpactError {
      branch = null;
    }
    try {
      head = (await _runner.runText(
        ['rev-parse', '--short', 'HEAD'],
        workingDirectory: repoRoot,
      ))
          .trim();
    } on ImpactError {
      head = null;
    }
    final isClean = await _isClean(repoRoot);
    return GitInfo(branch: branch, head: head, isClean: isClean);
  }

  Future<bool> _isClean(String repoRoot) async {
    final raw = await _runner.runText(
      ['status', '--porcelain=v1', '-z', '-uall'],
      workingDirectory: repoRoot,
    );
    return GitRunner.splitNul(raw).isEmpty;
  }

  List<ChangedFile> _filter(List<ChangedFile> files, String repoRoot) {
    final result = <ChangedFile>[];
    for (final file in files) {
      final absolute = p.join(repoRoot, p.split(file.path).join(p.separator));
      if (_ignores.isIgnored(absolute, repoRoot: repoRoot)) continue;
      result.add(file);
    }
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  /// Parses `git status --porcelain -z` tokens.
  ///
  /// Entry format: `XY PATH`, where rename/copy entries are followed by the
  /// NEW path token and then the OLD path token.
  List<ChangedFile> _parseStatusTokens(List<String> tokens) {
    final files = <ChangedFile>[];
    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      i += 1;
      if (token.length < 3) continue;
      final xy = token.substring(0, 2);
      final path = token.substring(3);

      String? oldPath;
      if (xy.contains('R') || xy.contains('C')) {
        if (i < tokens.length) {
          oldPath = tokens[i];
          i += 1;
        }
      }
      files.add(ChangedFile(
        path: _normalize(path),
        oldPath: oldPath == null ? null : _normalize(oldPath),
        status: _statusFromCode(_primaryCode(xy)),
      ));
    }
    return files;
  }

  /// Parses `git diff --name-status -z` tokens.
  ///
  /// Entry format: `STATUS PATH`; rename/copy entries are `STATUS OLD NEW`.
  List<ChangedFile> _parseNameStatusTokens(List<String> tokens) {
    final files = <ChangedFile>[];
    var i = 0;
    while (i < tokens.length) {
      final code = tokens[i];
      i += 1;
      if (i >= tokens.length) break;
      final first = tokens[i];
      i += 1;

      if (code.startsWith('R') || code.startsWith('C')) {
        if (i >= tokens.length) break;
        final second = tokens[i];
        i += 1;
        files.add(ChangedFile(
          path: _normalize(second),
          oldPath: _normalize(first),
          status: _statusFromCode(code[0]),
        ));
      } else {
        files.add(ChangedFile(
          path: _normalize(first),
          status: _statusFromCode(code[0]),
        ));
      }
    }
    return files;
  }

  String _primaryCode(String xy) {
    final index = xy[0];
    final worktree = xy[1];
    if (index != ' ') return index;
    return worktree == ' ' ? '?' : worktree;
  }

  ChangeStatus _statusFromCode(String code) {
    switch (code) {
      case 'A':
      case 'C':
      case '?':
        return ChangeStatus.added;
      case 'D':
        return ChangeStatus.deleted;
      case 'R':
        return ChangeStatus.renamed;
      case 'M':
      case 'T':
      case 'U':
      default:
        return ChangeStatus.modified;
    }
  }

  String _normalize(String path) => p.split(path).join('/');
}
