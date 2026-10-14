# Graph Views — Impact Analyzer Dashboard

How the dashboard turns one `ImpactReport.graph` payload into five different
visual representations, and why.

---

## 1. The problem this solves

The first version of the dashboard drew the impact graph with Cytoscape's
`cose` force-directed layout. It produced a blob:

- labels rendered at ~16px regardless of node size, because `cose` zooms to
  fit and Cytoscape label font-size is in fixed pixels
- nodes piled into the centre with overlapping labels
- the single test file floated far away, attached by one long edge

That is not a bug in the layout, it is the wrong layout. An impact graph is a
**small, sparse, directed acyclic graph** over **file** dependencies. A
force simulation is the wrong tool: it optimises for compactness, not for
showing tiers, direction or containment.

Two other problems compounded it:

- **Symbol nodes dominated.** A 6-file change set carried 6 symbol nodes, and
  the symbols crowded out the files, which are the thing a reader actually
  navigates by.
- **One representation cannot answer every question.** "How far does this
  reach?" and "which files reference each other?" are different questions and
  want different pictures.

The fix was to drop force layout entirely and ship five representations of the
same data.

---

## 2. The five views

All five render the identical payload from `GET /api/impact/working-tree`.
Nothing is recomputed per view except presentation.

| View | Engine | The question it answers |
|---|---|---|
| **Layered** (default) | Cytoscape `breadthfirst` | What breaks, and in what order? |
| **Sugiyama** | Eclipse ELK `layered` | Same, with edge crossings minimised |
| **Rings** | manual concentric placement | How far does the blast radius reach? |
| **Matrix** | plain DOM grid | Which files reference which, at scale? |
| **Tree** | plain DOM outline | What is in scope, by directory? |

### 2.1 Layered (default)

Cytoscape `breadthfirst`, `directed: true`, rooted at the changed files, so
each tier is one more hop away from the change.

```js
{
  name: 'breadthfirst',
  directed: true,
  roots: <changed file ids>,
  nodeDimensionsIncludeLabels: true,
  nodeSeparation: 70,
  spacingFactor: 1.7,
  padding: 40,
  avoidOverlap: true,
  fit: true,
  animate: false
}
```

### 2.2 Sugiyama

