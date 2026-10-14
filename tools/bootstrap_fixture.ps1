<#
.SYNOPSIS
  Recreates fixtures/sample_app, the git fixture Impact Analyzer analyses.

.DESCRIPTION
  The fixture is a real git repository with two commits and a deliberately
  dirty working tree, because that is the input GitDiffCollector is built to
  read. It is excluded from the parent repository: a directory containing .git
  can only enter a parent repo as a gitlink (submodule), which would drop the
  fixture sources, and .gitignore cannot prevent that. So it is generated.

  The script rebuilds:

    commit 1  initial            base sources + test/auth_repository_test.dart
    commit 2  modify user model  plan.json, pubspec.lock, one "// touched" line
    worktree  (uncommitted)      main.dart rewired, more "// touched" lines,
                                 test/auth_repository_test.dart deleted

  `.dart_tool/` is deliberately not recreated; run `dart pub get` inside the
  fixture if you need it. The analyzer reads sources, not tool state.

.PARAMETER Path
  Where to create the fixture. Defaults to fixtures/sample_app under the repo
  root.

.PARAMETER Force
  Overwrite an existing fixture. Without it the script refuses to touch one.

.EXAMPLE
  pwsh tools/bootstrap_fixture.ps1 -Force

.EXAMPLE
  pwsh tools/bootstrap_fixture.ps1 -Path "$env:TEMP\ia-fixture"
