# Plan — Impact Analyzer (Dart Only)

## 1. Objective

Ship a Dart-only Impact Analyzer as a monorepo of packages: core library, CLI, MCP server, and local dashboard — delivering file + graph impact, severity, uncommitted/commit-range analysis, and AI-plan preflight.

## 2. Scope lock

| In | Out (v1) |
|---|---|
| Dart / Flutter projects | Other languages |
| Git working tree + commit ranges | Hosted SaaS |
| Symbol/import impact via analyzer | Runtime/dynamic impact |
| Read-only MCP tools | Mutating agent tools |
| Local dashboard | VS Code extension (later) |

## 3. Strategy

1. **One core, many surfaces** — CLI, MCP, and dashboard only call `package:impact_analyzer`.
2. **Correctness before chrome** — severity + graph accuracy before visual polish.
3. **Agent-ready early** — MCP in phase 2 so AI workflows validate the report schema.
4. **Dashboard last-mile polish** — phase 3 UX can iterate without changing scoring.

## 4. Phases

### Phase 0 — Documentation & scaffold (current)

- Requirements, specification, plan, tasks, analysis (this docs set)
- Melos/pub workspace skeleton
- Sample Flutter fixture package for tests

**Exit:** Docs complete; empty packages resolve with `dart pub get`.

### Phase 1 — Core + CLI

- Git change collector
- Analyzer-backed symbol index + impact graph
- Severity + confidence
- CLI: `analyze`, `plan`, JSON output
- Unit/integration tests on fixture repo

**Exit:** FR-G*, FR-D1–D4, FR-S1–S2, FR-C1–C2 acceptance met.

### Phase 2 — MCP server

- stdio MCP exposing working tree, range, plan, graph summary, severity
- Cursor config example in README
- Golden JSON fixtures for tool responses

**Exit:** FR-M1 + agent can call tools without the dashboard.

### Phase 3 — Dashboard

- Local Dart HTTP server + static UI
- File list, metrics, severity, interactive graph
- Plan paste → analyze
- Visual design pass (non-generic, brand-forward)

**Exit:** FR-U1–U3 met; `impact serve` demo-ready.

### Phase 4 — Hardening

- Cache / warm analysis under `.impact_analyzer/` or `.dart_tool/`
- `.impactignore` + `impact.yaml`
- Public API + Flutter UI weighting
- Test impact mapping
- Performance pass on medium app

**Exit:** NFR targets met; publish prep.

### Phase 5 — Publish prep

- pub.dev READMEs, examples, changelog
- Versioning policy
- Optional: CI gate mode (`--fail-on high`)

## 5. Milestones

| Milestone | Outcome |
|---|---|
| M0 | Docs + workspace scaffold |
| M1 | CLI produces `ImpactReport` for working tree |
| M2 | MCP tools live |
| M3 | Dashboard live |
| M4 | Hardened + documented for pub.dev |

## 6. Package delivery order

```
packages/impact_analyzer            # Phase 1
packages/impact_analyzer_cli        # Phase 1
packages/impact_analyzer_mcp        # Phase 2
packages/impact_analyzer_dashboard  # Phase 3
```

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Analyzer performance on large apps | Cache contexts; limit depth; incremental file set |
| Vague AI plans | Prefer structured JSON; lower confidence otherwise |
| Graph noise from generated files | Default ignores for `*.g.dart`, `*.freezed.dart` |
| Severity distrust | Transparent rationale list + confidence band |

## 8. Success metrics (v1)

- Developer can answer “what does this WIP change touch?” in one CLI or dashboard view.
- Agent can call MCP and receive file count, class count, and severity without reading the whole repo.
- Same report JSON from CLI, MCP, and dashboard for the same git state.

## 9. Immediate next step after docs

Scaffold monorepo packages and a `fixtures/sample_app` Flutter/Dart project used by tests.
