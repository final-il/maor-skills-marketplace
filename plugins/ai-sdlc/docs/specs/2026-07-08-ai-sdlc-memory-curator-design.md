# AI-SDLC Memory Curator — Design Spec

**Date:** 2026-07-08
**Status:** Design + scaffold, **validated by one live run** against the real SDLC corpus (2026-07-08). The `sdlc-curator` agent works end-to-end: isolated scan → leverage-ranked, evidence-verified, safety-tiered proposal (3 candidates found and applied under approval). The `/sdlc lessons curate` command flow is documented but not yet exercised as a single automated path — the first run was driven manually. Formal smoke suite (below) still to run.
**Scope:** The subtractive half of the self-learning loop. Where `sdlc-lesson-extractor` **adds** rules to the accumulated knowledge under a cost gate, the curator **removes** what is no longer relevant under a safety gate.

> Read alongside `2026-06-10-ai-sdlc-self-learning-design.md`. This spec deliberately reuses that loop's machinery (journal, extractor-shaped isolation, approval-owns-apply split, toggle/flag-file, `references/recipes-*.md` tier) rather than inventing a parallel system. It is the **generalization and implementation of that spec's "Change 3 — pruning pass, scoped"** (2026-07-05 addendum), which sketched a periodic consolidation pass over recipes but left it as future work.

## Problem

The self-learning loop only ever grows the corpus. Every lesson that passes the extractor's truth test lands somewhere — a role file, a `feedback_*.md`, repo `CLAUDE.md`, a `references/recipes-*.md`, or the journal. The tiering addendum slowed the ratchet on always-loaded files but did not reverse it. Over time the accumulated knowledge accretes:

- **Duplicated** content — the same rule restated in two role files, or in both a role file and `CLAUDE.md`. Every duplicate in an always-loaded file is paid on **every relevant spawn, forever**.
- **Contradictory** content — "always X" in one file, a hedged "prefer X when convenient" in another. Agents get conflicting instructions → degraded accuracy, not just wasted tokens.
- **Superseded** content — a rule that a later approved `Proposal (replace)` rewrote elsewhere, or a recipe whose `When-it-rots` condition has demonstrably fired.
- **Stale** content — references to files, agents, tools, or flags that no longer exist in the repo.

The biggest win is trimming **always-loaded** context (role files, feedback, `CLAUDE.md`, `commands/sdlc.md`), which is injected on every relevant agent spawn. Recipes and the journal are cheaper (on-demand / never loaded) but still accumulate rot.

Goals:

- Scan the whole accumulated corpus and surface removal/consolidation candidates ranked by leverage (tokens saved × load frequency).
- Improve accuracy by resolving contradictions and collapsing duplicates so agents read one canonical instruction, not several conflicting ones.
- Be **safe**: nothing is deleted or edited without the user's per-item approval.
- Do not itself bloat the session it is shrinking: all corpus-reading happens inside a throwaway sub-agent context, never in the main session.

Non-goals (v1):

- **Auto-deletion of always-loaded principles.** Inherited verbatim from the self-learning non-goal: *"an auto-deleted instruction is one an agent silently stops following."* The curator NEVER proposes silent deletion of an always-loaded operating instruction — only consolidation of duplicates or resolution of contradictions, both sides shown, per-item approval.
- **Automatic / scheduled runs.** v1 is on-demand only (`/sdlc lessons curate`). No cron, no Phase-8 auto-offer, no size trigger.
- **Cross-repo curation.** One invocation curates one project's corpus (its repo + the shared plugin files + the user memory dir).

## Form factor — agent + command verb (not a skill)

Mirrors the additive loop's split exactly:

| Component | Role | Analogous to |
|---|---|---|
| **`sdlc-curator` agent** (sonnet, isolated) | Read-heavy analyzer. Reads the whole corpus, returns a compact ranked pruning proposal. NEVER deletes, edits, or writes the journal. | `sdlc-lesson-extractor` |
| **`/sdlc lessons curate` command verb** (thin, in `commands/sdlc.md`) | Trigger + surface + per-item approval + apply + journal append. | The orchestrator's drain/apply role |

