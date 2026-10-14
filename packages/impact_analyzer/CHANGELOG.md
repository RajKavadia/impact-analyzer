## 0.1.0

Initial release.

- `GitDiffCollector` — working-tree, staged and unstaged scopes, plus commit
  ranges, with rename and deletion handling.
- `DartSymbolIndex` — analyzer-backed symbol and reference resolution with a
  regex fallback for files that do not parse. Resolves classes, enums, mixins,
  extensions, typedefs and extension members; collapses `part` files into their
  library; collapses field/getter/setter triples to a single symbol entry.
- `ImpactGraphBuilder` — reverse-reference scan with breadth-first transitive
  expansion and offset-precise type attribution.
- `SeverityScorer` — saturating weighted score across impacted files, classes,
  public API hits, Flutter UI roots, graph depth and impacted tests. Produces a
  `low`/`medium`/`high`/`critical` band with per-term rationale.
- `ConfidenceScorer` — heuristic confidence band with explanatory notes.
- `PlanExtractor` — parses AI plans as either structured JSON or freeform
  markdown.
- `IgnoreRules` — built-in exclusions plus optional `.impactignore`. Later
  rules win, so a `.impactignore` can re-include a built-in default.
- `ImpactOrchestrator` — wires the above into a single `ImpactReport`.