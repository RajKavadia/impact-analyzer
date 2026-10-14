# MCP Specification — Impact Analyzer (Dart Only)

## 1. Purpose

Expose read-only impact analysis tools to AI agents (Cursor, Claude Desktop, etc.) so they can size blast radius before or after proposing Dart/Flutter edits.

## 2. Transport

- Protocol: Model Context Protocol (MCP)
- Mode: stdio
- Entrypoint (planned): `dart run impact_analyzer_mcp` or compiled `impact_mcp`

### Example Cursor config

```json
{
  "mcpServers": {
    "impact-analyzer": {
      "command": "dart",
      "args": ["run", "impact_analyzer_mcp"],
      "cwd": "/path/to/impact-analyzer/packages/impact_analyzer_mcp"
    }
  }
}
```

## 3. Design rules

1. **Read-only** — no write, format, commit, or patch tools in v1.
2. **Explicit root** — every tool takes `rootPath` (absolute or workspace-relative).
3. **Compact by default** — prefer summary tools; full graph on demand.
4. **Same schema** — responses align with `ImpactReport` from the core library.

## 4. Tools

### 4.1 `analyze_working_tree`

Analyze uncommitted changes.

**Input**

| Field | Type | Required | Description |
|---|---|---|---|
| `rootPath` | string | yes | Dart/Flutter repo path |
| `scope` | string | no | `all` \| `staged` \| `unstaged` |
| `maxDepth` | number | no | Transitive depth |
| `includeGraph` | boolean | no | Default `false` for token savings |

**Output**

- Full or summary `ImpactReport` JSON (graph omitted unless requested).

**Agent use**

- Before finishing a multi-file edit, measure WIP blast radius.

### 4.2 `analyze_commit_range`

**Input**

| Field | Type | Required |
|---|---|---|
| `rootPath` | string | yes |
| `baseRef` | string | yes |
| `headRef` | string | no (default `HEAD`) |
| `includeGraph` | boolean | no |

### 4.3 `analyze_plan`

Estimate impact of an AI plan without applying edits.

**Input**

| Field | Type | Required | Description |
|---|---|---|---|
| `rootPath` | string | yes | |
| `planText` | string | no | Markdown plan |
| `planJson` | object | no | Structured plan (preferred) |
| `includeGraph` | boolean | no | |

At least one of `planText` / `planJson` required.

**Output**

- `ImpactReport` with `mode: "plan"` and confidence notes when paths are inferred.

**Agent use**

- After drafting a plan, call before editing; if severity is `high`/`critical`, narrow the plan or add tests.

### 4.4 `get_impact_summary`

Token-cheap counts + severity.

**Input:** `rootPath`, optional `mode` (`working_tree` default), optional range/plan fields.

**Output example**

```json
{
  "changedFileCount": 3,
  "impactedFileCount": 18,
  "impactedClassCount": 11,
  "severity": "high",
  "score": 0.74,
  "confidence": "medium",
  "topImpactedFiles": [
    "lib/app.dart",
    "lib/src/auth/auth_repository.dart"
  ]
}
```

### 4.5 `get_impact_graph`

**Input:** same targeting as summary + `maxNodes` (default 200).

**Output:** `{ nodes, edges, truncated }`

## 5. Error responses

Tools return MCP error or structured payload:

```json
{
  "code": "not_dart_project",
  "message": "No pubspec.yaml found"
}
```

## 6. Security

- Resolve and normalize `rootPath`; reject escaping the allowed workspace if host provides a sandbox root.
- Do not echo file contents by default (paths + symbols only).
- Optional future flag `includeSnippets` remains off by default.

## 7. Agent playbook (recommended)

1. `get_impact_summary` on working tree.
2. If severity ≥ `high`, `get_impact_graph` or full `analyze_working_tree`.
3. For new work: draft plan → `analyze_plan` → adjust → edit → re-summary.
4. Mention impacted test files when proposing verification steps.