**Why not a skill.** A skill is instructions the *main session* follows — the main context would then read the entire corpus itself, bloating the exact session we are trying to shrink. Disqualified by the anti-bloat constraint. **Why not an agent alone.** An agent cannot own approval or safely apply deletions, and needs a trigger. The whole design keeps "apply" in the approval-owning layer. **Both** is the only shape that preserves the isolation + approval split.

**Anti-bloat mechanism (the core reason for the agent).** The analysis cost — reading dozens of files across the corpus — is paid entirely inside the sub-agent's throwaway context. The main session receives only a bounded, ranked proposal (top-N candidates + a leverage summary). Running the curator therefore has **zero standing context cost** and a bounded per-run cost. This is the same discipline `sdlc-jira-reader` uses to keep Jira bodies out of the orchestrator.

## Corpus — what the curator reads

Resolved by the command layer once and passed to the agent as an explicit file list (the agent does not glob wildly). Grouped by load-frequency tier because tier drives both the safety rules and the leverage ranking:

| Tier | Load frequency | Members |
|---|---|---|
| **Always-loaded** | Every relevant agent spawn, forever | `plugins/ai-sdlc/agents/sdlc-*.md` (13 role files + extractor), `plugins/ai-sdlc/commands/sdlc.md`, `~/.claude/projects/.../memory/feedback_*.md`, `~/.claude/projects/.../memory/MEMORY.md`, repo-local `CLAUDE.md`, user global `CLAUDE.md`/`RTK.md` |
| **On-demand** | Only when an agent pulls it in | `plugins/ai-sdlc/skills/*/SKILL.md`, `plugins/ai-sdlc/skills/sdlc-conventions/references/recipes-*.md` and other `references/*.md`, `~/.claude/projects/.../memory/*.md` (non-feedback) |
| **Never-loaded** | Storage only | `~/.claude/projects/.../memory/sdlc-events.jsonl` (the journal) |

The journal is both an input (evidence source for supersession/recurrence) and a curation target (old resolved events can be archived).

## Safety model — risk-tiered proposals

Every candidate the curator emits carries a **tier** and an **action** constrained by that tier. This is the safety spine that keeps the always-loaded non-goal intact.

| Tier | Targets | Allowed curator actions |
|---|---|---|
| **A — safe** | `references/recipes-*.md`, the journal | `delete` (a rotted/duplicate recipe), `archive` (old resolved journal events). Recipes carry their own `When-it-rots` expiry; the journal is never loaded. Deletion here changes no always-loaded behavior. |
| **B — flag-only** | any always-loaded file, `SKILL.md` bodies | `consolidate` (two files state the same rule → keep one canonical, remove the duplicate, both sides shown) or `resolve-contradiction` (two files conflict → user picks the winner). **Never `delete` a standalone live instruction.** |

Both tiers are gated by per-item user approval. Tier A allows outright deletion because the cost of a wrong prune is bounded (a recipe re-verified on next need; a journal line that only fed analytics). Tier B forbids the framing "delete this instruction" entirely — it can only ever say "these two say the same thing / conflict; pick the canonical one," which is impossible to satisfy by silently dropping a rule agents rely on.

## Detection categories

The four signals the curator computes, each with its confidence basis:

