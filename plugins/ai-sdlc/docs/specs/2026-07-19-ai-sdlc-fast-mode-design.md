# AI-SDLC Fast Mode + Retro Jira Reconciliation — Design

**Status:** Design (2026-07-19).
**Author:** Maor + Claude
**Related:** `2026-07-08-ai-sdlc-hybrid-artifact-store-design.md` (the enabler — spec detail already lives in git), `sdlc-conventions` skill (Artifact Discipline), the "Hotfix Pattern" in `commands/sdlc.md` (the precedent — skip-Jira-then-reconcile for one fix).

## Problem

The pipeline uses **Jira as the message bus**. Every phase hands off by transitioning a ticket
(Backlog → Selected for Development → In Progress → In Review → Testing → Done) and posting a `## Summary`
comment; the defect loop works by minting a child Bug issue and flipping the parent Story to In Progress.
Robust, PM-visible — but **slow**. Each per-story agent does one `jira_get_issue` at start and one
`jira_add_comment` + `jira_transition_issue` batch at the end, and on a wide wave those Jira MCP
round-trips dominate wall-clock.

Sometimes the user is driving a small, live session and does not need PM-visible Jira state *during* the
build — they want speed, and can decide *afterward* whether the wave is worth a Jira audit trail.

## The two enablers (already in the codebase)

1. **Hybrid artifact store** (shipped 2026-07-09). All spec *detail* — tech specs, CUJs, names-reserved,
   design specs, integration notes — already lives in local git files under `docs/sdlc/{KEY}/*.md`. Jira
   comments are only a `## Summary` + a pointer. So the *content* the pipeline needs is already in git;
   Jira holds *state + a cheap snapshot*.
2. **Hotfix Pattern** (`commands/sdlc.md`). For a single small fix the orchestrator already spawns the
   bug-fixer directly, skips upfront Jira ceremony, runs the verification gates, and **reconciles Jira
   afterward** (creates a Bug ticket back-dated, moves it to Done). Fast mode generalizes this from one
   fix to a whole wave of stories.

Given (1), fast mode is mostly *subtractive*: stop writing the Jira summary + transition (the detail is
already in git), and replace the Jira **status** signal with an orchestrator-held ledger.

## Decided design (fixed requirements)

- **Scope = "Jira only, keep all gates."** Fast mode skips *only* the Jira ceremony: no ticket creation,
  no status transitions, no summary comments, no Bug issues. It keeps **every** engineering gate — planner,
  plan-challenger, architect, designer, integrator, developer, tester (incl. smoke-path artifact +
  live-process E2E gates), QA reviewer, bug-fixer, Phase 7.5 PR merge. Same rigor; less latency.
- **Retro reconciliation = "full hierarchy, back-filled," opt-in per wave.** When a wave finishes (all
  units Done + merged), the orchestrator *asks* whether to mint Jira. On yes it recreates the normal
  QBV → Epic → Story(→ Bug) hierarchy with summary comments + git spec pointers + PR links, each ticket
  walked to its recorded final status.
- **Trigger = "always offer + recommend."** Every run the orchestrator recommends fast vs normal with a
  one-line rationale; the user picks. `--fast` / `--normal` may pre-answer; `--auto` takes the
  recommendation without pausing.

## Coordination model

### The `Jira:` context axis (not a new `Mode:`)

Every agent already parses `Self-Learning: ON|OFF` from the SDLC Context block. Fast mode adds a parallel
axis: **`Jira: on|off`**.

**Why a separate axis and not `Mode: fast`:** the QA reviewer already has a `Mode: fast` field meaning
"lightweight review — skip skill loading + test re-run." That is an *orthogonal* concern (how heavy the
gate is), not *whether Jira is used*. Overloading `Mode: fast` would conflate the two. So the coordination
switch is `Jira: on|off`; QA's `Mode: fast` is untouched and the two combine freely.

**Default:** absent `Jira:` line ⇒ `Jira: on` (normal). Every existing agent behaves exactly as before
until the orchestrator sends `Jira: off`. This is what makes steps 2–4 of the rollout inert until step 5.

### The Fast Work Ledger (replaces Jira status as the message bus)

The orchestrator holds a **ledger** — the machine-readable state of the wave — in two places:

- **In the resume file** as a `## Fast Work Ledger` block (fast-resume reads it).
- **Committed to git** at `docs/sdlc/_wave-{WAVE-ID}/ledger.md` on the base branch (durable copy; survives
  loss of the memory file; readable by `--docs` and reconciliation).

One entry per work unit:

