# AI-SDLC Documentation Phase (Phase 7.7) — Design

**Status:** Design + scaffold (2026-07-08). Opt-in via `--docs`. Not yet run against a live epic.
**⚠️ SUPERSEDED-IN-PART:** the artifact-duplication concern this raised led to `2026-07-08-ai-sdlc-hybrid-artifact-store-design.md`, which folds this phase in and shrinks it (documenter *assembles* from local `docs/sdlc/` files instead of *re-deriving* from Jira). Build this phase only as part of that redesign. The scaffold (`agents/sdlc-documenter.md`, Phase 7.7 wiring) is retained but will be trimmed.
**Author:** Maor + Claude
**Related:** `2026-06-10-ai-sdlc-self-learning-design.md`, `2026-07-08-ai-sdlc-memory-curator-design.md`, `2026-07-08-ai-sdlc-hybrid-artifact-store-design.md` (parent)

## Problem

The pipeline generates a large amount of high-quality design thinking — tech specs (`## Technical Specification`), Critical User Journeys, integration notes, Mermaid diagrams, design specs — but **all of it dies in Jira comments.** Nothing lands in the repo as durable, human-readable documentation that a future contributor (or the next `/sdlc` run) can read without reconstructing it from ticket threads.

Concretely, after an epic completes:
- There is no README update reflecting the feature that shipped.
- There is no `docs/` page describing the architecture that was actually built (vs. the pre-build spec).
- There is no changelog entry.
- Nothing is pushed to the team's Confluence space, where non-engineers look.

The `sdlc-explainer` skill documents *the SDLC system itself* — it does **not** document the *product* the pipeline builds. That gap is what this phase closes.

## Non-goals

- **Not always-on.** Documentation is opt-in (`--docs`), because not every epic warrants it (spikes, internal refactors) and because it adds an agent spawn + a commit per epic.
- **Not a replacement for tech specs.** The Jira tech spec remains the pre-build design record. This phase produces the *post-build* durable record, synthesized from specs + the actual merged code.
- **Not inline docstring generation.** That is a separate, per-file developer-agent concern (deliberately out of scope here; see Future work).

## Form factor

A **new pipeline phase (7.7) + a dedicated agent (`sdlc-documenter`) + an opt-in flag (`--docs`)**. Mirrors the agent-per-phase model the rest of the pipeline uses.

- **Phase 7.7 (Documentation)** slots between Phase 7.5 (continuous merge of Done PRs) and Phase 8 (completion). At that point every story is Done and merged, so the source material is complete: Jira artifacts *plus* the real merged diff on the base branch.
- **`sdlc-documenter` agent** (sonnet, isolated) reads the epic's Jira artifacts + the merged code, synthesizes documentation, and returns the doc content + a manifest of files to write/update. Like every other SDLC agent, it does the heavy reading in its own context so the orchestrator stays lean.
- **`--docs` flag** gates the whole phase. Absent → Phase 7.7 is skipped entirely (log one line, move to Phase 8). Persisted in the resume file so it survives `/sdlc continue`.

### Why an agent, not a skill invoked inline

