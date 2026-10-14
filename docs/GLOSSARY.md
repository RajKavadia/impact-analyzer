# Glossary — Impact Analyzer

| Term | Meaning |
|---|---|
| **Blast radius** | Set of files/symbols potentially affected by a change |
| **Changed file** | File modified in the git working tree, index, or commit range |
| **Impacted file** | File that depends on (imports/references) changed symbols, directly or transitively |
| **Direct impact** | Immediate dependents (one hop) |
| **Transitive impact** | Dependents reached beyond one hop, up to `maxDepth` |
| **Impact graph** | Nodes (files/symbols) and edges (import/reference) describing blast radius |
| **Severity** | Heuristic risk band derived mainly from impacted file and class counts |
| **Confidence** | How trustworthy the analysis is (analyzer success, plan clarity, truncation) |
| **AI plan** | Proposed edit plan (markdown or JSON) analyzed *before* edits are applied |
| **Public API hit** | Change/impact involving non-private API under package `lib/` |
| **Working tree** | Uncommitted local changes (staged and/or unstaged) |
| **MCP** | Model Context Protocol — tool interface for AI agents |
| **Fixture** | Sample Dart/Flutter project used in automated tests |