```yaml
- key: CSI-F1                    # synthetic key (see below)
  title: <story title>
  epic: <epic title>             # groups units under an epic for reconciliation
  ac: [ <criterion>, ... ]
  complexity: S|M|L
  deps: [ CSI-F2, ... ]          # blocking work-unit keys
  phase: architected|ready|in-progress|in-review|testing|done|blocked
  branch: CSI-F1/<slug>
  pr: <url or null>
  spec_files: [ docs/sdlc/CSI-F1/tech-spec.md, ... ]
  bugs:                          # defect loop — replaces child Bug issues
    - id: CSI-F1-B1
      summary: <one-line failure + failing test>
      source: tester|qa|user
      status: open|fixed
      loop: 1                    # bug-fix loop counter; cap 3
  verdicts:
    test: PASS|FAIL|null
    qa: APPROVED|ISSUES|null
  jira: null                     # real Jira key, filled at reconciliation
```

The orchestrator updates the ledger from each agent's **return text**. Agents no longer post status to
Jira; they return their verdict/branch/PR/bug-report in their ≤10-line summary and write their detail
artifact to a git file (see per-agent behavior). The return text IS the message-bus signal.

### Synthetic work-unit keys

Without jira-creator to mint keys, work units are named **`{PROJECT}-F{n}`** (`F` = fast; e.g. `CSI-F1`).

- **Collision-free:** real Jira keys are always `{PROJECT}-{integer}`; `{PROJECT}-F{integer}` can never be
  a real key.
- **Drop-in:** `docs/sdlc/CSI-F1/`, branch `CSI-F1/{slug}`, worktree `{repo}.worktrees/CSI-F1` — the exact
  existing conventions, no code path cares whether the key is real.
- **Back-mappable:** the ledger's `jira:` field records `CSI-F1 → CSI-1234` once reconciliation mints the
  real ticket.

