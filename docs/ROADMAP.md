# Roadmap — Impact Analyzer (Beyond v1)

Dart-only v1 ships first. Items below are candidates after core + MCP + dashboard are solid.

## Near-term (v1.x)

- Watch mode for live dashboard updates
- Richer line-hunk → symbol mapping (only symbols touched by diff lines)
- `--fail-on` CI gate + SARIF export
- Melos/pub workspace multi-package impact in one report
- Custom Flutter root types via `impact.yaml`
- Graph export (SVG/PNG) for PR descriptions

## Medium-term

- VS Code / Cursor extension webview hosting the same UI
- PR comment bot formatting (`ImpactReport` → markdown)
- Historical co-change hotspots from git log
- Suggested test command set from impacted tests
- Incremental analyzer cache shared with `dart analyze`

## Long-term (optional)

- Multi-language **heuristics** (file/import only) — still not full semantic parity
- Team rules: ownership CODEOWNERS overlay on impact graph
- Policy packs (e.g. “public API change requires changelog entry”)
- Hosted optional sync — only if privacy model is clear

## Explicitly deferred

- Automatic code repair
- Guaranteeing runtime correctness
- Non-Dart deep semantic graphs as a v1 promise
