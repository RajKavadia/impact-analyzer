## 0.1.0

Initial release.

**Status: scaffold.** The MCP stdio server is declared but not implemented. The
`impact_mcp` executable does not exist in this release and no tools are
callable. The package is published to reserve the name and document the
planned tool surface.

Planned for a later release, per the specification in `docs/MCP.md`:

- JSON-RPC 2.0 framing over stdio
- `analyze_working_tree`, `analyze_commit_range`, `analyze_plan`,
  `get_impact_summary`, `get_impact_graph`
- Read-only tools with an explicit `rootPath` argument
- Responses aligned with `ImpactReport` from `impact_analyzer`