# Impact Analyzer — Documentation Index

Dart/Flutter-only change impact analysis: working-tree and commit diffs, symbol-level blast radius, AI-plan preflight, MCP tools for agents, and a local dashboard.

## Documents

| Document | Purpose |
|---|---|
| [REQUIREMENTS.md](./REQUIREMENTS.md) | Product goals, users, functional & non-functional requirements |
| [SPECIFICATION.md](./SPECIFICATION.md) | Technical spec: APIs, data models, MCP tools, severity rules |
| [PLAN.md](./PLAN.md) | Phased delivery plan and milestones |
| [TASKS.md](./TASKS.md) | Actionable work breakdown |
| [ANALYSIS.md](./ANALYSIS.md) | Feasibility, risks, competitors, trade-offs |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Package layout, pipelines, components |
| [MCP.md](./MCP.md) | MCP tool contracts for AI agents |
| [SEVERITY.md](./SEVERITY.md) | Severity scoring model |
| [DASHBOARD.md](./DASHBOARD.md) | Local server dashboard UX |
| [GRAPH_VIEWS.md](./GRAPH_VIEWS.md) | The five impact-graph representations and their layout engine quirks |
| [FIXTURE.md](./FIXTURE.md) | Test fixture: why it is generated, how to rebuild it |
| [ROADMAP.md](./ROADMAP.md) | Post-v1 ideas |
| [GLOSSARY.md](./GLOSSARY.md) | Shared terms |

## Scope (v1)

- **In scope:** Dart and Flutter projects only.
- **Out of scope (v1):** Multi-language semantic impact, cloud SaaS, write/mutate MCP tools.

## Quick links

- Package target: publishable Dart packages for Flutter developers.
- Surfaces: core library, CLI, MCP server, local dashboard.
