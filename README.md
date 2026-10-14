# Impact Analyzer

**Dart/Flutter change impact analysis for developers and AI agents.**

Point it at a repo and it tells you what your uncommitted work breaks, how far
the damage reaches, and how bad it is — before you push, and before an agent
starts editing.

> **v1 scope:** Dart and Flutter projects only.

---

## What it does

| Capability | Detail |
|---|---|
| **Working-tree analysis** | Uncommitted changes, or `--scope staged` / `--scope unstaged` |
| **Commit-range analysis** | `--base main` to diff two refs |
| **Symbol-level blast radius** | Resolves classes, enums, mixins, extensions, typedefs and `part` files through the Dart `analyzer` |
| **Transitive impact** | Breadth-first expansion out to a configurable depth |
| **AI plan preflight** | Paste a plan, get the severity *before* the edits exist |
| **Severity scoring** | Saturating weighted score across files, classes, public API, UI roots, depth and tests |
| **Local dashboard** | Loopback-only web UI with the same engine as the CLI |
| **MCP server** | Agent-facing tools (scaffold) |

---

## Quick start

```bash
git clone <this repo>
cd impact-analyzer
dart pub get
```

The integration fixture is generated, not committed:

```powershell
# PowerShell
powershell -ExecutionPolicy Bypass -File tools/bootstrap_fixture.ps1 -Force
```

```bash
# or pwsh / bash
pwsh tools/bootstrap_fixture.ps1 -Force
```

Then:

```bash
# Working tree
dart run impact_analyzer_cli:impact analyze --path . --json

# Commit range
dart run impact_analyzer_cli:impact analyze --base main

# AI plan preflight
dart run impact_analyzer_cli:impact plan --file plan.md

# Local dashboard on http://127.0.0.1:7788
dart run impact_analyzer_cli:impact serve --path . --port 7788
```

Once published:

```bash
dart pub global activate impact_analyzer_cli   # provides the `impact` command
```

---

## Packages

```
packages/
  impact_analyzer            # core library — the engine everything else calls
  impact_analyzer_cli        # `impact analyze | plan | serve`
  impact_analyzer_dashboard  # HTTP server + web UI
  impact_analyzer_mcp        # MCP server (scaffold)
```

A pub workspace, so one `dart pub get` at the root covers all of them.

---

## CLI reference

### `impact analyze`

| Flag | Default | Meaning |
|---|---|---|
| `-p, --path` | `.` | Repository path |
| `--scope` | `all` | `all`, `staged` or `unstaged` |
| `--base` | — | Base ref for a commit range, e.g. `main` |
| `--head` | `HEAD` | Head ref for a commit range |
| `-d, --depth` | unlimited | Max transitive depth |
| `--json` | off | Emit the full `ImpactReport` as JSON |
| `--fail-on` | — | Exit `3` if severity ≥ `low`\|`medium`\|`high`\|`critical` |

```bash
# Only staged work, two hops deep, fail CI on anything high or worse
impact analyze --scope staged --depth 2 --fail-on high
```

### `impact plan`

| Flag | Default | Meaning |
|---|---|---|
| `-p, --path` | `.` | Repository path |
| `-f, --file` | — | Plan file, markdown or JSON |
| `--stdin` | off | Read the plan from stdin |
| `-d, --depth` | unlimited | Max transitive depth |
| `--json` | off | Emit JSON |
| `--fail-on` | — | Exit `3` on threshold |

Accepts either structured JSON or freeform markdown, so you can paste an agent's
plan verbatim.

### `impact serve`

| Flag | Default | Meaning |
|---|---|---|
| `-p, --path` | `.` | Repository path |
| `-P, --port` | `7788` | HTTP port |
| `--json` | off | Print startup details as JSON |

Binds `127.0.0.1` only and makes no outbound calls.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Analysis error |
| `2` | Usage error |
| `3` | Severity met or exceeded `--fail-on` |

`--fail-on` is what makes this usable as a CI gate.

---

## How the analysis works

```
git diff ──► changed files ──► symbol index ──► reverse reference scan
                                                          │
                          blast-depth BFS ◄────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
              severity score               graph payload
```

1. **GitDiffCollector** reads the working tree (`git status`, `git diff`,
   `git diff --cached`), or a commit range. Renames and deletions are handled.
2. **DartSymbolIndex** resolves every changed file's symbols through the Dart
   `analyzer`, with a regex fallback when a file will not parse. `part` files
   collapse into their library; extension members are indexed; fields, getters
   and setters collapse to one symbol entry.
3. **ImpactGraphBuilder** scans the reverse reference graph and expands
   transitively by breadth-first search, counting a reference only when the
   symbol is genuinely *used*, not merely imported.
4. **SeverityScorer** applies a saturating weighted formula — see
   [docs/SEVERITY.md](docs/SEVERITY.md) for the weights and denominators.
5. **IgnoreRules** applies built-in exclusions plus an optional
   `.impactignore` in the repo root. Later rules win, so a `.impactignore` can
   re-include a built-in default.

### Severity bands

| Band | Score | Meaning |
|---|---|---|
| `low` | 0.00 – 0.24 | Small local change, few dependents |
| `medium` | 0.25 – 0.49 | Moderate fan-out, review dependents |
| `high` | 0.50 – 0.74 | Wide file/class impact or public API touch |
| `critical` | 0.75 – 1.00 | Very wide blast radius and/or core UI/public API |

