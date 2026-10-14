# Specification — Impact Analyzer (Dart Only)

## 1. Overview

This specification defines the technical contracts for the Impact Analyzer system: inputs, outputs, core algorithms, package APIs, CLI, MCP tools, and dashboard endpoints.

## 2. System context

```
Developer / AI Agent
        │
        ├── CLI (impact_analyzer_cli)
        ├── MCP (impact_analyzer_mcp)
        └── Dashboard (impact_analyzer_dashboard)
                │
                ▼
        impact_analyzer (core library)
                │
        ├── GitDiffCollector
        ├── DartSymbolIndex (package:analyzer)
        ├── ImpactGraphBuilder
        ├── SeverityScorer
        └── ImpactReport
```

## 3. Inputs

### 3.1 Analyze working tree

| Field | Type | Description |
|---|---|---|
| `rootPath` | string | Path inside a Dart/Flutter git repo |
| `scope` | enum | `all` \| `staged` \| `unstaged` (default `all`) |
| `includeTests` | bool | Include test mapping (default true) |
| `maxDepth` | int | Max transitive hops (default 5) |

### 3.2 Analyze commit range

| Field | Type | Description |
|---|---|---|
| `rootPath` | string | Repo path |
| `baseRef` | string | e.g. `main`, `origin/main`, commit SHA |
| `headRef` | string | default `HEAD` |

### 3.3 Analyze AI plan

| Field | Type | Description |
|---|---|---|
| `rootPath` | string | Repo path |
| `planText` | string? | Freeform markdown plan |
| `plan` | object? | Structured plan (preferred) |

#### Structured plan schema

```json
{
  "title": "Refactor auth token refresh",
  "steps": [
    {
      "description": "Extract refresh logic",
      "files": ["lib/src/auth/token_service.dart"],
      "symbols": ["TokenService", "refreshToken"]
    }
  ]
}
```

If only `planText` is provided, the extractor uses path-like tokens (`lib/.../*.dart`) and Dart identifier heuristics. Ambiguity lowers `confidence`.

## 4. Output model — `ImpactReport`

```json
{
  "version": "1",
  "rootPath": "/path/to/project",
  "mode": "working_tree",
  "generatedAt": "2026-10-14T17:00:00.000Z",
  "git": {
    "branch": "feature/x",
    "head": "abc1234",
    "isClean": false
  },
  "changedFiles": [
    {
      "path": "lib/src/auth/token_service.dart",
      "status": "modified",
      "symbols": ["TokenService", "refreshToken"]
    }
  ],
  "impactedFiles": [
    {
      "path": "lib/src/auth/auth_repository.dart",
      "relation": "direct",
      "reason": "imports TokenService",
      "impactedSymbols": ["AuthRepository"]
    }
  ],
  "graph": {
    "nodes": [
      { "id": "lib/src/auth/token_service.dart", "kind": "file", "changed": true },
      { "id": "TokenService", "kind": "class", "file": "lib/src/auth/token_service.dart" }
    ],
    "edges": [
      { "from": "lib/src/auth/auth_repository.dart", "to": "TokenService", "type": "references" }
    ]
  },
  "metrics": {
    "changedFileCount": 1,
    "impactedFileCount": 12,
    "impactedClassCount": 7,
    "directCount": 4,
    "transitiveCount": 8,
    "publicApiHits": 2,
    "impactedTestCount": 3
  },
  "severity": {
    "band": "high",
    "score": 0.72,
    "rationale": [
      "7 impacted classes",
      "2 public API hits",
      "12 impacted files"
    ]
  },
  "confidence": {
    "band": "high",
    "score": 0.9,
    "notes": []
  },
  "warnings": []
}
```

## 5. Core algorithms

### 5.1 Change set collection

1. Verify git repo (`git rev-parse --show-toplevel`).
2. Verify Dart project (`pubspec.yaml` present at package or workspace root).
3. Collect paths via `git status --porcelain` and/or `git diff --name-status`.
4. Filter with `.impactignore` + built-in ignores.
5. Keep only `.dart` files for symbol analysis; non-Dart changed files appear in `changedFiles` with empty `symbols` and do not expand the graph (except as informational).

**Decisions locked during implementation:**

- **Untracked files are included.** `git status --porcelain -z -uall` is used for the
  default `all` scope, and untracked (`??`) files are reported with status `added`.
  This matters because agent workflows usually create new, uncommitted files.
- **`changedFileCount` counts Dart files only.** Non-Dart changes still appear in the
  `changedFiles` array for visibility but never affect metrics or severity.
