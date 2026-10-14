import 'package:impact_analyzer/impact_analyzer.dart';
import 'package:test/test.dart';

bool ignored(IgnoreRules rules, String root, String relative) {
  final absolute = relative.startsWith('/')
      ? '$root$relative'
      : '$root/${relative.replaceAll('/', '/')}';
  return rules.isIgnored(absolute, repoRoot: root);
}

void main() {
  group('IgnoreRules', () {
    const root = '/repo';

    test('ignores build and tooling directories', () {
      final rules = IgnoreRules.fromRepository(root);
      expect(ignored(rules, root, 'build/app.dart'), isTrue);
      expect(ignored(rules, root, '.dart_tool/package_config.json'), isTrue);
      expect(ignored(rules, root, '.git/config'), isTrue);
    });

    test('ignores generated files', () {
      final rules = IgnoreRules.fromRepository(root);
      expect(ignored(rules, root, 'lib/foo.g.dart'), isTrue);
      expect(ignored(rules, root, 'lib/nested/bar.freezed.dart'), isTrue);
      expect(ignored(rules, root, 'lib/keep.dart'), isFalse);
    });

    test('matches directory patterns at any depth', () {
      final rules = IgnoreRules.fromRepository(root);
      expect(ignored(rules, root, 'packages/a/build/x.dart'), isTrue);
      expect(ignored(rules, root, 'packages/a/lib/x.dart'), isFalse);
    });

    test('anchored patterns only match from the repo root', () {
      final rules = IgnoreRules(
        rules: [IgnoreRule.parse('/generated/')],
      );
      expect(ignored(rules, root, 'generated/a.dart'), isTrue);
      expect(ignored(rules, root, 'lib/generated/a.dart'), isFalse);
    });

    test('wildcards match within a single segment', () {
      final rules = IgnoreRules(rules: [IgnoreRule.parse('lib/*_mock.dart')]);
      expect(ignored(rules, root, 'lib/user_mock.dart'), isTrue);
      expect(ignored(rules, root, 'lib/user.dart'), isFalse);
    });

    test('negation re-includes a path matched by an earlier rule', () {
      final rules = IgnoreRules(
        rules: [
          IgnoreRule.parse('**/*.g.dart'),
          IgnoreRule.parse('!lib/keep.g.dart'),
        ],
      );
      expect(ignored(rules, root, 'lib/drop.g.dart'), isTrue);
      expect(ignored(rules, root, 'lib/keep.g.dart'), isFalse);
    });

    test('paths outside the repo are never ignored', () {
      final rules = IgnoreRules(rules: [IgnoreRule.parse('**')]);
      expect(rules.isIgnored('/elsewhere/file.dart', repoRoot: root), isFalse);
    });

    test('config ignores are layered on top of defaults', () {
      final rules = IgnoreRules.fromRepository(root, configIgnores: ['lib/legacy/']);
      expect(ignored(rules, root, 'lib/legacy/old.dart'), isTrue);
      expect(ignored(rules, root, 'lib/current.dart'), isFalse);
    });
  });

  group('ImpactConfig', () {
    test('defaults match the specification', () {
      final config = ImpactConfig.defaults();
      expect(config.maxDepth, 5);
      expect(config.weights.impactedFile, 1.0);
      expect(config.weights.impactedClass, 1.5);
      expect(config.weights.publicApi, 2.0);
      expect(config.weights.flutterUiRoot, 1.5);
      expect(config.weights.depth, 0.5);
      expect(config.weights.tests, 0.25);
      expect(config.flutterRoots, contains('Widget'));
      expect(config.failOnSeverity, isNull);
    });

    test('weight sum is the documented 6.75', () {
      expect(const SeverityWeights().sum, 6.75);
    });

    test('missing config file yields defaults', () {
      final config = ImpactConfig.load('/definitely/not/here');
      expect(config.maxDepth, 5);
    });
  });

  group('ImpactError', () {
    test('serializes to the documented error shape', () {
      final error = ImpactError(ImpactErrorCodes.notDartProject, 'no pubspec.yaml');
      expect(error.toJson(), {
        'code': 'not_dart_project',
        'message': 'no pubspec.yaml',
        'details': <String, Object?>{},
      });
    });
  });
}