Severity is a **heuristic triage signal, not proof of breakage.**

---

## The dashboard

```bash
impact serve --path . --port 7788
```

Loopback only, no outbound calls, same engine as the CLI — the human view and
the agent view can never disagree.

### Five graph representations

The impact graph is a small, sparse DAG over file dependencies, which a
force-directed layout renders as an unreadable blob. So there are five views,
all rendering the same payload:

| View | Engine | Question it answers |
|---|---|---|
| **Layered** (default) | Cytoscape `breadthfirst` | What breaks, and in what order? |
| **Sugiyama** | Eclipse ELK `layered` | Same, with edge crossings minimised |
| **Rings** | manual concentric placement | How far does the blast radius reach? |
| **Matrix** | files × files grid | Which files reference which, at scale? |
| **Tree** | collapsible directory outline | What is in scope, by directory? |

Switch in the panel head, or deep-link: `#layered`, `#sugiyama`, `#rings`,
`#matrix`, `#tree`.

Blast depth drives colour everywhere — blue changed, red one hop, orange two,
yellow three, grey four or more.

See [docs/GRAPH_VIEWS.md](docs/GRAPH_VIEWS.md) for the engines and the
Cytoscape/ELK gotchas worth knowing before editing `web/views.js`.

### API

The dashboard is also the machine-readable surface for agents:

```
GET  /api/health
GET  /api/impact/working-tree
GET  /api/impact/range
POST /api/impact/plan
GET  /api/impact/summary
GET  /api/impact/graph
GET  /api/contract
```

`/api/contract` self-documents the surface, including query parameters, error
codes and severity bands. The dashboard renders it under **Agent access**, so
you can copy the contract without leaving the page.

### Also on the page

- **Severity hero** — band, score and the rationale chips
- **Metric strip** — changed, impacted, classes, direct, transitive, public API
  hits, tests, depth, files indexed
- **Plan lab** — paste a plan, get severity before the edits exist
- **File tables** — impacted and changed sets, filterable, kept in sync with
  the graph selection

---

## Configuration

Drop an optional `.impactignore` in the repo root:

```
# generated code is not worth analysing
lib/generated/
*.g.dart
lib/model/schema.dart
```

Built-in patterns already exclude `.dart_tool/` and `build/`. Later rules win,
so you can re-include a built-in default.

---

## Testing

```bash
dart analyze                                          # clean
cd packages/impact_analyzer       && dart test        # 54 tests
cd packages/impact_analyzer_dashboard && dart test    # 16 tests
```

70 tests covering git diff collection, ignore rules, symbol resolution,
reference precision, part files, extension members, symbol scoping, severity
scoring, plan extraction, the orchestrator, and the dashboard API contract
including path-traversal rejection.

The fixture is deliberately a real git repo with a dirty working tree, because
that is what `GitDiffCollector` reads. See [docs/FIXTURE.md](docs/FIXTURE.md)
for why it is generated rather than committed, and how to rebuild it.

---

## Project layout

```
impact-analyzer/
  packages/
    impact_analyzer/            core engine + tests
    impact_analyzer_cli/        CLI entry point
    impact_analyzer_dashboard/  server, web assets + tests
    impact_analyzer_mcp/        MCP server scaffold
  fixtures/sample_app/           generated integration fixture
  tools/bootstrap_fixture.ps1    rebuilds the fixture
  docs/                          specifications and design notes
```

---

## Documentation

Start at **[docs/README.md](docs/README.md)**.

| Doc | Description |
|---|---|
| [Requirements](docs/REQUIREMENTS.md) | Goals, users, functional requirements |
| [Specification](docs/SPECIFICATION.md) | APIs, report schema, CLI/HTTP contracts |
| [Architecture](docs/ARCHITECTURE.md) | Packages and pipelines |
| [Graph views](docs/GRAPH_VIEWS.md) | The five representations and layout quirks |
| [Severity](docs/SEVERITY.md) | Scoring model, weights, denominators |
| [Dashboard](docs/DASHBOARD.md) | Local UI spec |
| [MCP](docs/MCP.md) | Agent tool contracts |
| [Fixture](docs/FIXTURE.md) | Why it is generated, how to rebuild it |
| [Analysis](docs/ANALYSIS.md) | Feasibility and trade-offs |
| [Plan](docs/PLAN.md) / [Tasks](docs/TASKS.md) / [Roadmap](docs/ROADMAP.md) | Delivery status |
| [Glossary](docs/GLOSSARY.md) | Terms |

---

## Status

Implemented, with tests:

- Core library: git collection, analyzer-backed symbol index, impact graph,
  severity and confidence scoring, plan extraction, ignore rules, orchestrator
- CLI: `analyze`, `plan`, `serve`, exit codes `0`/`1`/`2`/`3`
- Dashboard: HTTP API, web UI, five graph representations, plan lab, agent
  contract surface
- 70 passing tests, `dart analyze` clean

Still to do:

- MCP server is a scaffold — see [docs/MCP.md](docs/MCP.md)
- Multi-language impact analysis (out of v1 scope)

---

## Third-party assets

The dashboard vendors its browser libraries so it stays loopback-only:

| Asset | License |
|---|---|
| `web/vendor/cytoscape.min.js` | MIT |
| `web/vendor/elk.bundled.js` (Eclipse ELK) | EPL-2.0 OR GPL-3.0-or-later |

---

## License

MIT — see [LICENSE](LICENSE).