Same reasoning as the curator: reading the full epic corpus (every story's tech spec + CUJ + the merged diff) inline would bloat the orchestrator. The documenter absorbs that in a throwaway context and returns bounded artifacts. It *may* itself invoke the `technical-docs` skill internally to structure its output — that keeps doc-formatting logic in one reusable place rather than duplicated in the agent.

## What it produces

Chosen scope (2026-07-08): **repo README/docs + a Confluence page.**

| Target | Where | Action |
|---|---|---|
| `README.md` | repo root | Update the relevant feature section (or add one). Surgical edit, not a rewrite. |
| `docs/<feature>.md` | repo `docs/` | New page: what shipped, architecture-as-built, key decisions, how to run/test. Uses `technical-docs` frontmatter so downstream docx/pptx skills can consume it. |
| `CHANGELOG` entry | repo (if a changelog file exists) | Append a per-epic entry (stories shipped + notable changes). Skip silently if no changelog convention is present. |
| Confluence page | team space | One page per epic, linked from the epic ticket. Created via Atlassian MCP `confluence_create_page` (or `confluence_update_page` if it already exists). |

The repo docs are the source of truth; the Confluence page is a rendered copy for non-engineers, with a link back to the repo docs and the epic.

### Confluence target resolution

There is **no Confluence space configured** in the plugin today. The documenter (via the orchestrator) resolves the target once and persists it:

1. If the SDLC Context block carries `Confluence Space: <key>` / `Confluence Parent: <id>`, use them.
2. Else, the orchestrator asks the user **once** ("Which Confluence space + parent page for `{Project Name}` docs?"), then persists the answer to the resume file's `## Docs` block so it is never re-asked for this project.
3. If the user declines / has no Confluence, the phase still writes repo docs and just skips the Confluence step (logged, not an error).

## Where it fits in the flow

```
Phase 7.5  Continuous merge of Done PRs
   │
   ▼
Phase 7.7  Documentation   ← only if --docs; else skip with one log line
   │  1. Gate on --docs
   │  2. Resolve Confluence target (from context / resume / ask-once)
   │  3. Spawn sdlc-documenter with the epic key + context block
   │  4. Agent reads Jira artifacts + merged diff, returns doc manifest
   │  5. Orchestrator SURFACES the proposed docs to the user (diff-style)
   │  6. On approval: write repo files, commit on base branch, push
   │  7. On approval: create/update the Confluence page, link from epic
   │  8. Journal the doc run (source:"documenter") if Self-Learning ON
   ▼
Phase 8    Completion
```

**Approval gate.** Like design (3.5) and promotion (8), the docs are surfaced for approval before anything is written — unless `--auto`, which auto-approves (consistent with every other gate). The user sees the proposed README diff, the new `docs/` page, and the Confluence page title/space before it lands.

**Commit shape.** Repo doc files are committed on the base branch (`dev` or `main`), exactly like the Phase 8 CUJ replay artifacts already are — or as a small "epic docs" PR if branch protection requires it.

## The `sdlc-documenter` agent contract

Mirrors the curator/extractor split: **the agent proposes, the orchestrator applies.** The agent has no write authority over the repo or Confluence — it returns content + a manifest; the command layer writes after approval. (Reason: keeps one apply-owns-approval path, and keeps the agent safely re-runnable.)

**Reads (from its prompt's `Read Artifacts`):**
- Epic ticket: `## Critical User Journeys`, epic description.
- Each story: `## Technical Specification`, `## Integration Notes`, `## Design Specification` (if present).
- The merged diff for the epic on the base branch (`git -C {repo} diff <epic-base>..<base_branch>` or per-story PR diffs) — the as-built truth.
- Existing `README.md` / `docs/` so edits are surgical, not clobbering.

**Returns:** a `## Documentation Proposal` containing, per target file, the exact content (or Edit-shaped old/new for README surgical edits) + a one-line rationale, plus the Confluence page body. Verbatim snippets for any README edit so the command layer's Edit `old_string` matches.

**Toggle interaction.** The documenter is *not* gated by `Self-Learning` — documentation is a product artifact, not a self-learning proposal. It runs whenever `--docs` is set. (Self-Learning only governs whether the *doc run itself* gets journaled.)

## Journal symmetry

If Self-Learning is ON, the orchestrator journals the doc run with `source:"documenter"` (new enum value alongside `agent-self-report`, `user-correction`, `curator`), and a `documenter_run` object structurally parallel to `extractor_run` / `curator_run`: `{ epic, files_written: [...], confluence_page_id, status }`. This keeps the self-learning journal a complete audit log of everything the pipeline mutates.

## Safety

- **Approval before any write** (repo or Confluence), same as every other gate. `--auto` bypasses, consistent with the rest of the pipeline.
- **Surgical README edits only** — never overwrite an existing README wholesale; the agent returns Edit-shaped diffs with verbatim anchors.
- **Confluence create-or-update** — check for an existing epic page (by title/label) before creating, to avoid duplicates on re-run.
- **Idempotent re-run** — running Phase 7.7 twice on the same epic updates in place rather than appending duplicate sections (the agent reads current state first).

## Smoke tests (to run before marking built)

| # | Test | Expected |
|---|---|---|
| D1 | `--docs` absent | Phase 7.7 skipped with one log line; Phase 8 proceeds |
| D2 | `--docs` present, clean epic | Documenter returns a proposal; README diff + docs page + Confluence body surfaced |
| D3 | Approval gate | Nothing written until user approves; `--auto` auto-approves |
| D4 | Surgical README edit | Existing README sections preserved; only the feature section changes |
| D5 | No Confluence configured | User asked once, answer persisted to `## Docs`; decline → repo docs still written, Confluence skipped |
| D6 | No `docs/` or changelog convention | `docs/` page created; changelog skipped silently (no error) |
| D7 | Idempotent re-run | Second run updates in place, no duplicate sections, no duplicate Confluence page |
| D8 | Anti-bloat | Epic corpus + diff stay in the agent; only the bounded proposal returns |
| D9 | Journal | With Self-Learning ON, one `source:"documenter"` event written; with OFF, none |

## Future work

- **Inline docstring pass** — a developer-agent Phase 4 option to write fuller docstrings, distinct from this post-build synthesis phase.
- **`sdlc-cuj-runner`** already noted in Phase 8; a docs phase could consume its artifacts (screenshots) as figures.
- **Diagram embedding** — pull the architect's Mermaid diagrams from Jira into the repo docs page rather than re-generating.
