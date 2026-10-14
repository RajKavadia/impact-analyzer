# impact_analyzer_cli

Command-line interface for Impact Analyzer: analyse a working tree, a commit
range, or an AI plan.

Uses [`impact_analyzer`](https://pub.dev/packages/impact_analyzer) as its
engine.

## Install

```bash
dart pub global activate impact_analyzer_cli
```

Or run it from source without installing:

```bash
dart run impact_analyzer_cli:impact analyze --path .
```

## Commands

### `impact analyze`

```bash
# Working tree
impact analyze --path .

# Only staged work, two hops deep
impact analyze --scope staged --depth 2

# Commit range
impact analyze --base main --head HEAD
```

| Flag | Default | Meaning |
|---|---|---|
| `-p, --path` | `.` | Repository path |
| `--scope` | `all` | `all`, `staged` or `unstaged` |
| `--base` | — | Base ref for a commit range |
| `--head` | `HEAD` | Head ref for a commit range |
| `-d, --depth` | unlimited | Max transitive depth |
| `--json` | off | Emit the full report as JSON |
| `--fail-on` | — | Exit `3` if severity >= threshold |

### `impact plan`

Estimate the impact of a plan **before** applying it. Accepts structured JSON
or freeform markdown, so an agent's plan can be pasted verbatim.

```bash
impact plan --file plan.md
echo "$PLAN" | impact plan --stdin
```

| Flag | Default | Meaning |
|---|---|---|
| `-p, --path` | `.` | Repository path |
| `-f, --file` | — | Plan file, markdown or JSON |
| `--stdin` | off | Read the plan from stdin |
| `-d, --depth` | unlimited | Max transitive depth |
| `--json` | off | Emit JSON |
| `--fail-on` | — | Exit `3` on threshold |

### `impact serve`

Start the local dashboard.

```bash
impact serve --path . --port 7788
```

| Flag | Default | Meaning |
|---|---|---|
| `-p, --path` | `.` | Repository path |
| `-P, --port` | `7788` | HTTP port, loopback only |
| `--json` | off | Print startup details as JSON |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Analysis error |
| `2` | Usage error |
| `3` | Severity met or exceeded `--fail-on` |

`--fail-on` is what makes this usable as a CI gate:

```yaml
- run: impact analyze --scope staged --fail-on high
```

## Related packages

- [`impact_analyzer`](https://pub.dev/packages/impact_analyzer) — the engine
- [`impact_analyzer_dashboard`](https://pub.dev/packages/impact_analyzer_dashboard) — the UI `serve` starts

## License

MIT — see [LICENSE](LICENSE).