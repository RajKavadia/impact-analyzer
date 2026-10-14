import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:impact_analyzer/impact_analyzer.dart';

Future<void> _write(String dir, String relative, String content) async {
  final file = File(p.join(dir, p.joinAll(relative.split('/'))));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

void main() {
  group('PlanExtractor', () {
    late Directory temp;
    late String root;
    late DartSymbolIndex index;
    late PlanExtractor extractor;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('impact_plan_');
      root = temp.path;
      await _write(root, 'pubspec.yaml', 'name: sample\nenvironment:\n  sdk: ^3.13.0\n');
      await _write(root, 'lib/token_service.dart', '''
class TokenService {
  Future<String> refreshToken() async => 'token';
}
''');
      await _write(root, 'lib/repository.dart', '''
import 'token_service.dart';

class Repository {
  final TokenService service = TokenService();
}
''');
      index = await DartSymbolIndex.build(
        repoRoot: root,
        ignoreRules: IgnoreRules.fromRepository(root),
      );
      extractor = PlanExtractor(index);
    });

    tearDown(() => temp.delete(recursive: true));

    test('structured plans yield file candidates', () {
      final plan = extractor.fromStructured({
        'title': 'Refactor auth',
        'steps': [
          {
            'description': 'Extract refresh logic',
            'files': ['lib/token_service.dart', 'lib/repository.dart'],
            'symbols': ['TokenService'],
          },
        ],
      });

      expect(plan.kind, PlanExtractionKind.structured);
      expect(plan.files.map((f) => f.path).toList(), [
        'lib/repository.dart',
        'lib/token_service.dart',
      ]);
      expect(plan.files.every((f) => f.exists), isTrue);
      expect(plan.notes, isEmpty);
    });

    test('structured plan with missing files is flagged, not rejected', () {
      final plan = extractor.fromStructured({
        'steps': [
          {'files': ['lib/token_service.dart', 'lib/does_not_exist.dart']},
        ],
      });
      expect(plan.files, hasLength(2));
      expect(plan.notes.any((n) => n.contains('lib/does_not_exist.dart')), isTrue);
    });

    test('rejects plans without steps or files', () {
      expect(
        () => extractor.fromStructured('not a map'),
        throwsA(isA<ImpactError>().having(
          (e) => e.code,
          'code',
          ImpactErrorCodes.invalidPlan,
        )),
      );
      expect(
        () => extractor.fromStructured({'title': 'x'}),
        throwsA(isA<ImpactError>()),
      );
      expect(
        () => extractor.fromStructured({'steps': [<String>[]]}),
        throwsA(isA<ImpactError>()),
      );
      expect(
        () => extractor.fromStructured({
          'steps': [
            {'files': [42]}
          ],
        }),
        throwsA(isA<ImpactError>()),
      );
    });

    test('markdown plans extract .dart paths', () {
      final plan = extractor.fromMarkdown('''
# Plan

Touch `lib/token_service.dart` and update `lib/repository.dart`.
''');
      expect(plan.kind, PlanExtractionKind.freeText);
      expect(plan.files.map((f) => f.path).toList(), [
        'lib/repository.dart',
        'lib/token_service.dart',
      ]);
    });

    test('backticked identifiers resolve to declaring files', () {
      final plan = extractor.fromMarkdown('Update `TokenService` behaviour.');
      expect(plan.files.map((f) => f.path), contains('lib/token_service.dart'));
      expect(plan.unmatchedSymbols, isEmpty);
    });

    test('unknown identifiers are reported as unmatched', () {
      final plan = extractor.fromMarkdown(
        'Update `lib/token_service.dart` to fix `NotAThing`.',
      );
      expect(plan.files.map((f) => f.path), ['lib/token_service.dart']);
      expect(plan.unmatchedSymbols, ['NotAThing']);
      expect(plan.notes.any((n) => n.contains('NotAThing')), isTrue);
    });

    test('a plan with only unknown identifiers yields no candidates', () {
      expect(
        () => extractor.fromMarkdown('Refactor `NotAThing` now.'),
        throwsA(isA<ImpactError>()),
      );
    });

    test('markdown without candidates is invalid', () {
      expect(
        () => extractor.fromMarkdown('Just prose, no code references.'),
        throwsA(isA<ImpactError>().having(
          (e) => e.code,
          'code',
          ImpactErrorCodes.invalidPlan,
        )),
      );
    });

    test('windows-style separators are normalized', () {
      final plan = extractor.fromStructured({
        'steps': [
          {'files': ['lib\\token_service.dart']},
        ],
      });
      expect(plan.files.single.path, 'lib/token_service.dart');
    });
  });
}