1. **Duplicated** *(highest leverage)* — the same rule (semantic near-match, not just string equality) appears in ≥2 files. Rank duplicates in always-loaded files first, since each copy is paid every spawn. Action: `consolidate` (Tier B) or `delete` (Tier A recipe dupes).
2. **Contradictory** *(highest accuracy value)* — opposing directives on the same topic across files (e.g. an unhedged "always use `git -C`" vs a buried "prefer `git -C` when convenient"). Action: `resolve-contradiction`; the curator shows both, names the topic, and states which it believes is current (with reasoning) but the user decides.
3. **Superseded** — cross-referenced evidence: an approved `Proposal (replace)` in the journal means old wording was rewritten (the pre-rewrite phrasing, if it survived elsewhere, is superseded); a recipe whose `When-it-rots` condition demonstrably fired; git history showing the rule's rationale was reverted. Action: `delete` (Tier A) or `consolidate`/`resolve` (Tier B).
4. **Stale** *(highest confidence — verifiable)* — every concrete reference in a rule (file path, agent name, tool binary, CLI flag, skill name) is checked against the current repo/plugin state; dangling references are flagged. This is deterministic, so stale findings carry the highest confidence. Action: `delete` if the whole rule is dead (Tier A) or `consolidate`/flag if only a reference within a live rule rotted (Tier B → surface for manual fix).

## Leverage ranking — measurable anti-bloat

The curator ranks candidates by:

```
leverage = lines_removed × load_weight
  load_weight:  always-loaded = <count of spawns the file feeds, or a fixed high constant>
                on-demand      = 1
                never-loaded   = 0   (journal archival ranked last; it's hygiene, not token savings)
```

**Token-win vs maintainability-win.** A `lines × always-loaded-weight` score is a real per-spawn token saving ONLY when each duplicate copy sits in a **separate** always-loaded artifact that loads on its own (two standalone `feedback_*.md` files stating the same rule — removing one removes it from context forever). When the duplicate block instead lives *inside* files that each load once regardless (a verbatim `## Lessons` block repeated across 13 role files — each role file is injected once per spawn no matter its body), deduping is a **maintainability** win, not a token win — it scores `load_weight = 1` or drops below the cut. The curator must not claim a token saving the load model doesn't deliver. (This distinction was surfaced by the first live run against the real corpus, which correctly demoted the cross-role `## Lessons` duplication to `Dropped`.)

It returns only the **top-N** candidates (default N=15) and — per the "no silent caps" discipline — reports how many it dropped and their aggregate leverage (*"+9 lower-leverage candidates not shown (~30 always-loaded lines); re-run with `--all` to see them"*). Each candidate quantifies its win: *"consolidating these 6 duplicated lines removes ~40 always-loaded lines ≈ N tokens per relevant spawn, forever."* The batch opens with a one-line total: biggest always-loaded win first.

## Agent contract — `sdlc-curator`

**Spawn:** general-purpose `Agent()`, model `sonnet`, pointer-not-body. Path resolved by Phase 0's existing `Agent Paths` Glob (`**/ai-sdlc/agents/sdlc-*.md` already matches it; the orchestrator adds a `curator` key to the map).

**Inputs (in spawn prompt):**

- `Corpus`: the explicit tiered file list the command layer resolved (paths grouped by tier), plus the journal path.
- `Journal Path`: absolute path to `sdlc-events.jsonl` (for supersession + near-duplicate cross-checks).
- `Repo Root` + `Plugin Root`: for stale-reference verification.
- `Top-N`: max candidates to return (default 15).
- `Self-Learning`: `ON | OFF` — the same toggle line every agent reads.

**What the curator does:**

