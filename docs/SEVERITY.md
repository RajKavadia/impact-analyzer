# Severity Model — Impact Analyzer (Dart Only)

## 1. Intent

Provide a **heuristic** blast-radius score so developers and agents can triage risk quickly. Severity is **not** a proof of breakage.

## 2. Bands

| Band | Score range | Meaning |
|---|---|---|
| `low` | 0.00 – 0.24 | Small local change; few dependents |
| `medium` | 0.25 – 0.49 | Moderate fan-out; review dependents |
| `high` | 0.50 – 0.74 | Wide file/class impact or public API touch |
| `critical` | 0.75 – 1.00 | Very wide blast radius and/or core UI/public API |

## 3. Primary signals

| Signal | Symbol | Default weight | Notes |
|---|---|---|---|
| Impacted file count | `F` | 1.0 | Direct + transitive files |
| Impacted class/type count | `C` | 1.5 | Classes, enums, mixins, extensions |
| Public API hits | `P` | 2.0 | Changed/impacted public `lib/` API |
| Flutter UI roots | `U` | 1.5 | Widget/State (and configured roots) |
| Max graph depth reached | `D` | 0.5 | Deeper fan-out → higher risk |
| Impacted tests | `T` | 0.25 | Informative; slight increase |

## 4. Normalization (v1 formula)

Use saturating normalization so huge repos do not always pin to critical:

```
f = min(F / 25, 1.0)
c = min(C / 15, 1.0)
p = min(P / 5, 1.0)
u = min(U / 5, 1.0)
d = min(D / 5, 1.0)
t = min(T / 10, 1.0)

raw =
  1.0*f + 1.5*c + 2.0*p + 1.5*u + 0.5*d + 0.25*t

score = clamp(raw / 6.75, 0, 1)   # 6.75 = sum of weights
```

Weights and denominators are configurable via `impact.yaml`.

## 5. Rationale strings

Every report includes human-readable reasons, e.g.:

- `11 impacted classes (weight 1.5)`
- `2 public API hits`
- `4 Flutter UI root types in impact set`
- `transitive depth 4`

Agents should surface these, not only the band.

## 6. Confidence (separate from severity)

| Confidence | When |
|---|---|
| `high` | Analyzer succeeded; paths explicit; few ignores skipped |
| `medium` | Plan inferred from free text; or partial analyzer warnings |
| `low` | Missing package config; many unresolved URIs; truncated graph |

Rules of thumb:

- Free-text plan without clear `lib/**/*.dart` paths → confidence ≤ medium
- Analyzer context failure → confidence low; severity may still be estimated from imports only

## 7. Class-count focus

Product requirement: severity reflects **how many class/type files could be impacted**.

Implementation detail:

- Prefer counting **impacted types** (`impactedClassCount`) over raw LOC
- A file with 3 impacted classes contributes 3 toward `C`, not 1
- Top-level functions without enclosing type count as 0.5 equivalent (optional v1.1)

## 8. Flutter-specific bumps

When an impacted/changed type is assignable to (or named like configured roots):

- `Widget`, `StatefulWidget`, `StatelessWidget`, `State`
- Optional config list: `Notifier`, `Cubit`, `Bloc`, `Provider`, etc.

Each unique matching type increments `U`.

## 9. What severity must not claim

- “This will break production”
- “All listed files need edits”
- “Tests will fail”

Preferred language: *potential static blast radius*.

## 10. CLI / CI gating

Optional:

```bash
impact analyze --fail-on high
```

Exit `3` when band ≥ threshold. Default off for local DX.
