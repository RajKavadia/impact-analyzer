# Analysis — Impact Analyzer (Dart Only)

## 1. Verdict

**Feasible for Dart/Flutter v1.** The combination of git diffs, `package:analyzer`, MCP, and a local dashboard is well within the Dart ecosystem. The main product risk is differentiation and severity trust — not basic technical viability.

## 2. Problem statement

AI agents and humans change Dart code without a cheap, trustworthy view of blast radius. Line diffs show *what changed*; they do not show *what else may break*. Flutter apps amplify this: widgets, state, and routing create wide fan-out from small edits.

## 3. Why Dart-only first

| Reason | Detail |
|---|---|
| Accuracy | `package:analyzer` gives real elements/references; multi-language needs many parsers |
| Audience | Explicit target: Flutter developers |
| Speed to value | One language → ship MCP + dashboard sooner |
| Honest scope | Avoid claiming “any repo” semantic impact too early |

Non-Dart files in a Flutter repo can still appear in git change lists as informational, without expanding the symbol graph.

## 4. Prior art (landscape)

| Project | Overlap | Gap we can fill |
|---|---|---|
| Official `dart mcp-server` | Analyzer/runtime tools | Not change/plan blast-radius focused |
| `dart_context_mcp` | Symbol lookup, impact, dependency graph | Less emphasis on git WIP + plan preflight + dashboard product |
| Generic code-impact MCPs | Blast radius / risk scores | Not Dart-native; weaker Flutter semantics |
| IDE refactor previews | Local symbol refs | Not agent/MCP + plan + severity productized |

**Differentiation thesis:** *git working-tree + AI-plan preflight + severity UX + local dashboard*, all sharing one Dart-native report model.

## 5. Technical feasibility by capability

| Capability | Rating | Notes |
|---|---|---|
| Uncommitted changes | High | git porcelain/diff |
| Commit range | High | `git diff base...head` |
| File-level impact | High | import graph |
| Class/symbol impact | High–Medium | analyzer; line-hunk precision is extra work |
| Impact graph viz | High | JSON graph → web renderer |
| AI plan analysis | Medium–High | Structured plans easy; free text ambiguous |
| MCP tools | High | stdio MCP pattern established |
| Severity by class/file counts | Medium | Heuristic; needs transparent rationale |
| Stunning dashboard | High | UX effort, not a blocker |
| pub.dev packages | High | Standard Dart packaging |

## 6. Architecture trade-offs

### 6.1 Analyzer vs regex

- **Chosen:** `package:analyzer`
- **Why:** Correct element model; worth the startup cost
- **Mitigation:** Cache analysis contexts; analyze changed + dependent set, not always whole world naively

### 6.2 Monorepo surfaces

- **Chosen:** core + cli + mcp + dashboard packages
- **Why:** Independent publish/version; single scoring brain
- **Cost:** Slightly more packaging boilerplate

### 6.3 Dashboard stack

- **Chosen (planned):** Dart HTTP server + web UI (static SPA or Flutter web)
- **Default lean:** shelf/Dart Frog + HTML/CSS/JS graph for faster polish iteration
- **Alternative:** Flutter web if team prefers one language for UI

### 6.4 LLM inside core?

- **Chosen for v1:** No required LLM in core
- **Why:** Deterministic, offline, testable
- **Agent host** may structure plans before calling MCP

## 7. Severity model risks

Counting impacted classes is useful but can:

- Over-rank barrel `export` churn
- Under-rank tiny changes to critical singletons
- Ignore reflection / dynamic invocation
- Noise from generated code if not ignored

**Mitigations:** ignores, public-API weighting, confidence score, rationale strings (see SEVERITY.md).

## 8. Security & trust

- MCP tools must be **read-only**
- Dashboard binds to localhost by default
- Do not exfiltrate source to remote services in v1
- Treat plan text as untrusted input (path traversal checks)

## 9. Effort estimate (indicative)

| Phase | Effort |
|---|---|
| Docs (this) | 1 day |
| Core + CLI MVP | 1–2 weeks |
| MCP | 3–5 days |
| Dashboard MVP | 1 week |
| Visual polish + hardening | 1 week |

Single experienced Dart engineer, assuming fixture-driven development.

## 10. Open questions (non-blocking)

1. Melos vs plain pub workspace — default to pub workspace unless melos already preferred.
2. Flutter web vs static SPA for dashboard — default static SPA for graph libraries.
3. Exact Dart SDK lower bound — set at scaffold to current stable.

## 11. Recommendation

Proceed with **Phase 0 complete → Phase 1 scaffold + core**. Keep messaging strictly **Dart/Flutter impact analysis**. Revisit multi-language only after MCP + dashboard prove the report model.
