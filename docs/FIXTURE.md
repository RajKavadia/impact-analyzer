# Test Fixture — `fixtures/sample_app`

The integration fixture is a **real git repository with a deliberately dirty
working tree**, because that is exactly what `GitDiffCollector` is built to
read. It is not tracked in this repository. This doc explains why, and how to
rebuild it.

---

## 1. Why it is not tracked

`fixtures/sample_app/.git` is a nested repository, and git will only accept a
directory containing `.git` into a parent repository as a **gitlink**
(i.e. a submodule entry, mode `160000`).

Two consequences:

1. The fixture's source files do not appear in the parent repository at all.
   Only a pointer to a commit that does not exist on any remote is recorded.
2. **`.gitignore` cannot prevent this.** Ignore rules are consulted after git
   has already classified the directory as a submodule, so
   `fixtures/sample_app/` in `.gitignore` has no effect on the initial add.

A `.git` *file* containing `gitdir: ...` behaves identically, because that is
how submodules are checked out.

The remaining options were:

| Option | Verdict |
|---|---|
| Real submodule | Needs a URL this repo does not have |
| Separate git dir + `.git` pointer file | Still detected as embedded |
| Ignore the fixture, generate it | **Chosen** |

---

## 2. Rebuilding

```powershell
powershell -ExecutionPolicy Bypass -File tools/bootstrap_fixture.ps1 -Force
```

macOS / Linux, or a machine with `pwsh`:

```bash
pwsh tools/bootstrap_fixture.ps1 -Force
```

Without `-Force` the script refuses to overwrite an existing fixture.

Useful parameters:

| Parameter | Purpose |
|---|---|
| `-Path <dir>` | Build somewhere other than `fixtures/sample_app`, e.g. a temp dir for comparison |
| `-Force` | Delete and rebuild an existing fixture |

---

## 3. What it produces

```
commit 1  initial            base sources + test/auth_repository_test.dart
commit 2  modify user model  plan.json, pubspec.lock, one "// touched" line
worktree  (uncommitted)      main.dart rewired, four more "// touched" lines,
                             test/auth_repository_test.dart deleted
```

The uncommitted state is the interesting part, because that is what
`analyze` on the working tree reports:

```
 M lib/main.dart
 M lib/src/model/user.dart
 D test/auth_repository_test.dart
```

Three changed files, three impacted files, seven impacted classes, depth one,
`low` severity at score `0.196`.

### 3.1 `dart pub get` is mandatory

The script runs `dart pub get` between the two commits. This is not
incidental. The analyzer resolves `package:sample_app/...` imports through
`.dart_tool/package_config.json` (falling back to `pubspec.lock`). Without it
the fixture parses but resolves nothing, and every run reports an empty impact
set:

```
without pub get:  band=low score=0.059 changed=3 impacted=0 depth=0
with pub get:     band=low score=0.196 changed=3 impacted=3 depth=1
```

The `0.059` run looks plausible enough to be a false pass, which is why the
script does the resolve step unconditionally.

---

## 4. Verifying a rebuild

The script prints its own summary, but the real check is that the analysis
matches:

```bash
dart run impact_analyzer_cli:impact analyze --path fixtures/sample_app --json
```

Expected metrics:

| Metric | Expected |
|---|---|
| `severity.band` | `low` |
| `severity.score` | `0.196` |
| `changedFileCount` | 3 |
| `impactedFileCount` | 3 |
| `impactedClassCount` | 7 |
| `maxDepthReached` | 1 |
| `publicApiHits` | 1 |

### 4.1 Line endings

Files are written with LF so a rebuild is identical on every OS. The fixture
that shipped before this script existed had mixed CRLF and LF endings, so a
rebuilt fixture will not be byte-identical to an old one. Content and analysis
are identical; the byte comparison is not meaningful and should not be a
regression signal.

---

## 5. Shape of the fixture

```
fixtures/sample_app/
  pubspec.yaml
  plan.json                      sample plan for the plan-lab demo
  lib/
    app.dart                     SampleApp, wires the services
    main.dart                    entry point (modified in the worktree)
    src/
      auth/
        auth_repository.dart     AuthRepository
        token_service.dart       TokenService
      model/
        user.dart                User, UserRole, Auditable, UserId
      ui/
        sample_widget.dart       Widget / StatefulWidget / ScreenState
  test/
    auth_repository_test.dart    deleted in the worktree
```

The `src/ui/sample_widget.dart` shapes (`Widget`, `StatefulWidget`,
`ScreenState`, a top-level `runSampleWidget`) are there so the symbol index
has Flutter-style UI roots to resolve, not just plain Dart classes.

`plan.json` is the input for the dashboard plan-lab and for
`impact plan --file`.