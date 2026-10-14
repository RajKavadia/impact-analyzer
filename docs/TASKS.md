# Tasks — Impact Analyzer (Dart Only)

Status legend: `todo` | `doing` | `done` | `blocked`

## Phase 0 — Docs & scaffold

| ID | Task | Status |
|---|---|---|
| T0.1 | Write REQUIREMENTS.md | done |
| T0.2 | Write SPECIFICATION.md | done |
| T0.3 | Write PLAN.md | done |
| T0.4 | Write TASKS.md | done |
| T0.5 | Write ANALYSIS.md | done |
| T0.6 | Write ARCHITECTURE, MCP, SEVERITY, DASHBOARD, ROADMAP | done |
| T0.7 | Root README linking to docs | done |
| T0.8 | Create pub workspace with four packages | done |
| T0.9 | Add `fixtures/sample_app` Dart fixture | done |
| T0.10 | MIT LICENSE | done |
| T0.11 | CI skeleton (`dart analyze`, `dart test`) | todo |

## Phase 1 — Core library + CLI

| ID | Task | Status |
|---|---|---|
| T1.1 | Define public models: `ImpactReport`, graph, severity, confidence | done |
| T1.2 | Implement `GitDiffCollector` (working tree + range) | done |
| T1.3 | Implement `.impactignore` + built-in ignores | done |
| T1.4 | Implement `DartSymbolIndex` with `package:analyzer` | done |
| T1.5 | Implement `ImpactGraphBuilder` (direct + transitive) | done |
| T1.6 | Implement `SeverityScorer` per SEVERITY.md | done |
| T1.7 | Implement `analyzeWorkingTree` / `analyzeCommitRange` | done |
| T1.8 | Implement plan parser + `analyzePlan` | done |
| T1.9 | CLI: `impact analyze` with JSON/text formatters | done |
| T1.10 | CLI: `impact plan` | done |
| T1.11 | Unit tests for scorer + ignore rules | done |
| T1.12 | Integration tests on fixture with seeded diffs | done |
| T1.13 | CLI `impact serve` real dashboard server | todo |
| T1.14 | Reference-precise class counting + plan symbol scoping | done |

## Phase 2 — MCP

| ID | Task | Status |
|---|---|---|
| T2.1 | Choose/implement Dart MCP stdio transport | todo |
| T2.2 | Tool: `analyze_working_tree` | todo |
| T2.3 | Tool: `analyze_commit_range` | todo |
| T2.4 | Tool: `analyze_plan` | todo |
| T2.5 | Tool: `get_impact_summary` (counts + severity only) | todo |
| T2.6 | Tool: `get_impact_graph` | todo |
| T2.7 | Cursor MCP config example + docs/MCP.md sync | todo |
| T2.8 | Golden tests for MCP JSON responses | todo |

## Phase 3 — Dashboard

| ID | Task | Status |
|---|---|---|
| T3.1 | Dart HTTP server (`serve`) + static asset hosting | todo |
| T3.2 | API routes per SPECIFICATION.md | todo |
| T3.3 | UI: severity hero + metrics | todo |
| T3.4 | UI: changed vs impacted file tables | todo |
| T3.5 | UI: interactive impact graph | todo |
| T3.6 | UI: AI plan paste panel | todo |
| T3.7 | Visual design system (CSS variables, motion) | todo |
| T3.8 | Desktop responsive layout pass | todo |

## Phase 4 — Hardening

| ID | Task | Status |
|---|---|---|
| T4.1 | Analysis cache for warm runs | todo |
| T4.2 | `impact.yaml` configuration loading | todo |
| T4.3 | Public API hit detection | todo |
| T4.4 | Flutter UI-root weighting | todo |
| T4.5 | Test impact mapping | todo |
| T4.6 | Performance profiling on medium fixture | todo |
| T4.7 | Structured error codes end-to-end | todo |

## Phase 5 — Publish prep

| ID | Task | Status |
|---|---|---|
| T5.1 | Package READMEs + examples | todo |
| T5.2 | CHANGELOG + versioning | todo |
| T5.3 | `--fail-on` CLI/CI mode | todo |
| T5.4 | pub.dev dry-run publish checklist | todo |

## Suggested first implementation sprint

1. T0.7–T0.9 — scaffold + fixture  
2. T1.1–T1.7 — core analyze path  
3. T1.9 + T1.11–T1.12 — CLI + tests  

MCP and dashboard follow once `ImpactReport` is stable.
