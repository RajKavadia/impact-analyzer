# impact_analyzer_mcp

Model Context Protocol (MCP) stdio server exposing read-only Impact Analyzer
tools to AI agents, so an agent can size blast radius before or after
proposing Dart/Flutter edits.

> **Status: early scaffold. Not usable yet.**
>
> The MCP server is declared but **not implemented**. The `impact_mcp`
> executable referenced below does not exist in this release, and the tools
> listed under [Planned tools](#planned-tools) are not yet callable.
>
> Install [`impact_analyzer_cli`](https://pub.dev/packages/impact_analyzer_cli)
> today for working command-line access to the same engine.

## Planned transport

- Protocol: Model Context Protocol
- Mode: stdio
- Entry point: `impact_mcp`, or `dart run impact_analyzer_mcp:impact_mcp`

Example client configuration:

```json
{
  "mcpServers": {
    "impact-analyzer": {
      "command": "dart",
      "args": ["run", "impact_analyzer_mcp:impact_mcp"],
      "cwd": "/path/to/impact-analyzer/packages/impact_analyzer_mcp"
    }
  }
}
```

## Design rules

1. **Read-only.** No write, format, commit or patch tools in v1.
2. **Explicit root.** Every tool takes `rootPath`.
3. **Compact by default.** Prefer summary tools; full graph on demand.
4. **Same schema.** Responses align with `ImpactReport` from
   [`impact_analyzer`](https://pub.dev/packages/impact_analyzer).

## Planned tools

| Tool | Purpose |
|---|---|
| `analyze_working_tree` | Analyse uncommitted changes |
| `analyze_commit_range` | Analyse a ref range |
| `analyze_plan` | Estimate impact of a plan before editing |
| `get_impact_summary` | Token-cheap counts and severity |
| `get_impact_graph` | `{ nodes, edges, truncated }`, node-capped |

Errors use the shared error contract:

```json
{ "code": "not_dart_project", "message": "No pubspec.yaml found" }
```

## Related packages

- [`impact_analyzer`](https://pub.dev/packages/impact_analyzer) — the engine
- [`impact_analyzer_cli`](https://pub.dev/packages/impact_analyzer_cli) — `impact analyze | plan`
- [`impact_analyzer_dashboard`](https://pub.dev/packages/impact_analyzer_dashboard) — the same API over HTTP

## License

MIT — see [LICENSE](LICENSE).