#>
[CmdletBinding()]
param(
  [string] $Path,
  [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Path) { $Path = Join-Path $repoRoot 'fixtures\sample_app' }

if (Test-Path -LiteralPath $Path) {
  if (-not $Force) {
    throw "Fixture already exists at $Path. Re-run with -Force to rebuild it."
  }
  Remove-Item -LiteralPath $Path -Recurse -Force
}

# --------------------------------------------------------------- helpers

function Write-Source {
  param([string] $Relative, [string] $Content)
  $target = Join-Path $script:Root $Relative
  $dir = Split-Path -Parent $target
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  Write-Text -Target $target -Content $Content
}

function Write-Text {
  param([string] $Target, [string] $Content)
  # LF only, so the regenerated fixture is identical on every OS and the
  # analyzer never sees CRLF drift. UTF-8 without a BOM: Dart tooling treats
  # a BOM as a stray character.
  $normalised = ($Content -replace "`r`n", "`n")
  [System.IO.File]::WriteAllText($Target, $normalised, (New-Object System.Text.UTF8Encoding($false)))
}

$script:Root = $Path

# --------------------------------------------------- commit 1: sources

Write-Source 'pubspec.yaml' @'
name: sample_app
description: Dart fixture project used by Impact Analyzer integration tests.
publish_to: none

environment:
  sdk: ^3.13.0
'@

Write-Source 'lib/app.dart' @'
import 'package:sample_app/src/auth/auth_repository.dart';
import 'package:sample_app/src/auth/token_service.dart';
import 'package:sample_app/src/model/user.dart';
import 'package:sample_app/src/ui/sample_widget.dart';

/// Application root wiring services together.
class SampleApp {
  SampleApp(this.repository, this.tokenService, this.currentUser);

  final AuthRepository repository;
  final TokenService tokenService;
  final User currentUser;

  /// Renders the sample widget into a description string.
  String render() => const SampleWidget(title: 'sample').describe();

  Future<String> greet(String name) async {
    await tokenService.refreshToken();
    return repository.findUser(name)?.displayName ?? 'guest';
  }
}
'@

Write-Source 'lib/main.dart' @'
import 'package:sample_app/app.dart';
import 'package:sample_app/src/ui/sample_widget.dart';

/// Entry point of the fixture application.
Future<void> main() async {
  final app = SampleApp();
  final greeting = await app.greet('world');
  print(greeting);
  runSampleWidget();
}
'@

Write-Source 'lib/src/model/user.dart' @'
/// A minimal user model for the fixture.
class User with Auditable {
  User(this.id, this.displayName, this.role);

  final UserId id;
  final String displayName;
  final UserRole role;

  bool get isAdmin => role == UserRole.admin;
}

/// Roles a fixture user may have.
enum UserRole {
  guest,
  member,
  admin;

  bool get elevated => this == admin || this == member;
}

/// Marker mixin for record auditing.
mixin Auditable {
  DateTime? auditedAt;

  void markAudited() {
    auditedAt = DateTime.now();
  }
}

/// Opaque user identifier.
typedef UserId = String;
'@

Write-Source 'lib/src/auth/token_service.dart' @'
import 'package:sample_app/src/model/user.dart';

/// Service that issues and refreshes authentication tokens.
class TokenService {
  TokenService(this.secret);

  final String secret;
  int refreshCount = 0;

  /// Refreshes the current token and increments [refreshCount].
  Future<String> refreshToken() async {
    refreshCount += 1;
    return '$secret-$refreshCount';
  }

  /// Builds a display label for a user.
  String describeUser(User user) => '${user.displayName} (${user.role.name})';
}
'@

Write-Source 'lib/src/auth/auth_repository.dart' @'
import 'package:sample_app/src/auth/token_service.dart';
import 'package:sample_app/src/model/user.dart';

/// Repository that looks up fixture users.
class AuthRepository {
  AuthRepository(this.tokenService, this.seed);

  final TokenService tokenService;
  final List<User> seed;

  /// Finds a user by name.
  User? findUser(String name) {
    for (final user in seed) {
      if (user.displayName == name) return user;
    }
    return null;
  }

  /// Counts users visible to an admin token.
  Future<int> visibleUsers() async {
    final token = await tokenService.refreshToken();
    return token.isEmpty ? 0 : seed.length;
  }
}
'@

Write-Source 'lib/src/ui/sample_widget.dart' @'
/// Base class standing in for a Flutter widget root in this fixture.
abstract class Widget {
  const Widget({required this.title});

  final String title;
}

/// A minimal stateful widget stand-in.
abstract class StatefulWidget extends Widget {
  const StatefulWidget({required super.title});
}

/// A minimal stateless widget implementation.
class SampleWidget extends Widget {
  const SampleWidget({required super.title});

  String describe() => 'SampleWidget($title)';
}

/// A screen state class - another Flutter UI root shape.
class ScreenState extends StatefulWidget {
  const ScreenState() : super(title: 'screen');
}

/// Starts the sample widget (avatar of `runApp`).
void runSampleWidget() {
  final widget = const SampleWidget(title: 'fixture');
  print(widget.describe());
}
'@

Write-Source 'test/auth_repository_test.dart' @'
import 'package:sample_app/src/auth/auth_repository.dart';
import 'package:sample_app/src/auth/token_service.dart';
import 'package:sample_app/src/model/user.dart';
import 'package:test/test.dart';

void main() {
  group('AuthRepository', () {
    late AuthRepository repository;

    setUp(() {
      repository = AuthRepository(
        TokenService('secret'),
        [User('1', 'ada', UserRole.admin)],
      );
    });

    test('findUser returns the matching user', () {
      expect(repository.findUser('ada'), isNotNull);
    });

    test('visibleUsers counts the seed', () async {
      expect(await repository.visibleUsers(), 1);
    });
  });
}
'@

# ------------------------------------------------------ git: commit one

Push-Location -LiteralPath $Path
try {
  & git init -q
  & git config user.email 'test@test.com'
  & git config user.name 'test'
  & git config core.autocrlf false
  & git config core.filemode false
  & git config core.symlinks false

  & git add -A
  & git commit -q -m 'initial'

  # ------------------------------------------------------ dependency resolve

  # The analyzer resolves `package:` imports through .dart_tool/package_config
  # (or pubspec.lock). Without this the fixture resolves no symbols and every
  # analysis comes back with an empty impact set, so it is not optional.
  Write-Host 'Resolving fixture dependencies (dart pub get)…'
  & dart pub get --directory $Path | Out-Null

  # ----------------------------------------------- commit two: user model

  $userPath = 'lib/src/model/user.dart'
  $userFile = Join-Path $Path $userPath
  $nl = "`n"
  [System.IO.File]::AppendAllText($userFile, "$nl// touched$nl")

  Write-Source 'plan.json' @'
{
  "title": "Refactor auth token refresh",
  "steps": [
    {
      "description": "Extract refresh logic",
      "files": [
        "lib/src/auth/token_service.dart",
        "lib/src/auth/auth_repository.dart"
      ],
      "symbols": ["TokenService", "AuthRepository"]
    }
  ]
}
'@

  & git add -A
  & git commit -q -m 'modify user model'

  # ------------------------------------------- uncommitted working tree

  # Rewire the entry point so it constructs services instead of SampleApp()
  # with no arguments. This is the change GitDiffCollector reports on.
  Write-Source 'lib/main.dart' @'
import 'package:sample_app/app.dart';
import 'package:sample_app/src/auth/auth_repository.dart';
import 'package:sample_app/src/auth/token_service.dart';
import 'package:sample_app/src/model/user.dart';
import 'package:sample_app/src/ui/sample_widget.dart';

/// Entry point of the fixture application.
Future<void> main() async {
  final tokenService = TokenService('fixture-secret');
  final repository = AuthRepository(
    tokenService,
    [User('1', 'ada', UserRole.admin)],
  );
  final app = SampleApp(repository, tokenService, repository.findUser('ada')!);
  print(await app.greet('world'));
  runSampleWidget();
}
'@

  # More edits to the same model file, so the diff spans several hunks.
  [System.IO.File]::AppendAllText(
    $userFile, "$nl// touched$nl$nl// touched$nl$nl// touched$nl$nl// touched$nl")

  # Delete the test file in the working tree, which makes the analyzer
  # report a deletion alongside the modifications.
  Remove-Item -LiteralPath (Join-Path $Path 'test/auth_repository_test.dart') -Force

  # ------------------------------------------------------- verification

  Write-Host ''
  Write-Host "Fixture rebuilt at $Path"
  Write-Host ''
  Write-Host 'Commits:'
  & git log --oneline
  Write-Host ''
  Write-Host 'Working tree:'
  & git status --short
}
finally {
  Pop-Location
}