- **v1 symbol granularity is whole-file.** Every declaration in a changed Dart file
  is treated as changed; diff-hunk-level precision is deferred (see ROADMAP).
- **Reference resolution is analyzer-backed, not `analysis_server`-based.**
  Changed files are resolved via `AnalysisContextCollection`, and identifier and
  named-type references are matched against the changed symbol set.
- **Report paths are repo-relative POSIX.** Internally the index stores absolute
  paths, but every path emitted in `ImpactReport` is repo-relative.
- **Impacted classes are reference-precise.** A type counts as impacted only when a
  resolved reference to a changed symbol appears inside it (matched by source
  offset). Importing a changed library still marks the *file* as a dependent, but
  no longer inflates `impactedClassCount` on its own.
- **Plan `symbols` narrow the change set.** When a plan step names symbols (bare
  `refreshToken` or qualified `TokenService.refreshToken`), only those declarations
  are treated as changed instead of every declaration in the file. Naming symbols
  that do not exist falls back to the whole file rather than reporting a false zero.
- **`part` files expand through their library.** Blast-radius seeds are the library
  that owns each changed file, so edits inside a part reach the library's importers.

### 5.2 Symbol index

1. Create `AnalysisContextCollection` for the package (and melos/workspace members when detected).
2. For each changed Dart file, resolve compilation unit elements.
3. Collect declared public/private types and members touched by the diff hunks when line-level diff is available; otherwise treat whole-file declared types as changed.

### 5.3 Impact graph

1. Seed nodes = changed files + changed symbols.
2. Find files that import those libraries.
3. Find elements that reference changed elements (where analyzer reference resolution is available).
4. BFS/DFS up to `maxDepth` for transitive dependents.
5. Emit nodes/edges for dashboard and MCP.

### 5.4 Severity

See [SEVERITY.md](./SEVERITY.md). Summary:

- Inputs: impacted files, impacted classes, public API hits, Flutter UI roots, depth.
- Output: score `0.0–1.0` mapped to bands.

## 6. Package API (core)

Proposed library surface (`package:impact_analyzer`):

```dart
Future<ImpactReport> analyzeWorkingTree(AnalyzeWorkingTreeRequest request);
Future<ImpactReport> analyzeCommitRange(AnalyzeCommitRangeRequest request);
Future<ImpactReport> analyzePlan(AnalyzePlanRequest request);
```

Supporting types: `ImpactReport`, `ChangedFile`, `ImpactedFile`, `ImpactGraph`, `SeverityResult`, `ConfidenceResult`.

## 7. CLI

| Command | Behavior |
|---|---|
| `impact analyze [--path .] [--scope all\|staged\|unstaged] [--json]` | Working tree report |
| `impact analyze --base main [--head HEAD]` | Commit range |
| `impact plan --file plan.md` or `--stdin` | Plan analysis |
| `impact serve [--port 7788]` | Start dashboard server |

Exit codes: `0` success, `1` analysis error, `2` usage error, `3` severity ≥ configured fail threshold (optional flag).

## 8. HTTP dashboard API

Base: `http://127.0.0.1:7788`

| Method | Path | Description |
|---|---|---|
| GET | `/` | SPA / dashboard UI |
| GET | `/api/health` | Liveness |
| GET | `/api/impact/working-tree` | Current working tree report |
| POST | `/api/impact/plan` | Body: plan text or JSON |
| GET | `/api/impact/range?base=&head=` | Commit range report |

## 9. MCP

See [MCP.md](./MCP.md). Transport: stdio. Tools are read-only.

## 10. Configuration

### `.impactignore`

gitignore-style patterns.

### `impact.yaml` (optional)

```yaml
maxDepth: 5
failOnSeverity: critical
weights:
  impactedFile: 1.0
  impactedClass: 1.5
  publicApi: 2.0
  flutterUiRoot: 1.5
ignores:
  - "**/*.g.dart"
  - "**/*.freezed.dart"
```

## 11. Error model

```json
{
  "code": "not_dart_project",
  "message": "No pubspec.yaml found at or above rootPath",
  "details": {}
}
```

Common codes: `not_git_repo`, `not_dart_project`, `analyzer_failed`, `invalid_plan`, `git_failed`.

## 12. Compatibility

- Dart SDK: `^3.13.0` (current stable at scaffold time)
- `package:analyzer`: `^14.5.0` (element-model APIs: `LibraryFragment.importedLibraries`,
  `Fragment.source`, `NamedType.element`)
- Flutter projects supported as Dart packages with Flutter SDK constraint
- OS: Windows, macOS, Linux