The wave gets a **`WAVE-ID` = `{PROJECT}-W{YYYYMMDD-HHMMSS}`**. The orchestrator stamps it once at wave
start (agents/scripts can't call `date` deterministically). It names the resume file and the wave dir.

### The plan / AC source (no jira-creator)

In normal mode the developer reads story description + AC from the Jira story. In fast mode the orchestrator
writes the approved plan to `docs/sdlc/_wave-{WAVE-ID}/plan.md`, one section per work unit
(`## CSI-F1 — <title>` → description, acceptance criteria, complexity, deps). Every per-story agent reads
its unit's section from that local file instead of `jira_get_issue`. The ledger is the machine state;
`plan.md` is the human-readable requirements source.

### Wave directory layout

```
docs/sdlc/
  _wave-{WAVE-ID}/
    plan.md          # requirements: one section per work unit
    ledger.md        # machine state (committed copy)
  CSI-F1/            # per-unit artifacts (same as normal, synthetic key)
    tech-spec.md  names-reserved.md  design-spec.md  integration-notes.md
    impl-complete.md  test-results.md  qa-review.md  bug-fix-CSI-F1-B1.md
  CSI-F1/cujs.md  ... (cujs live under the wave's "epic" — for fast mode, under _wave dir or a nominal epic unit)
```

## Per-agent fast-mode behavior

Each per-story agent (architect, developer, tester, qa-reviewer, bug-fixer, integrator, designer) gets a
`## Fast Mode (Jira: off)` section. When `Jira: off`:

1. **Skip the startup `jira_get_issue`.** Read the unit's description + AC from
   `docs/sdlc/_wave-{WAVE-ID}/plan.md` (its `## {KEY}` section). Read sibling detail from the local
   `docs/sdlc/{KEY}/*.md` files — already the hybrid-store default.
2. **Skip all Jira writes** (`jira_transition_issue`, `jira_add_comment`, `jira_create_issue`) and **load
   no `mcp__mcp-atlassian__*` tools** — skip the mandatory startup ToolSearch entirely (saves latency +
   tokens).
3. **Write the summary artifact to a git file** instead of a Jira comment:

   | Agent | Fast-mode artifact file |
   |---|---|
   | architect | `docs/sdlc/{KEY}/tech-spec.md`, `names-reserved.md`, `cujs.md` — *already git; just drop the Jira comment* |
   | designer | `docs/sdlc/{KEY}/design-spec.md` — *already git* |
   | integrator | `docs/sdlc/{KEY}/integration-notes.md` — *already git* |
   | developer | `docs/sdlc/{KEY}/impl-complete.md` |
   | tester | `docs/sdlc/{KEY}/test-results.md` |
   | qa-reviewer | `docs/sdlc/{KEY}/qa-review.md` |
   | bug-fixer | `docs/sdlc/{KEY}/bug-fix-{bug-id}.md` |

4. **Return the verdict in the return text** — the orchestrator parses this to update the ledger + route:
   ```
   Status: <phase>            # architected | ready | in-review | testing | done | blocked
   PR: <url or n/a>
   Verdict: PASS|FAIL|APPROVED|ISSUES|n/a
   Bug: <one-line summary + failing test>   # only on FAIL/ISSUES
   ```

Everything else the agent does (worktree, code, TDD, tests, smoke artifacts, live-process gates, PR) is
**identical** — those are git/file-based already.

### Failure loop without Bug issues

- Tester/QA return a `Bug:` block instead of creating a Jira Bug.
- The orchestrator appends it to the unit's `bugs[]` (id `{KEY}-B{n}`, `loop: n`), and spawns
  `sdlc-bug-fixer` with `Jira: off`, the failure detail, the parent work-unit key, and the shared worktree.
- The bug-fixer writes `bug-fix-{bug-id}.md`, returns `Fixed: {bug-id}`; the orchestrator marks the bug
  `fixed` and re-routes the unit to Phase 5 (re-test).
- **Max-3-loops cap unchanged** — counted from `bugs[].loop` in the ledger instead of closed child Bugs.
  On the 3rd failure the unit is marked `blocked` and surfaced to the user.

## The offer / recommendation gate

**Where:** after plan approval — **end of Phase 1.5** — because plan size/shape informs the recommendation.
For feedback-loop / hotfix entries (small delta on an existing repo, no full plan phase), offer it **up
front** in Phase 0, before anything would be created.

**Recommend FAST when most hold:**
- Small wave (≤ ~5 stories) OR a feedback-loop / hotfix delta.
- The user is actively driving the session (not a background `/sdlc continue`).
- No stated need for live PM visibility *during* the build (reconcile after suffices).

**Recommend NORMAL when:** large multi-epic project, multiple stakeholders tracking Jira live, or the user
asked for full traceability throughout.

**Prompt (shown once):**
```
Recommended: FAST mode — {rationale, e.g. "3-story feedback delta, you're driving live"}.
Fast mode skips Jira during the build (same tests, QA, and gates) and offers to create the
tickets in retrospect when the wave finishes.
  [f] Fast (recommended)   [n] Normal (Jira as we go)
```

**Flag interaction:**
- `--fast` / `--normal` pre-answer the gate (no pause).
- `--auto` takes the *recommended* option automatically and logs it (consistent with every other `--auto`
  gate). `--fast --auto` ⇒ fast, no prompt. `--normal` overrides the recommendation.

## Retro reconciliation — Phase 8.5 (opt-in)

Runs at wave completion (all units `done`, PRs merged), **after** Phase 8's CUJ replay, **before** the
final report.

**Gate (ask once):**
```
Wave complete. Create the Jira tickets in retrospect
(full QBV → Epic → Story hierarchy, each moved to its final status)?
  [y] yes   [n] no, leave it in git only
```
`--auto` ⇒ yes.

**Driver:** reuse **`sdlc-jira-creator` with `Mode: reconcile`**. The orchestrator passes the ledger +
`plan.md` + committed `docs/sdlc/` paths + PR urls + `Repo Web Base`. The agent:

1. Creates QBV → Epics → Stories as today (Steps 3–6), but each Story description carries the real spec
   pointer (`{Repo Web Base}/blob/{base_branch}/docs/sdlc/{KEY}/tech-spec.md`) and the PR link.
2. For each unit with `bugs[]`, creates the child Bug issues (final status Done).
3. Posts each phase's `## Summary` comment by reading the local artifact file's summary
   (`impl-complete.md`, `test-results.md`, `qa-review.md`) — assembling, not re-deriving.
4. **Walks each ticket to its recorded final status.** A freshly-created issue lands in Backlog/To Do;
   Jira will not jump straight to Done. The agent walks the transition chain
   (Backlog → Selected → In Progress → In Review → Testing → Done) using the Transition Map.
   **Caveat:** some workflows forbid skip/backward transitions — the agent leaves the ticket at the
   furthest reachable status and notes it; it does **not** fail the wave over a stuck transition.
5. Records `synthetic → real` in the ledger `jira:` field and returns the mapping.

**Idempotency:** the agent's existing label-based dedupe (Step 2) makes a re-run safe — an existing
QBV/epic is reused, not duplicated.

**Synthetic-dir rename (decided: NO).** After reconciliation the `docs/sdlc/{PROJECT}-F{n}/` dirs are
**left as-is**. PRs and branches already reference the synthetic key; a mass rename would rewrite paths the
merged PRs point at and muddy git history. The `synthetic → real` mapping is recorded in the ledger and in
a `## Reconciliation` comment on the epic, which is enough to trace a real key back to its artifacts.

## Resume in fast mode

Fast runs have no Jira epic key, so `/sdlc continue` keys off the **wave id**:

- Resume file: `~/.claude/projects/-Users-maorb-git-dev/memory/sdlc-resume-{WAVE-ID}.md` (same dir, wave id
  instead of epic key). Adds a `## Wave` block (`id`, `project`, `mode: fast`, `plan_file`,
  `reconciled: false|<QBV-KEY>`) and a `## Fast Work Ledger` block.
- `/sdlc continue {WAVE-ID}` (or bare — pick the most recent unreconciled wave) → Phase 0 fast-resume reads
  the ledger from the resume file, falling back to `docs/sdlc/_wave-{WAVE-ID}/ledger.md` if the memory file
  is gone. Routing uses each unit's ledger `phase` — **no verification JQL** (there are no tickets).
- After reconciliation the wave gains a real epic key; `## Wave.reconciled` records it and the epic key
  resumes normally thereafter (normal-mode routing).

## Self-learning & docs interplay

- **Self-learning is orthogonal and unaffected.** The `Self-Learning: ON|OFF` axis is independent of
  `Jira: on|off`. Agents still emit `## Lessons` when ON; the capture hooks read agent *return text*, not
  Jira, so nothing changes. Drain/extractor loop runs the same. A fast-mode lesson may target the ledger or
  a `_wave-*` file — fine.
- **`--docs` (Phase 7.7) still works.** The documenter reads local `docs/sdlc/{KEY}/*.md`, which exist in
  fast mode. It can run before or after reconciliation. If run before reconciliation, the Confluence
  link-back comment (which needs a Jira epic) is deferred to reconciliation or skipped with a note.

## Rollout (independently shippable)

1. ⏳ This design doc.
2. ⏳ `sdlc-conventions` — define the `Jira: on|off` axis, `{PROJECT}-F{n}` key scheme, ledger schema,
   per-agent fast artifact files, wave-dir layout; `workflow-states.md` ledger-phase ↔ Jira-status table.
3. ⏳ Per-agent `## Fast Mode` sections (architect, developer, tester, qa-reviewer, bug-fixer, integrator,
   designer). Inert until the orchestrator sends `Jira: off`.
4. ⏳ `sdlc-jira-creator` `## Reconcile Mode` section.
5. ⏳ Orchestrator wiring (`commands/sdlc.md`): flags, offer gate, fast-path routing, Phase 8.5, resume
   schema.
6. ⏳ Repo `CLAUDE.md` + `README.md`.

Each step ships alone: normal mode is untouched until step 5 wires the offer; agents default `Jira: on`.

## Smoke tests (before build sign-off)

| # | Test | Expected |
|---|---|---|
| F1 | `/sdlc "small 2-story feature"` | Offer fast/normal with rationale; pick fast |
| F2 | Architect `Jira: off` | Writes tech-spec/cujs to git; **no** Jira comment; no MCP calls |
| F3 | Developer `Jira: off` | Reads AC from `_wave-*/plan.md`; opens PR; writes `impl-complete.md`; returns `PR:`+`Status:` |
| F4 | Tester failure path | Returns a `Bug:` block; orchestrator records ledger `bugs[]`, spawns bug-fixer; no Jira Bug |
| F5 | Bug loop cap | 3 failed loops → unit `blocked`, surfaced |
| F6 | Ledger persistence | `ledger.md` committed to base; `## Fast Work Ledger` in resume file |
| F7 | Resume | `/sdlc continue {WAVE-ID}` restores ledger, routes remaining units, no JQL |
| F8 | Reconciliation | On `y`: QBV→Epic→Story(→Bug), each walked to Done, pointers+PR links present; map recorded |
| F9 | Reconcile idempotency | Re-run creates no duplicates (label dedupe) |
| F10 | `--docs` in fast mode | Documenter assembles from local files, no Jira dependency |
| F11 | Normal-mode regression | A run with no `Jira:` line behaves exactly as before |

## Tradeoffs

- **Kept:** every engineering gate + the ability to reconstruct full Jira history on demand.
- **Cost:** an orchestrator-held ledger to maintain; a reconcile phase whose status-walk may stall on
  restrictive workflows; the ledger is the single point of truth during a fast run (mitigated by the
  git-committed copy).
- **Rejected — lean mode (skip QA/design too):** the user chose "keep all gates"; rigor is not the thing to
  trade for speed. **Rejected — reconcile as lightweight single epic:** the user chose full back-filled
  hierarchy for a faithful audit trail. **Rejected — flag-only trigger:** the user chose always-offer +
  recommend so the choice is explicit every run.
