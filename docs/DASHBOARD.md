# Dashboard — Impact Analyzer (Dart Only)

## 1. Purpose

Local, visually strong web UI for humans to inspect impact reports produced by the same core engine as CLI/MCP.

## 2. Runtime

- Command: `impact serve --port 7788`
- Bind: `127.0.0.1` (localhost only by default)
- Stack (planned): Dart HTTP server + static web UI + graph library

## 3. Primary views

### 3.1 Overview (first viewport)

One composition focused on impact, not a dense admin dashboard:

- Product name **Impact Analyzer** as hero-level brand signal
- One headline: current severity band
- One supporting line: `X files changed · Y files impacted · Z classes impacted`
- CTA group: `Re-analyze`, `Paste AI plan`, `Export JSON`
- Dominant visual: interactive impact graph (full-bleed within the main stage)

Avoid first-viewport clutter: no stat-strip overload, no card grid of unrelated promos.

### 3.2 Graph representations

The impact graph ships in five switchable representations — **Layered**
(default), **Sugiyama**, **Rings**, **Matrix** and **Tree** — all rendering the
same `ImpactReport.graph` payload. Force-directed layout is deliberately not
used: the graph is a small directed acyclic graph over file dependencies, which
a force simulation renders as an unreadable blob.

See [GRAPH_VIEWS.md](./GRAPH_VIEWS.md) for the engines, the shared blast-depth
index, the colour scale, and the Cytoscape/ELK gotchas.

### 3.2 Files

- Tabs or split: **Changed** vs **Impacted**
- Columns: path, relation (direct/transitive), symbols, reason
- Click file → focus node in graph

### 3.3 Plan lab

- Text area for markdown/JSON plan
- Run analysis → show severity delta vs current working tree (if both available)

### 3.4 Graph

- Nodes: files and/or classes (toggle)
- Edges: imports / references
- Changed nodes visually distinct from impacted
- Truncation badge when `maxNodes` exceeded

## 4. Visual direction

- Define CSS variables for brand colors; avoid purple-on-white cliché and generic Inter/Roboto stacks
- Atmospheric background (subtle gradient/pattern), not flat white only
- 2–3 intentional motions: graph settle, severity band reveal, re-analyze fade
- Desktop-first; usable down to tablet widths

## 5. API consumption

UI calls:

- `GET /api/impact/working-tree`
- `POST /api/impact/plan`
- `GET /api/impact/range?base=&head=`

No duplicate scoring in the browser.

## 6. Empty & error states

| State | UI |
|---|---|
| Clean git tree | Calm empty graph + “No local changes” |
| Not a Dart project | Clear error with fix hint (`pubspec.yaml`) |
| Analyzer failure | Error panel + confidence low messaging |

## 7. Acceptance checklist

- [ ] Severity band readable in under 3 seconds
- [ ] File list and graph stay in sync on selection
- [ ] Plan paste produces a report without CLI
- [ ] Localhost-only binding documented
- [ ] Works in Chromium and Firefox recent stable