1. **Toggle gate (belt-and-suspenders).** If `Self-Learning: OFF`, return `## Verdict: nothing-to-curate` (reason: disabled) and exit — read nothing, write nothing. Mirrors the extractor's step-2 gate.
2. Read the corpus files (tier by tier) and the journal.
3. Detect the four categories. For contradictions and duplicates, do semantic matching, not string equality.
4. Verify every stale candidate against the live repo/plugin (a path/agent/tool/flag either exists or it doesn't).
5. Assign each candidate a tier (A/B) and a tier-legal action.
6. Compute leverage; rank; keep top-N; count the remainder.
7. Return the ranked proposal. **Never** edit a file. **Never** write the journal.

**Output — `## Curation Proposal`:**

```
## Curation Proposal
Corpus: <N files scanned> (<A always-loaded, B on-demand, C journal events>)
Total potential savings: ~<L> always-loaded lines across <k> candidates

### Candidate 1
Category: duplicated | contradictory | superseded | stale
Tier: A | B
Action: delete | archive | consolidate | resolve-contradiction
Leverage: <lines_removed> lines × <load_weight> = <score>  (<human note, e.g. "-6 lines every sdlc-developer spawn">)
Targets:
  - <file:line-range> — "<verbatim snippet A>"
  - <file:line-range> — "<verbatim snippet B>"   # for consolidate/resolve
Evidence: <one sentence — why this is a dupe/contradiction/superseded/stale; cite journal id or repo fact>
Proposed resolution: <for delete/archive: what is removed. for consolidate: which target is canonical, what is removed. for resolve: which side wins + why the curator believes so — user decides>

### Candidate 2
...

Dropped: <M> lower-leverage candidates (~<L2> lines) — re-run with `--all` to include.
```

Or, when clean: `## Verdict: nothing-to-curate` with a one-line reason.

**Constraints (mirror the extractor's):**

- Never applies a deletion or edit. Returns the proposal; the command layer applies after per-item approval.
- Never writes the journal. The command layer owns journal writes.
- Never proposes silent deletion of a Tier-B (always-loaded) standalone instruction.
- Every candidate traces to concrete evidence (a matching snippet, a journal id, a failed repo check). Never invents rot.
- Verbatim snippets in `Targets` so the command layer's Edit `old_string` matches exactly.
- One resolution per candidate; multi-file consolidations are separate candidates.

## Command verb — `/sdlc lessons curate` (STUB — not smoke-tested)

Extends the existing `/sdlc lessons on|off` family in `commands/sdlc.md`. Flow:

1. **Toggle hard-gate.** If Self-Learning is OFF, refuse (*"Self-learning is off; curation is part of the same loop. Turn it on with `/sdlc lessons on` first."*). Never curate while off.
2. **Resolve the corpus.** Glob the tiered file list (see Corpus table) — the command layer does the globbing so the agent gets an explicit list and stays bounded. Resolve repo root, plugin root, journal path.
3. **Spawn `sdlc-curator`** via the standard general-purpose `Agent()` pattern, pointer to `Agent Paths.curator`, passing the corpus + journal + roots + Top-N + `Self-Learning: ON`.
4. **Surface the ranked proposal** as a batch (reuses the mode-2 batch surface shape): total savings line, then per-candidate blocks, then `Approve all / Reject all / Per-item (1: a/r, 2: a/r, ...)`.
5. **Per-item apply on approval:**
   - `delete` / `archive` (Tier A) → Edit removes the recipe block / journal archival moves resolved lines to `sdlc-events.archive-YYYY-MM.jsonl` (reuse the design spec's manual-rotation convention).
   - `consolidate` (Tier B) → Edit removes the duplicate copy from the non-canonical file; leave the canonical untouched. If the canonical needs a pointer, add the one-line reference.
   - `resolve-contradiction` (Tier B) → Edit the losing side to match / defer to the winner (or delete the losing hedge). User picked the winner at the gate.
6. **Journal each action** with `source: "curator"` (see below). Do NOT auto-commit — the user commits lesson/curation edits when ready (v1 behavior, inherited).
7. **Near-duplicate guard against thrash.** Before proposing to delete a recipe, the curator/command checks the journal: if the same content was *added* by an approved lesson within the last 50 events, flag it as "recently added — confirm intent" rather than silently proposing removal. Prevents prune/re-add oscillation with the additive loop.

## Journal symmetry — provenance for removals

A removal is a learning event too. Curator actions append to the same `sdlc-events.jsonl` using the existing schema with:

- `source: "curator"` *(new enum value — the only schema addition)*
- `agent: "sdlc-curator"`
- `extractor_run` → repurposed as `curator_run`: `{ category, tier, action, targets: [file:line...], leverage, resolution }` (structurally parallel; readers key off `source`).
- `status` values reused: `proposed`, `approved`, `rejected`. A new terminal `archived` for journal-archival actions (optional; `approved` also works).

This gives provenance symmetry with the additive loop (git blame shows *what* was removed; the journal shows *why*), and lets the existing near-duplicate suppression see curator activity so the two halves of the loop don't fight.

## Why this complements the loop rather than reinventing it

| Concern | Additive loop (extractor) | Subtractive loop (curator) | Shared machinery |
|---|---|---|---|
| Detection | hooks → journal `raw` | on-demand corpus scan | the journal |
| Analysis | isolated sub-agent, proposes 1 diff | isolated sub-agent, proposes N ranked candidates | extractor-shaped isolation (anti-bloat) |
| Gate | cost gate (tiered routing) | safety gate (risk tiers) | approval-owns-apply split |
| Apply | orchestrator Edits + journals | command layer Edits + journals | never in the sub-agent |
| Toggle | `Self-Learning: ON/OFF` + flag file | same | one toggle governs both halves |
| Recipe tier | writes `references/recipes-*.md` | prunes `references/recipes-*.md` | the on-demand tier |

The extractor adds under a cost gate; the curator removes under a safety gate. Same machine, opposite direction.

## Testing strategy (to run before declaring done — NOT yet run)

Smoke tests, mirroring the self-learning suite:

1. **Duplicate consolidation, happy path.** Plant the same rule in two role files. Run curate. Verify a `duplicated`/Tier-B/`consolidate` candidate, both snippets shown, one canonical. Approve → duplicate removed from the non-canonical file, canonical untouched, journal `approved` with `source: curator`.
2. **Contradiction resolution.** Plant "always X" and "prefer X when convenient" in two files. Verify a `contradictory`/Tier-B/`resolve-contradiction` candidate with both sides + the curator's belief. Approve the winner → loser edited. Reject → journal `rejected`, no edit.
3. **Stale reference detection.** Reference a deleted agent file in a rule. Verify a `stale` candidate with the failed repo check as evidence. (Tier depends on whether the whole rule is dead.)
4. **Recipe deletion (Tier A).** Add a recipe whose `When-it-rots` condition is met. Verify `superseded`/Tier-A/`delete`. Approve → recipe block removed.
5. **Never-delete-principle invariant.** Plant a unique, non-duplicated always-loaded instruction. Verify the curator NEVER emits a `delete` for it (at most flags it if its references are stale). This is the safety-critical test.
6. **Leverage ranking + drop reporting.** Plant 20 candidates. Verify top-15 returned, always-loaded ranked above on-demand, and the "Dropped: 5 …" line present (no silent cap).
7. **Toggle OFF.** `/sdlc lessons off`, then `/sdlc lessons curate`. Verify refusal, no spawn, no reads, no journal write.
8. **Anti-thrash guard.** Approve a lesson that adds a recipe. Immediately run curate. Verify the just-added recipe is flagged "recently added — confirm intent," not silently proposed for deletion.
9. **Anti-bloat check.** Verify the main-session context after a curate run contains only the bounded proposal + summary — not the corpus file contents.

## Future work (v2)

- **Automatic offer** at Phase 8 / on a size trigger (deferred from v1 by the on-demand-only decision).
- **Curator applies Tier-A deletions directly** (the way tiered routing may eventually let the extractor pick tiers), keeping only Tier-B behind approval.
- **Effectiveness tracking** — after a consolidation, watch the journal: did an agent later re-add the removed duplicate? If so the consolidation picked the wrong canonical.
- **`/sdlc lessons curate --all` and `--tier A|B`** scoping flags.
- **Cross-session corpus growth stats** — "always-loaded line count grew N lines over M sessions; last curate removed K."
