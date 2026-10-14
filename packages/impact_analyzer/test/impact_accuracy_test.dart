import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:impact_analyzer/impact_analyzer.dart';

Future<void> _write(String dir, String relative, String content) async {
  final file = File(p.join(dir, p.joinAll(relative.split('/'))));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

Future<String> _makePackage(String dir, Map<String, String> files) async {
  await _write(dir, 'pubspec.yaml', '''
name: sample
publish_to: none
environment:
  sdk: ^3.13.0
''');
  for (final entry in files.entries) {
    await _write(dir, entry.key, entry.value);
  }
  final result = await Process.run('dart', ['pub', 'get'], workingDirectory: dir);
  if (result.exitCode != 0) {
    fail('dart pub get failed: ${result.stderr}');
  }
  return dir;
}

Future<ImpactAnalysis> _analyze(String root, List<String> changedPaths) async {
  final index = await DartSymbolIndex.build(
    repoRoot: root,
    ignoreRules: IgnoreRules.fromRepository(root),
  );
  return ImpactGraphBuilder(
    index: index,
    config: ImpactConfig.defaults(),
  ).build([
    for (final path in changedPaths)
      ChangedFile(path: path, status: ChangeStatus.modified),
  ]);
}

Future<void> runGit(String root, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: root);
  expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
}