Same DAG through [elkjs](https://github.com/kieler/elkjs) `0.12.0`,
vendored locally as `web/vendor/elk.bundled.js`:

```js
'elk.algorithm': 'layered',
'elk.direction': 'RIGHT',
'elk.layered.crossingMinimization.strategy': 'LAYER_SWEEP',
'elk.layered.nodePlacement.strategy': 'BRANDES_KOEPF'
```

Worth it once a change set reaches ~15 files, where `breadthfirst` starts
producing crossing edges. Positions are applied through the Cytoscape API:

```js
result.children.forEach(function (c) {
  cy.getElementById(c.id).position({ x: c.x + c.width / 2, y: c.y + c.height / 2 });
});
```

If `elk.bundled.js` fails to load, the view falls back to `breadthfirst` and
says so in the status line rather than rendering nothing.

### 2.3 Rings

Changed files orbit the origin; hop 1 sits on the first ring, hop 2 on the
second, up to four rings. Rings past four are folded into the outermost ring
and coloured the same, because a fifth ring is not adding information.

Ring radii are **computed, not fixed**, from two constraints:

```js
var needed = (count * (widest + 56)) / (2 * Math.PI);   // circumference
var radius = Math.max(needed, widest + 70, 175 + (ring - 1) * 225);
```

The circumference term stops adjacent nodes touching; the `widest + 70` term
stops nodes on opposite sides colliding across the squashed vertical axis
(rings are squashed to `0.78` to fit the panel).

### 2.4 Matrix

An `N x N` files-by-files grid. Row `i`, column `j` is the cell for
`file i imports file j`, with opacity scaled by reference count.

This is the view that scales. A 40-file change set is 1600 cells and stays
perfectly readable, whereas no force or layered layout survives it. Cells carry
the full `from -> to (n refs)` detail in their tooltip.

Rows are sorted by blast depth then path, so hot files land in the top-left
corner where the eye starts.

### 2.5 Tree

A collapsible directory outline. Folder badges carry rolled-up counts
(`3 changed`, `2 impacted`) so a collapsed folder still reports its weight.
Leaves carry a blast-depth colour dot and the full path in their tooltip.

This view has no layout step at all, so it can never overlap.

---

## 3. Shared index

Every view consumes one normalised structure built by `ImpactViews.index()`
in `web/views.js`:

```js
{
  files:        [...],   // file node ids
  changedFiles: [...],   // seeds, depth 0
  depth:        { id -> hop count },
  fileEdges:    [{ from, to, weight }],
  maxDepth:     number
}
```

### 3.1 Blast depth

Depth is the number of hops from the change set, measured **against** the
import direction. `lib/app.dart` imports `user_model.dart`, so if the model
changes, `app.dart` is one hop away.

Implementation: build a reverse adjacency (`importers[target]` = who imports
`target`) from the `imports` edges, then breadth-first walk it **outward from
the changed files**. Symbol-level `references` edges contribute extra weight
to a file pair but do not create new depth.

```js
importers[e.to].push(e.from);   // importer -> imported, walked backwards
```

If there is no change set at all, every file is seeded at depth 0 so the views
still draw something rather than an empty panel.

### 3.2 Colour encoding

One scale, used by all five views:

| Depth | Colour | Meaning |
|---|---|---|
| 0 | `#58a6ff` blue | changed |
| 1 | `#f2545b` red | one hop away, direct impact |
| 2 | `#f0883e` orange | two hops |
| 3 | `#d9a441` yellow | three hops |
| 4+ | `#6e7681` grey | four or more |

The legend strip under the panel head always shows this scale, so the colour
meaning is never left to memory.

---

## 4. Gotchas worth knowing

These cost real debugging time and will bite again.

### 4.1 `maximal: true` crashes this Cytoscape build

```js
layout: { name: 'breadthfirst', maximal: true }
// TypeError: Cannot read properties of undefined (reading 'depth')
```

The error names a `depth` property that does not exist on the element
Cytoscape is reading. `maximal` is only meaningful together with `circle: true`,
which this dashboard does not use. Do not re-add it.

### 4.2 Do not use `mapData` on a field some elements lack

`mapData(depth, 0, 4, ...)` throws when blast depth is absent on any node, and
depth only exists for **file** nodes. All sizes and colours are resolved in
JavaScript instead (`labelWidth()`, `depthColor()`) and passed in as
`data(w)`, `data(h)`, `data(bg)`.

### 4.3 Nodes must be sized to their labels

Cytoscape cannot auto-fit a node box to its text, and the tiered layouts put
nodes on a grid, so a fixed 30px box makes labels spill over their neighbours.
`labelWidth()` estimates the box from the label, and
`nodeDimensionsIncludeLabels: true` tells the layout to space tiers by the
label bounds rather than the node bounds.

```js
function labelWidth(text) {
  var n = String(text).length;
  return Math.max(38, Math.min(26 + n * 6.0, 230));
}
```

### 4.4 ELK coordinates must go through the Cytoscape API

Mutating the plain element objects passed into `cytoscape({elements})` after
construction has no effect on the rendered graph. Use
`cy.getElementById(id).position(...)`.

### 4.5 Cap zoom on small graphs

`fit: true` zooms in on a 6-node graph, which magnifies fixed-pixel labels.
`maxZoom: 1.6` keeps text at a readable size instead of ballooning it.

---

## 5. Interaction

- **View switcher** in the panel head, plus deep links: `#layered`,
  `#sugiyama`, `#rings`, `#matrix`, `#tree`
- **Selection sync**: clicking a node, a matrix cell or a tree row selects the
  same file in the file tables, and vice versa. `Clear` resets it.
- **File/symbol toggles** apply to the node-link views only. Rings, matrix and
  tree are file-scoped by construction, so the toggles hide themselves.
- **Re-layout** re-runs the current layout; on Sugiyama and Rings it simply
  re-renders, because both are deterministic given the same report.

---

## 6. Vendored dependencies

Kept local so the dashboard stays loopback-only with no outbound calls.

| File | Size | License |
|---|---|---|
| `web/vendor/cytoscape.min.js` | ~364 KB | MIT |
| `web/vendor/elk.bundled.js` | ~1.6 MB | EPL-2.0 OR GPL-3.0-or-later |

To refresh them:

```bash
curl -o packages/impact_analyzer_dashboard/web/vendor/cytoscape.min.js \
  https://cdn.jsdelivr.net/npm/cytoscape@3/dist/cytoscape.min.js
curl -o packages/impact_analyzer_dashboard/web/vendor/elk.bundled.js \
  https://cdn.jsdelivr.net/npm/elkjs@0.12.0/lib/elk.bundled.js
```

---

## 7. Files

| File | Role |
|---|---|
| `web/views.js` | All five views, plus the shared index. ~700 lines, no framework. |
| `web/app.js` | View lifecycle, selection sync, table and plan rendering |
| `web/index.html` | View switcher, legend strip, panel markup |
| `web/styles.css` | Matrix grid, tree outline, switcher and legend styling |

Adding a sixth view means writing one `render(ctx)` function returning either a
Cytoscape instance or `null`, and registering it in the `VIEWS` map. Nothing
else needs to change.