import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:impact_analyzer/impact_analyzer.dart';

Future<void> _git(String dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir);
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} failed: ${result.stderr}');
  }
}

Future<void> _write(String dir, String relative, String content) async {
  final file = File(p.join(dir, p.joinAll(relative.split('/'))));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

void main() {
  group('GitDiffCollector', () {
    late Directory temp;
    late String root;
    late GitDiffCollector collector;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('impact_git_');
      root = temp.path;
      await _git(root, ['init', '-q']);
      await _git(root, ['config', 'user.email', 'test@test.com']);
      await _git(root, ['config', 'user.name', 'test']);
      await _write(root, 'lib/a.dart', 'class A {}');
      await _write(root, 'lib/b.dart', 'class B {}');
      await _write(root, 'build/generated.dart', 'class G {}');
      await _git(root, ['add', '-A']);
      await _git(root, ['commit', '-qm', 'init']);
      collector = GitDiffCollector(
        runner: GitRunner(),
        ignoreRules: IgnoreRules.fromRepository(root),
      );
    });

    tearDown(() => temp.delete(recursive: true));

    test('clean tree reports no changes', () async {
      final set = await collector.collectWorkingTree(root);
      expect(set.changedFiles, isEmpty);
      expect(set.git.isClean, isTrue);
      expect(set.git.head, isNotNull);
    });

    test('detects modified, untracked and staged files', () async {
      await _write(root, 'lib/a.dart', 'class A { int x = 1; }');
      await _write(root, 'lib/new.dart', 'class New {}');
      await _write(root, 'lib/b.dart', 'class B { int y = 2; }');
      await _git(root, ['add', 'lib/b.dart']);

      final set = await collector.collectWorkingTree(root);
      final byPath = {for (final f in set.changedFiles) f.path: f};

      expect(byPath['lib/a.dart']?.status, ChangeStatus.modified);
      // Untracked files count as added, per product decision.
      expect(byPath['lib/new.dart']?.status, ChangeStatus.added);
      expect(byPath['lib/b.dart']?.status, ChangeStatus.modified);
    });

    test('staged scope only reports staged changes', () async {
      await _write(root, 'lib/a.dart', 'class A { int x = 1; }');
      await _git(root, ['add', 'lib/a.dart']);

      final staged = await collector.collectWorkingTree(root, scope: GitChangeScope.staged);
      expect(staged.changedFiles.map((f) => f.path), ['lib/a.dart']);

      final unstaged = await collector.collectWorkingTree(root, scope: GitChangeScope.unstaged);
      expect(unstaged.changedFiles, isEmpty);
    });

    test('unstaged scope only reports unstaged tracked changes', () async {
      await _write(root, 'lib/a.dart', 'class A { int x = 1; }');
      final unstaged = await collector.collectWorkingTree(root, scope: GitChangeScope.unstaged);
      expect(unstaged.changedFiles.map((f) => f.path), ['lib/a.dart']);
    });

    test('filters ignored paths such as build output', () async {
      await _write(root, 'build/generated.dart', 'class G { int z = 3; }');
      final set = await collector.collectWorkingTree(root);
      expect(
        set.changedFiles.where((f) => f.path.startsWith('build/')),
        isEmpty,
      );
    });

    test('records renames with the previous path', () async {
      await Process.run(
        'git',
        ['mv', 'lib/a.dart', 'lib/renamed.dart'],
        workingDirectory: root,
      );
      final set = await collector.collectWorkingTree(root);
      final renamed = set.changedFiles.firstWhere(
        (f) => f.status == ChangeStatus.renamed,
      );
      expect(renamed.path, 'lib/renamed.dart');
      expect(renamed.oldPath, 'lib/a.dart');
    });

    test('commit range reports committed changes', () async {
      await _git(root, ['branch', 'main']);
      await _write(root, 'lib/a.dart', 'class A { int x = 1; }');
      await _git(root, ['add', '-A']);
      await _git(root, ['commit', '-qm', 'change']);

      final set = await collector.collectCommitRange(root, baseRef: 'main', headRef: 'HEAD');
      expect(set.changedFiles.map((f) => f.path), contains('lib/a.dart'));
      expect(set.git.isClean, isTrue);
    });

    test('detectRepoRoot resolves the toplevel', () async {
      final nested = Directory(p.join(root, 'lib'))..createSync();
      expect(
        p.equals(await collector.detectRepoRoot(nested.path), p.normalize(root)),
        isTrue,
      );
    });

    test('fails clearly outside a git repository', () async {
      final plain = await Directory.systemTemp.createTemp('impact_plain_');
      addTearDown(() => plain.delete(recursive: true));
      expect(
        () => collector.detectRepoRoot(plain.path),
        throwsA(
          isA<ImpactError>().having((e) => e.code, 'code', ImpactErrorCodes.notGitRepo),
        ),
      );
    });
  });
}