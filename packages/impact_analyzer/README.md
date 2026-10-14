# impact_analyzer

Dart/Flutter change impact analysis: git diffs, symbol-level blast radius,
heuristic severity, and AI-plan preflight.

This is the core engine. It has no CLI, no HTTP server and no UI — those are
built on top of it as separate packages.

## What it does

- Reads uncommitted changes (`all`, `staged`, `unstaged`) or a commit range
- Resolves changed symbols through the Dart `analyzer`, with a regex fallback
  for files that will not parse
- Scans the reverse reference graph and expands transitively by breadth-first
  search
- Scores severity across impacted files, classes, public API hits, Flutter UI
  roots, graph depth and impacted tests
- Parses an AI plan as structured JSON or freeform markdown, and estimates its
  impact before any edit is applied

## Usage

```dart
import 'package:impact_analyzer/impact_analyzer.dart';

final orchestrator = ImpactOrchestrator(rootPath: '/path/to/repo');

final report = await orchestrator.analyzeWorkingTree();
print(report.severity.band);   // low | medium | high | critical
print(report.metrics.impactedFileCount);
```

Or estimate a plan before touching the repo:

```dart
final preview = await orchestrator.analyzePlan(
  planJson: {
    'steps': [
      {
        'files': ['lib/src/auth/token_service.dart'],
        'symbols': ['TokenService.refreshToken'],
      },
    ],
  },
);
```

Commit ranges work the same way:

```dart
final report = await orchestrator.analyzeCommitRange(baseRef: 'main');
```

### Severity bands

| Band | Score |
|---|---|
| `low` | 0.00 – 0.24 |
| `medium` | 0.25 – 0.49 |
| `high` | 0.50 – 0.74 |
| `critical` | 0.75 – 1.00 |

Severity is a **heuristic triage signal, not proof of breakage.**

### Accuracy notes

The reference scan counts a dependency only when the symbol is genuinely
*used*, not merely imported. `part` files collapse into their library,
extension members are indexed, and field/getter/setter triples collapse to a
single symbol entry.

### Configuration

An optional `.impactignore` in the repo root is applied on top of the built-in
exclusions. Later rules win, so a `.impactignore` can re-include a built-in
default.

## Surfaces built on this package

- [`impact_analyzer_cli`](https://pub.dev/packages/impact_analyzer_cli) —
  `impact analyze | plan | serve`
- [`impact_analyzer_dashboard`](https://pub.dev/packages/impact_analyzer_dashboard) —
  local web UI
- [`impact_analyzer_mcp`](https://pub.dev/packages/impact_analyzer_mcp) —
  MCP server for AI agents

## License

MIT — see [LICENSE](LICENSE).