# AI-SDLC Hybrid Artifact Store — Design

**Status:** Design (2026-07-08). Supersedes the standalone documentation-phase plan; the documenter folds into this.
**Author:** Maor + Claude
**Related:** `2026-07-08-ai-sdlc-documentation-phase-design.md` (now a sub-part), `sdlc-conventions` skill (Artifact Discipline).

## Problem

Jira is doing two jobs at once:

1. **Workflow state machine** — status transitions are the message bus between phases. Jira is *good* at this. **Keep it.**
2. **Document store** — tech specs, design specs, integration notes, CUJs live as **comment bodies**. Jira is a *poor* fit here, and it costs us:
   - **Latency.** Architect writes 8 comment sections, integrator 10, designer 5. Each is a network round-trip; Jira MCP calls dominate wall-clock.
   - **Context bloat.** We had to build a whole agent — `sdlc-jira-reader` — solely to read comment bodies and return bounded summaries so the orchestrator's context doesn't blow up. That agent is a *workaround* for role #2.
   - **Duplication + drift.** The proposed documenter would read specs back out of Jira, re-derive docs, and store them a *third* place (git docs) and a *fourth* (Confluence). The same knowledge in four stores, drifting.
   - **Not diffable / not reviewed with the code.** A spec in a Jira comment is unversioned and reviewed separately from the PR that implements it.

## The key enabler (already in the codebase)

`sdlc-conventions` SKILL.md:103-117 already mandates that **every artifact opens with a `## Summary` of 3-5 bullets, then `## Detail` below**, and that "downstream agents read the summary first and drill into detail only when their task requires it."

The hybrid model is just: **relocate the existing split across the git/Jira boundary.** Nothing conceptually new.

## The model

| Piece | Lives in | Why |
|---|---|---|
| `## Summary` (3-5 bullets) | **Jira comment** (as today) | PM/non-eng visibility; cheap to read; already short |
| `## Detail` (full spec/design/notes) | **git file** `docs/sdlc/{STORY-KEY}/{artifact}.md` | Diffable, versioned, reviewed in the PR, local-read (no network) |
| Pointer | **Jira comment footer** | `📄 Detail: docs/sdlc/CSI-105/tech-spec.md @ {sha}` links the two |

**Jira's job shrinks to: state machine + summary + pointer.** Git becomes the single source of truth for spec *content*.

### Artifact → file map

| Artifact | Author phase | File |
|---|---|---|
| Technical Specification | Architect (3) | `docs/sdlc/{STORY}/tech-spec.md` |
| Names Reserved | Architect (3) | section within tech-spec.md (integrator greps it locally) |
| Critical User Journeys | Architect (3, epic) | `docs/sdlc/{EPIC}/cujs.md` |
| Design Specification | Designer (3.5) | `docs/sdlc/{STORY}/design-spec.md` |
| Integration Notes | Integrator (3.6) | `docs/sdlc/{STORY}/integration-notes.md` |

All `## Summary` blocks continue to post to Jira as comments, now with a pointer footer.

## What this fixes

- **`sdlc-jira-reader` mostly retires.** Its reason for existing (summarize expensive comment bodies) is gone — details are local files the orchestrator/agents `Read` directly and cheaply. It survives only for genuine *state* queries (which stories are Done, transitions), which are small.
- **`Read Artifacts` becomes file paths, not comment fetches.** The context protocol stays, but "read the architect's detail" is now a windowed local `Read`, not a `jira_get_issue`.
- **Specs are reviewed in the same PR as the code.** No drift; a spec change and its implementation land together.
- **Jira writes shrink** to short summary + pointer → fewer, smaller MCP calls → less latency.
- **The documenter collapses** (see below).

## The timing wrinkle (and fix)

Specs are written in Phases 3 / 3.5 / 3.6 — **before** the per-story worktree exists (worktrees are created at Phase 4, `sdlc.md:187`). So there's nowhere story-local to commit an early spec.

**Fix (reuses existing precedent):** Phase 8 already commits artifacts (CUJ replay) straight to the base branch. Do the same for specs — commit `docs/sdlc/{KEY}/*.md` to `{base_branch}` at the end of each design phase, in one small batched commit per phase:

```bash
git -C {repo_path} add docs/sdlc/
git -C {repo_path} commit -m "docs(sdlc): specs for {EPIC-KEY} architecture phase"
git -C {repo_path} push origin {base_branch}
```

When the story worktree is later created (Phase 4) off `{base_branch}`, the spec files are already there for the developer to `Read` locally. Alternative considered and rejected: create worktrees at Phase 3 — too early, and epics with many stories would spawn many worktrees before any code is written.

## How the documenter folds in

With details already in `docs/sdlc/` as the epic runs, Phase 7.7's job **collapses from "re-derive everything from Jira + code" to "assemble + surface"**:

