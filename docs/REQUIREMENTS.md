# Requirements — Impact Analyzer (Dart Only)

## 1. Product summary

Impact Analyzer helps Flutter/Dart developers and AI agents understand the **blast radius** of local code changes (uncommitted and committed) and of proposed AI plans — at **file** and **graph** level — with a clear **severity** score.

## 2. Goals

1. Show all uncommitted (and optionally staged / commit-range) changes in a Dart/Flutter repo.
2. Compute file-level and symbol-level impact using the Dart analyzer.
3. Visualize impact as a dependency/reference graph and as a file list.
4. Accept an AI agent plan and estimate impact before edits are applied.
5. Expose analysis as MCP tools for Cursor/Claude and similar hosts.
6. Ship a visually strong local Dart server dashboard for humans.
7. Distribute as Dart packages usable by Flutter developers.

## 3. Non-goals (v1)

- Non-Dart language semantic analysis.
- Automatic code modification, commits, or PR creation.
- Hosted multi-tenant cloud service.
- Guaranteeing runtime correctness (static heuristics only).

## 4. Users

| Persona | Needs |
|---|---|
| Flutter developer | See what a WIP change will touch before opening a PR |
| AI coding agent | Call MCP tools to size impact before/after planning edits |
| Tech lead / reviewer | Glance at severity and blast radius on a local dashboard |

## 5. Functional requirements

### 5.1 Git change collection

| ID | Requirement | Priority |
|---|---|---|
| FR-G1 | Detect git repository root from a given path | Must |
| FR-G2 | List uncommitted changes (unstaged + staged) with path and status (A/M/D/R) | Must |
| FR-G3 | Support analyzing staged-only or unstaged-only | Should |
| FR-G4 | Support commit-range analysis (e.g. `main...HEAD`) | Must |
| FR-G5 | Ignore paths matching `.impactignore` and sensible defaults (`build/`, `.dart_tool/`, generated) | Must |
| FR-G6 | Fail clearly when path is not a git repo or not a Dart project | Must |

### 5.2 Dart impact analysis

| ID | Requirement | Priority |
|---|---|---|
| FR-D1 | Resolve changed `.dart` files to symbols (classes, enums, mixins, extensions, top-level functions/vars) | Must |
| FR-D2 | Build import / reference graph for the package (and workspace packages when resolvable) | Must |
| FR-D3 | Compute reverse dependents: files/symbols that import or reference changed symbols | Must |
| FR-D4 | Distinguish direct vs transitive impact | Must |
| FR-D5 | Flag public API changes under `lib/` (non-`src`, non-private `_` names) | Should |
| FR-D6 | Map likely impacted tests (`test/`, `*_test.dart`) | Should |
| FR-D7 | Elevate Flutter-sensitive types (e.g. `Widget`, `State`, common state-management roots) in scoring | Should |

### 5.3 AI plan analysis

| ID | Requirement | Priority |
|---|---|---|
| FR-P1 | Accept plan input as markdown text or structured JSON (files + optional symbols) | Must |
| FR-P2 | Extract candidate file paths and symbols from the plan | Must |
| FR-P3 | Run the same impact pipeline as if those files/symbols were changed | Must |
| FR-P4 | Return confidence when plan mapping is ambiguous | Must |
| FR-P5 | Optional LLM-assisted mapping is out of core v1 (agent host may pre-structure the plan) | Could |

### 5.4 Severity

| ID | Requirement | Priority |
|---|---|---|
| FR-S1 | Produce severity band: `low`, `medium`, `high`, `critical` | Must |
| FR-S2 | Base score primarily on impacted file count and impacted class/type count | Must |
| FR-S3 | Apply weights for public API, Flutter UI roots, package boundary crossings | Should |
| FR-S4 | Separate `severity` from `confidence` | Must |
| FR-S5 | Document that severity is heuristic, not a break guarantee | Must |

### 5.5 Surfaces

| ID | Requirement | Priority |
|---|---|---|
| FR-C1 | Core Dart library API returning a structured `ImpactReport` | Must |
| FR-C2 | CLI: `impact analyze`, `impact plan`, `impact serve` | Must |
| FR-M1 | MCP server (stdio) with read-only analysis tools | Must |
| FR-U1 | Local HTTP dashboard showing files, severity, and interactive graph | Must |
| FR-U2 | Dashboard allows pasting an AI plan and re-running analysis | Should |
| FR-U3 | Dashboard is visually distinctive and usable on desktop browsers | Must |

### 5.6 Packaging

| ID | Requirement | Priority |
|---|---|---|
| FR-K1 | Monorepo of publishable packages aimed at Flutter/Dart developers | Must |
| FR-K2 | Clear README install for CLI, MCP (Cursor config), and dashboard | Must |
| FR-K3 | Works on Windows, macOS, Linux where Dart SDK + git are available | Must |

## 6. Non-functional requirements

| ID | Requirement |
|---|---|
| NFR-1 | Analysis of a medium Flutter app (~500 Dart files) completes in under 60s cold / under 10s warm cache (target) |
| NFR-2 | MCP tools are read-only; no filesystem writes except optional local cache under `.dart_tool/` or `.impact_analyzer/` |
| NFR-3 | Library is null-safe Dart 3.x compatible |
| NFR-4 | Deterministic reports for the same git state and same analyzer snapshot |
| NFR-5 | Errors are structured (code + message) for CLI/MCP/dashboard |

## 7. Acceptance criteria (v1)

1. In a sample Flutter repo with uncommitted Dart edits, CLI prints changed files, impacted files, class counts, and severity.
2. MCP `analyze_working_tree` returns equivalent JSON usable by an agent.
3. MCP `analyze_plan` accepts a plan listing 2+ files and returns impact + severity.
4. `impact serve` opens a local dashboard showing file list + graph for the current working tree.
5. Non-Dart-only repos (no `pubspec.yaml`) are rejected with a clear error.

## 8. Constraints

- v1 language scope: **Dart / Flutter only**.
- Prefer `package:analyzer` over regex-based parsing for Dart.
- Prefer shared core so CLI, MCP, and dashboard never diverge on scoring.
