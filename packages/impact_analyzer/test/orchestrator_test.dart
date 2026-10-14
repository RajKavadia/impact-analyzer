import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:impact_analyzer/impact_analyzer.dart';

void main() {
  group('ImpactOrchestrator', () {
    late Directory tempDir;
    late String repoRoot;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('impact_test_');
      repoRoot = tempDir.path;

      // Initialize git repo
      await _runGit(repoRoot, ['init', '-q']);
      await _runGit(repoRoot, ['config', 'user.email', 'test@test.com']);
      await _runGit(repoRoot, ['config', 'user.name', 'test']);

      // Create a simple Dart package structure
      await _createTestPackage(repoRoot);

      // Run pub get to generate package_config.json for analyzer
      await _runPubGet(repoRoot);

      await _runGit(repoRoot, ['add', '-A']);
      await _runGit(repoRoot, ['commit', '-qm', 'initial']);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('analyzeWorkingTree detects no changes in clean repo', () async {
      final orchestrator = ImpactOrchestrator(rootPath: repoRoot);
      final report = await orchestrator.analyzeWorkingTree();

      expect(report.changedFiles, isEmpty);
      expect(report.impactedFiles, isEmpty);
      expect(report.metrics.changedFileCount, 0);
      expect(report.severity.band, SeverityBand.low);
    });

    test('analyzeWorkingTree detects modified Dart file', () async {
      // Modify a Dart file
      final tokenService = File(p.join(repoRoot, 'lib', 'src', 'auth', 'token_service.dart'));
      await tokenService.writeAsString('''
// modified
class TokenService {
  String secret = 'test';
  int refreshCount = 0;

  Future<String> refreshToken() async {
    refreshCount += 1;
    return '\$secret-\$refreshCount';
  }
}
''');

      final orchestrator = ImpactOrchestrator(rootPath: repoRoot);
      final report = await orchestrator.analyzeWorkingTree();

      expect(report.metrics.changedFileCount, 1);
      expect(report.changedFiles.any((f) => f.path.contains('token_service.dart')), isTrue);
    });

    test('analyzeWorkingTree detects impact on dependent files', () async {
      // The test package has app.dart importing token_service.dart
      // Modify token_service.dart and verify app.dart is impacted
      final tokenService = File(p.join(repoRoot, 'lib', 'src', 'auth', 'token_service.dart'));
      await tokenService.writeAsString('''
// modified
class TokenService {
  String secret = 'test';
  int refreshCount = 0;

  Future<String> refreshToken() async {
    refreshCount += 1;
    return '\$secret-\$refreshCount';
  }
}
''');

      final orchestrator = ImpactOrchestrator(rootPath: repoRoot);
      final report = await orchestrator.analyzeWorkingTree();

      // Should find impacted files (app.dart, auth_repository.dart)
      expect(report.metrics.impactedFileCount, greaterThan(0));
      expect(report.metrics.impactedClassCount, greaterThan(0));
    });

    test('analyzeCommitRange works', () async {
      // Make a change and commit
      final tokenService = File(p.join(repoRoot, 'lib', 'src', 'auth', 'token_service.dart'));
      await tokenService.writeAsString('''
// modified
class TokenService {
  String secret = 'test';
  int refreshCount = 0;

  Future<String> refreshToken() async {
    refreshCount += 1;
    return '\$secret-\$refreshCount';
  }
}
''');
      await _runGit(repoRoot, ['add', '-A']);
      await _runGit(repoRoot, ['commit', '-qm', 'modify token service']);

      final orchestrator = ImpactOrchestrator(rootPath: repoRoot);
      final report = await orchestrator.analyzeCommitRange(baseRef: 'HEAD~1', headRef: 'HEAD');

      expect(report.mode, ImpactMode.commitRange);
      expect(report.metrics.changedFileCount, 1);
    });
  });
}

Future<void> _createTestPackage(String repoRoot) async {
  // pubspec.yaml
  await File(p.join(repoRoot, 'pubspec.yaml')).writeAsString('''
name: test_package
description: Test package for impact analyzer
publish_to: none
environment:
  sdk: ^3.13.0
''');

  // lib/main.dart
  await Directory(p.join(repoRoot, 'lib')).create(recursive: true);
  await File(p.join(repoRoot, 'lib', 'main.dart')).writeAsString('''
import 'package:test_package/app.dart';

void main() {
  final app = SampleApp();
  print(app.greet('world'));
}
''');

  // lib/app.dart
  await File(p.join(repoRoot, 'lib', 'app.dart')).writeAsString('''
import 'package:test_package/src/auth/auth_repository.dart';
import 'package:test_package/src/auth/token_service.dart';
import 'package:test_package/src/model/user.dart';

class SampleApp {
  SampleApp(this.repository, this.tokenService, this.currentUser);

  final AuthRepository repository;
  final TokenService tokenService;
  final User currentUser;

  Future<String> greet(String name) async {
    await tokenService.refreshToken();
    return repository.findUser(name)?.displayName ?? 'guest';
  }
}
''');

  // lib/src/model/user.dart
  await Directory(p.join(repoRoot, 'lib', 'src', 'model')).create(recursive: true);
  await File(p.join(repoRoot, 'lib', 'src', 'model', 'user.dart')).writeAsString('''
class User {
  User(this.id, this.displayName);

  final String id;
  final String displayName;
}
''');

  // lib/src/auth/token_service.dart
  await Directory(p.join(repoRoot, 'lib', 'src', 'auth')).create(recursive: true);
  await File(p.join(repoRoot, 'lib', 'src', 'auth', 'token_service.dart')).writeAsString('''
class TokenService {
  String secret = 'test';
  int refreshCount = 0;

  Future<String> refreshToken() async {
    refreshCount += 1;
    return '\$secret-\$refreshCount';
  }
}
''');

  // lib/src/auth/auth_repository.dart
  await File(p.join(repoRoot, 'lib', 'src', 'auth', 'auth_repository.dart')).writeAsString('''
import 'package:test_package/src/auth/token_service.dart';
import 'package:test_package/src/model/user.dart';

class AuthRepository {
  AuthRepository(this.tokenService);

  final TokenService tokenService;

  User? findUser(String name) => null;
}
''');
}

Future<void> _runPubGet(String workingDir) async {
  final result = await Process.run('dart', ['pub', 'get'], workingDirectory: workingDir);
  if (result.exitCode != 0) {
    throw Exception('dart pub get failed: ${result.stderr}');
  }
}

Future<void> _runGit(String workingDir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: workingDir);
  if (result.exitCode != 0) {
    throw Exception('git ${args.join(' ')} failed: ${result.stderr}');
  }
}