1. **README / user-facing docs** — still synthesized (the `docs/sdlc/` files are internal design records; a README is a curated user-facing view). But the documenter now reads *local spec files* instead of re-fetching Jira — faster, and it's reading the same canonical content the developer used, so no drift.
2. **`docs/<feature>.md`** — may become a thin index that links the already-committed `docs/sdlc/{KEY}/*.md` files, rather than regenerating their content.
3. **Confluence** — unchanged: a rendered mirror of the README/index for non-engineers, created once, linked from the epic.
4. **Changelog** — unchanged.

Net: the `sdlc-documenter` agent shrinks (less synthesis, more assembly), and the "four stores drifting" problem is gone — git is canonical, Jira holds summaries+pointers, Confluence is an explicit rendered mirror.

## Migration

- **In-flight epics** have details in Jira comments. Run mixed-mode: the file-read path falls back to a Jira comment fetch when no `docs/sdlc/{KEY}/` file exists. New artifacts write the hybrid way; old ones stay readable.
- **No back-fill required** — old epics finish under the old model; new epics start hybrid.
- **Rollout order:** (1) update `sdlc-conventions` Artifact Discipline to define the split + pointer format; (2) update each writer agent (architect, designer, integrator) to write detail-to-file + summary+pointer-to-Jira; (3) update `Read Artifacts` semantics + the reader agent; (4) add the phase-end spec commit; (5) fold the documenter. Each step is independently shippable.

## Tradeoffs (chosen: hybrid)

- **Kept:** PM visibility (summary + pointer in Jira), state machine in Jira, one canonical content store (git).
- **Cost:** a pointer indirection (Jira → file); the phase-end commit; mixed-mode during migration.
- **Rejected — full move to git:** loses in-Jira visibility entirely. **Rejected — keep all in Jira:** doesn't fix latency/bloat/drift.

## Build decisions (resolved 2026-07-09)

1. **Pointer format → clickable repo URL, branch-relative.** The Jira comment footer is a full GitHub blob URL tracking the base branch:
   ```
   📄 Detail: https://github.com/{org}/{repo}/blob/{base_branch}/docs/sdlc/CSI-105/tech-spec.md
   ```
   One click from Jira to the *current* rendered file. The orchestrator derives the web base once (from `git remote get-url origin`, transforming `git@github.com:org/repo.git` / `https://github.com/org/repo.git` → `https://github.com/org/repo`) and stores it in the context block as `Repo Web Base`. Agents build the URL from `{Repo Web Base}/blob/{base_branch}/{path}`. Agents that need to *read* the detail still use the repo-relative path locally (they already have `Repo Path`) — the URL is for the human-facing pointer only.

   **Branch-relative, not sha-pinned (resolved 2026-07-09):** a sha-pinned URL would freeze at the write-time version, contradicting decision 4 ("follow the pointer for current truth") — and the phase-end commit sha does not exist when the agent writes its summary, so pinning would force an orchestrator rewrite pass (an extra Jira write per artifact, the exact cost this model eliminates). Branch-relative is always-current and writable in one pass. Trade-off accepted: the link breaks if a detail file is later moved/deleted (rare; git history still has it).

2. **`Names Reserved` → its own file** `docs/sdlc/{STORY}/names-reserved.md`. The integrator reads only this small per-story file to detect collisions, never the full tech spec — cheapest possible integrator read. The architect writes it alongside `tech-spec.md`.

3. **Phase-end commit → mirror Phase 8 CUJ behavior.** Use the exact rule the Phase 8 CUJ-artifact commit already uses: direct push to `{base_branch}`, or a small PR only if branch protection requires it. One consistent, already-proven rule — no new commit policy.

4. **Summary re-sync → never; the pointer is truth.** The Jira `## Summary` is an at-creation snapshot; the pointer always leads to the current detail file. Detail edits in later phases do NOT trigger a summary re-post. This is the cheapest option and fully consistent with "git is canonical, Jira holds a cheap snapshot + live pointer." Consequence to document in `sdlc-conventions`: **the summary may lag the detail; follow the pointer for current truth.** (Rejected: always-re-sync — most Jira writes, works against the redesign's goal; material-change-only — small drift risk from agent judgment, and we prefer a bright-line rule.)

## Smoke tests (before build sign-off)

| # | Test | Expected |
|---|---|---|
| H1 | Architect writes tech spec | detail file at `docs/sdlc/{STORY}/tech-spec.md`; Jira comment = summary + pointer |
| H2 | Developer reads spec | reads the local file (no `jira_get_issue` for the detail body) |
| H3 | Phase-end commit | spec files committed + pushed to base branch; present when worktree is later created |
| H4 | Mixed-mode fallback | old epic (detail in Jira, no file) still readable |
| H5 | Integrator Names Reserved | collision detection works reading the local file |
| H6 | Documenter | assembles README/index from local `docs/sdlc/` files, not Jira re-fetch |
| H7 | PM visibility | Jira comment still shows a usable summary + working pointer |