void main() {
  group('path helpers', () {
    late String root;
    late DartSymbolIndex index;

    setUp(() async {
      final temp = await Directory.systemTemp.createTemp('impact_paths_');
      addTearDown(() => temp.delete(recursive: true));
      root = await _makePackage(temp.path, {
        'lib/a.dart': 'class A {}',
        'lib/nested/b.dart': 'class B {}',
      });
      index = await DartSymbolIndex.build(
        repoRoot: root,
        ignoreRules: IgnoreRules.fromRepository(root),
      );
    });

    test('toAbsolute accepts repo-relative paths', () {
      final absolute = index.toAbsolute('lib/a.dart');
      expect(absolute, contains('lib/a.dart'));
      expect(index.unitsByPath.keys, contains(absolute));
    });

    test('toAbsolute does not re-join an already absolute path', () {
      // Regression: this used to produce `<root>/<root>/lib/a.dart`.
      final once = index.toAbsolute('lib/a.dart');
      final twice = index.toAbsolute(once);
      expect(twice, once);
    });

    test('toRelative round-trips', () {
      expect(index.toRelative(index.toAbsolute('lib/nested/b.dart')), 'lib/nested/b.dart');
    });

    test('toRelative accepts a relative path without corrupting it', () {
      expect(index.toRelative('lib/a.dart'), 'lib/a.dart');
    });

    test('unitOf finds units for relative and absolute paths alike', () {
      // Regression: relative input used to resolve against the process CWD.
      expect(index.unitOf('lib/a.dart'), isNotNull);
      expect(index.unitOf(index.toAbsolute('lib/a.dart')), isNotNull);
      expect(index.unitOf('lib/missing.dart'), isNull);
    });

    test('isPublicApiSymbol only accepts public lib/ API', () {
      DeclaredSymbol make(String file, String name) =>
          DeclaredSymbol(file: file, name: name, kind: SymbolKind.classType);
      expect(index.isPublicApiSymbol(make(index.toAbsolute('lib/a.dart'), 'A')), isTrue);
      expect(index.isPublicApiSymbol(make(index.toAbsolute('lib/src/a.dart'), 'A')), isFalse);
      expect(index.isPublicApiSymbol(make(index.toAbsolute('lib/a.dart'), '_A')), isFalse);
      expect(index.isPublicApiSymbol(make(index.toAbsolute('bin/a.dart'), 'A')), isFalse);
    });
  });

  group('reference-precise impact', () {
    test('only types that reference the change count as impacted', () async {
      final temp = await Directory.systemTemp.createTemp('impact_precise_');
      addTearDown(() => temp.delete(recursive: true));
      final root = await _makePackage(temp.path, {
        'lib/user.dart': '''
class User {
  final String name;
  User(this.name);
}
''',
        'lib/consumers.dart': '''
import 'user.dart';

/// Uses the changed type.
class UsesUser {
  final User user = User('ada');
}

/// Does not touch User at all.
class Unrelated {
  int value = 1;
}

/// Also does not touch User.
class AlsoUnrelated {
  String label = 'x';
}
''',
      });

      final analysis = await _analyze(root, ['lib/user.dart']);

      final impactedNames = analysis.impactedFiles
          .firstWhere((f) => f.path == 'lib/consumers.dart')
          .impactedSymbols;
      expect(impactedNames, ['UsesUser']);
      // 1 changed type (User) + 1 genuinely impacted type.
      expect(analysis.metrics.impactedClassCount, 2);
    });

    test('a file that only imports without using does not inflate counts', () async {
      final temp = await Directory.systemTemp.createTemp('impact_import_');
      addTearDown(() => temp.delete(recursive: true));
      final root = await _makePackage(temp.path, {
        'lib/user.dart': 'class User {}\n',
        'lib/unused.dart': '''
import 'user.dart';

class NeverTouchesIt {
  int a = 1;
}
''',
      });

      final analysis = await _analyze(root, ['lib/user.dart']);
      final consumer = analysis.impactedFiles
          .firstWhere((f) => f.path == 'lib/unused.dart');
      // Import-level dependency is still reported...
      expect(consumer.relation, ImpactRelation.direct);
      expect(consumer.reason, contains('imports'));
      // ...but it must not be counted as an impacted class.
      expect(analysis.metrics.impactedClassCount, 1);
    });
  });

  group('part files', () {
    test('a change inside a part expands through its library', () async {
      final temp = await Directory.systemTemp.createTemp('impact_part_');
      addTearDown(() => temp.delete(recursive: true));
      final root = await _makePackage(temp.path, {
        'lib/thing.dart': '''
library thing;

part 'thing_part.dart';
''',
        'lib/thing_part.dart': '''
part of 'thing.dart';

class FromPart {
  int value = 1;
}
''',
        'lib/consumer.dart': '''
import 'thing.dart';

class Consumer {
  final FromPart part = FromPart();
}
''',
      });

      final analysis = await _analyze(root, ['lib/thing_part.dart']);
      expect(
        analysis.impactedFiles.map((f) => f.path),
        contains('lib/consumer.dart'),
      );
    });
  });

  group('symbol list hygiene', () {
    test('field/getter/setter collapse to a single symbol entry', () async {
      final temp = await Directory.systemTemp.createTemp('impact_dupe_');
      addTearDown(() => temp.delete(recursive: true));
      final root = await _makePackage(temp.path, {
        'lib/counter.dart': '''
class Counter {
  int value = 0;
  int get doubled => value * 2;
  set doubled(int v) => value = v ~/ 2;
  void bump() => value++;
}
''',
      });

      final index = await DartSymbolIndex.build(
        repoRoot: root,
        ignoreRules: IgnoreRules.fromRepository(root),
      );
      final names = index.unitOf('lib/counter.dart')!.declarations
          .map((s) => s.name)
          .toList();

      // Regression: the element model yields field+getter+setter separately.
      expect(names.where((n) => n == 'doubled').length, 1);
      expect(names.where((n) => n == 'value').length, 1);
      expect(names.toSet().length, names.length, reason: 'no duplicate symbol names');
    });
  });

  group('plan symbol scoping', () {
    late Directory temp;
    late String root;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('impact_scope_');
      root = await _makePackage(temp.path, {
        'pubspec.yaml': 'name: sample\npublish_to: none\nenvironment:\n  sdk: ^3.13.0\n',
      });
    });

    tearDown(() => temp.delete(recursive: true));

    test('naming a single symbol narrows the changed symbol set', () async {
      await _makePackage(root, {
        'lib/tokens.dart': '''
class TokenService {
  Future<String> refreshToken() async => 'fresh';
  Future<String> revokeToken() async => 'gone';
}

class UnrelatedService {
  int value = 1;
}
''',
        'lib/refresh_user.dart': '''
import 'tokens.dart';

class RefreshUser {
  Future<String> run() => TokenService().refreshToken();
}
''',
        'lib/revoke_user.dart': '''
import 'tokens.dart';

class RevokeUser {
  Future<String> run() => TokenService().revokeToken();
}
''',
      });
      await runGit(root, ['init', '-q']);
      await runGit(root, ['config', 'user.email', 't@t.co']);
      await runGit(root, ['config', 'user.name', 't']);
      await runGit(root, ['add', '-A']);
      await runGit(root, ['commit', '-qm', 'init']);
final orchestrator = ImpactOrchestrator(rootPath: root);

      final scoped = await orchestrator.analyzePlan(planJson: {
        'steps': [
          {
            'files': ['lib/tokens.dart'],
            'symbols': ['TokenService.refreshToken'],
          },
        ],
      });

      // The named symbol is the only one reported as changed...
      final changed = scoped.changedFiles.firstWhere(
        (f) => f.path == 'lib/tokens.dart',
      );
      expect(changed.symbols, ['refreshToken']);

      // ...so the sibling that only calls revokeToken is not credited with a
      // reference to the changed symbol.
      final revoke = scoped.impactedFiles
          .firstWhere((f) => f.path == 'lib/revoke_user.dart');
      expect(revoke.reason, isNot(contains('refreshToken')));
      expect(changed.symbols, isNot(contains('revokeToken')));

      // Without a symbol list the whole file is treated as changed, and the
      // sibling then shows up as a genuine symbol-level dependent.
      final whole = await orchestrator.analyzePlan(planJson: {
        'steps': [
          {'files': ['lib/tokens.dart']},
        ],
      });
      final wholeChanged = whole.changedFiles.firstWhere(
        (f) => f.path == 'lib/tokens.dart',
      );
      expect(wholeChanged.symbols, contains('TokenService'));
      expect(wholeChanged.symbols, contains('revokeToken'));

      final revokeWhole = whole.impactedFiles
          .firstWhere((f) => f.path == 'lib/revoke_user.dart');
      expect(revokeWhole.reason, contains('revokeToken'));
    });
  });

  group('extension members', () {
    test('extension methods are indexed so their references match', () async {
      final temp = await Directory.systemTemp.createTemp('impact_ext_');
      addTearDown(() => temp.delete(recursive: true));
      final root = await _makePackage(temp.path, {
        'lib/strings.dart': '''
extension StringX on String {
  int get doubledLength => length * 2;
}
''',
        'lib/use.dart': '''
import 'strings.dart';

class Uses {
  int measure(String s) => s.doubledLength;
}
''',
      });

      final index = await DartSymbolIndex.build(
        repoRoot: root,
        ignoreRules: IgnoreRules.fromRepository(root),
      );
      final memberKeys = index.symbolsByKey.keys
          .where((k) => k.contains('doubledLength'))
          .toList();
      expect(memberKeys, isNotEmpty, reason: 'extension getter must be indexed');

      final analysis = ImpactGraphBuilder(
        index: index,
        config: ImpactConfig.defaults(),
      ).build([
        const ChangedFile(path: 'lib/strings.dart', status: ChangeStatus.modified),
      ]);
      final use = analysis.impactedFiles.firstWhere((f) => f.path == 'lib/use.dart');
      expect(use.reason, contains('doubledLength'));
    });
  });
}