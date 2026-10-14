## 0.1.0

Initial release.

- Loopback-only HTTP server. Binds `127.0.0.1` and makes no outbound calls.
- API surface:
  - `GET  /api/health`
  - `GET  /api/impact/working-tree`
  - `GET  /api/impact/range`
  - `POST /api/impact/plan`
  - `GET  /api/impact/summary`
  - `GET  /api/impact/graph`
  - `GET  /api/contract` — self-documenting contract for agents
- `ReportView` projections: summary carries severity and rationale without file
  lists; graph projection never hides truncation.
- Static asset lookup rejects path traversal.
- Structured errors using the documented error contract.
- Web UI with five impact-graph representations of the same payload:
  **layered** (Cytoscape `breadthfirst`, default), **sugiyama** (Eclipse ELK
  layered), **rings** (concentric blast radius), **matrix** (files × files
  grid), **tree** (collapsible directory outline).
- Plan lab for estimating impact before edits are applied.
- Browser libraries vendored locally (`cytoscape`, `elkjs`) so the dashboard
  stays offline.