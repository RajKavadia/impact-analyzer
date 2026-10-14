# impact_analyzer_dashboard

Local, loopback-only web dashboard for Impact Analyzer reports: severity hero,
impact graph, file tables and an AI plan lab.

Uses [`impact_analyzer`](https://pub.dev/packages/impact_analyzer) as its
engine, so the dashboard and the CLI can never disagree.

## Usage

From this package:

```bash
dart run impact_analyzer_dashboard:impact_serve --path /path/to/repo --port 7788
```

Or through the CLI, which wraps this package:

```bash
dart pub global activate impact_analyzer_cli
impact serve --path . --port 7788
```

Then open <http://127.0.0.1:7788>.

The server binds `127.0.0.1` only and makes no outbound calls. All browser
libraries are vendored locally.

## Five graph representations

An impact graph is a small, sparse directed acyclic graph over file
dependencies. A force-directed layout renders that as an unreadable blob, so
there are five views over the same payload:

| View | Engine | Question it answers |
|---|---|---|
| **Layered** (default) | Cytoscape `breadthfirst` | What breaks, and in what order? |
| **Sugiyama** | Eclipse ELK `layered` | Same, with edge crossings minimised |
| **Rings** | concentric placement | How far does the blast radius reach? |
| **Matrix** | files x files grid | Which files reference which, at scale? |
| **Tree** | directory outline | What is in scope, by directory? |

Switch in the panel head, or deep-link with `#layered`, `#sugiyama`, `#rings`,
`#matrix`, `#tree`.

## API

The dashboard is also the machine-readable surface for agents.

```
GET  /api/health
GET  /api/impact/working-tree
GET  /api/impact/range
POST /api/impact/plan
GET  /api/impact/summary
GET  /api/impact/graph
GET  /api/contract
```

`/api/contract` self-documents the whole surface — paths, query parameters,
error codes and severity bands — so an agent can discover it without reading
any source.

`GET /api/impact/summary` is the token-cheap projection: counts and severity
without the file lists. `GET /api/impact/graph` returns
`{ nodes, edges, truncated }` and always reports truncation explicitly, so a
capped graph is never mistaken for a complete one.

## Programmatic use

```dart
import 'package:impact_analyzer_dashboard/impact_analyzer_dashboard.dart';

final server = DashboardServer(rootPath: '/path/to/repo', port: 7788);
await server.start();
```

## Third-party assets

Vendored under `web/vendor/` so the dashboard makes no outbound calls:

| Asset | License |
|---|---|
| `cytoscape.min.js` | MIT |
| `elk.bundled.js` (Eclipse ELK) | EPL-2.0 OR GPL-3.0-or-later |

## Related packages

- [`impact_analyzer`](https://pub.dev/packages/impact_analyzer) — the engine
- [`impact_analyzer_cli`](https://pub.dev/packages/impact_analyzer_cli) — `impact serve`

## License

MIT — see [LICENSE](LICENSE).