## 0.1.0

Initial release.

- `impact analyze` — working-tree, `--scope staged` / `--scope unstaged`, and
  commit-range analysis via `--base` / `--head`.
- `impact plan` — AI-plan preflight from `--file` or `--stdin`, accepting either
  structured JSON or freeform markdown.
- `impact serve` — starts the loopback dashboard from
  `impact_analyzer_dashboard`.
- `--depth` to cap transitive expansion, `--json` for machine-readable output.
- `--fail-on low|medium|high|critical` exits `3` when severity meets the
  threshold, making the CLI usable as a CI gate.
- Exit codes: `0` success, `1` analysis error, `2` usage error, `3` severity
  threshold met.