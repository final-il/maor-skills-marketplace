---
name: sdlc-conventions
description: >
  AI-SDLC Jira conventions and context protocol. This skill provides the standard templates,
  workflow states, and context-passing protocol used by all AI-SDLC agents. It is loaded
  as reference material by the /sdlc command and individual agents — not invoked directly.
  Use this skill when working with the AI-SDLC pipeline, when you need to understand
  how agents coordinate through Jira, or when creating/modifying SDLC agent definitions.
---

# AI-SDLC Conventions

## Overview

The AI-SDLC system uses Jira as the coordination layer between autonomous agents. Each agent reads its input from Jira tickets and writes its output back to Jira. This skill defines the shared conventions all agents follow.

## Jira Workflow

Stories flow through these statuses:

```
Backlog → Selected for Development → In Progress → In Review → Testing → Done
                                          ↑                           │
                                          └─── (defect: open child Bug) ─┘
```

On defect: Tester/QA creates a child **Bug issue** (issuetype=Bug) parented to the Story and transitions the Story to **In Progress**. The Bug Fixer transitions the Bug to Done and the Story to **In Review** for re-testing.

See `references/workflow-states.md` for full status definitions and the bug-fix detection JQL.

## Labels

All tickets created by the AI-SDLC system carry these labels:
- `ai-sdlc` — identifies tickets created/managed by the pipeline
- `phase-N` — the delivery phase (e.g., `phase-1a`, `phase-1b`)

## Ticket Structure

The system creates tickets in a 3-tier hierarchy:
- **QBV** (level 2) — One per product/project (e.g., "2c — Agent Conversation Visualizer")
- **Epic** (level 1) — Major functional area, parented to the QBV
- **Story** (level 0) — Implementable unit (1-3 days of work), parented to an Epic
- **Sub-task** — Optional fine-grained steps under a Story
- **Bug** — A child *issue* (issuetype=Bug, parented to the Story) created when tests/QA find a defect. Has its own status independent of the parent Story.

See `references/ticket-templates.md` for description templates.

## Context Protocol

Agents run in isolation. They share context through three channels:

1. **Agent prompt** — Structural metadata (cloudId, projectKey, repo path, `Repo Web Base`, issue keys, transition map). `Repo Web Base` is the normalized web URL of the repo (see §2.5), used to build clickable detail pointers.
2. **Jira tickets** — Summaries + pointers. Artifact **detail** now lives in git (§2.5); Jira carries the `## Summary` and a pointer to the detail file. Requirements and bug reports (descriptions) still live in Jira.
3. **Project repo** — Code, CLAUDE.md, config files, **and artifact detail** under `docs/sdlc/{KEY}/*.md` (§2.5)

See `references/context-protocol.md` for the full specification.

## On-Demand Recipes — Agent-Pointer Convention

Not every lesson deserves an always-loaded slot in every future context window. The self-learning loop splits lessons on a generality axis (see `docs/specs/2026-06-10-ai-sdlc-self-learning-design.md` → "Design Addendum — Tiered Lesson Routing"):

- **Principle** — generalizes across stacks/projects → stays always-loaded in a role file, feedback file, or `CLAUDE.md`.
- **Recipe** — true for one tool and rots as the tool changes → lives on-demand in `references/recipes-{domain}.md` (e.g. `recipes-iac.md`, `recipes-python.md`), NOT always-loaded.
- **One-off** — fired once, no recurrence signal → logged only (journal status `logged-recipe`), never codified.

**The convention:** an agent role file that works with a given domain's tooling carries a single one-line pointer to that domain's recipe file, instead of inlining the recipes themselves:

```
See `../skills/sdlc-conventions/references/recipes-{domain}.md` for {domain} tooling gotchas — load on demand.
```

The agent reads the pointed-to file **only when the story it is implementing touches that domain** (e.g. an IaC story → read `recipes-iac.md`; a Python packaging story → read `recipes-python.md`). This buys an entire on-demand recipe file for the cost of one always-loaded line, so the always-loaded tier does not ratchet upward as recipes accumulate.

**Recipe file format.** Each recipe file opens with its format spec, then a `## Recipes` section of `### <short title>` entries, each with three fields: **Trigger** (when this applies), **Recipe** (the command/gotcha), **When-it-rots** (the condition that makes it stale). See the two seed files for the canonical shape.

`sdlc-developer.md` carries the live IaC pointer today. When a new domain's recipes accumulate, add a `recipes-{domain}.md` file and a matching one-line pointer to whichever role files touch that domain.

## Artifact Discipline

Every Jira read/write costs context tokens. Agents that pull the entire ticket "to be safe" balloon the context window and slow the pipeline. The rules below keep agents honest about what they read and write.

### 1. Per-phase artifact contract

Every agent has **exactly one output artifact** — the comment it posts at the end of its phase. The orchestrator's prompt to the agent tells it which prior artifacts (comments) to read. Agents do NOT scan the entire comment thread "for context."

The orchestrator's context block must include:

```
Read Artifacts:
  - Tech Spec (architect comment on {STORY-KEY})
  - Design Spec (designer comment on {STORY-KEY})  ← only if Phase 3.5 ran
  - Integration Notes (integrator comment on {STORY-KEY})  ← only if Phase 3.6 found shared files / collisions
Write Artifact:
  - Dev Result (post as comment on {STORY-KEY})
```

Agents read only the listed artifacts. If an agent finds it needs something else, it stops and asks the orchestrator rather than fetching the full ticket.

**Architect-specific note:** The architect must produce a **Names Reserved** list — every new file path, exported symbol, route prefix, CLI command, and env var the story claims. Under the hybrid store (§2.5) this is its **own file** `docs/sdlc/{STORY-KEY}/names-reserved.md`, so the Phase 3.6 integrator reads only that small file per sibling story (never the full tech spec) to detect collisions before development starts. See `references/ticket-templates.md` for the format.

### 2. Summary header convention

Every artifact (every comment an agent posts) opens with a `## Summary` of 3-5 bullets, then detail below.

```markdown
## Summary
- Approach: streaming XML SAX parser (handles 100MB+ files)
- New module: `src/parsers/xml.py` exposing `parse_stream(io.IOBase)`
- Depends on stdlib `xml.sax` only — no new packages
- Test strategy: 5 fixture files covering malformed/valid/large
- Risk: SAX is callback-based; refactor needed if we want async later

## Detail
...
```

Downstream agents read the **summary first** and drill into detail only when their task requires it. Use the `Read` tool's `offset`/`limit` to window large artifacts. The writer of the artifact owns the summary; this is not lossy compression — the detail is always one read away.

### 2.5 Hybrid artifact store — detail lives in git, not Jira

**The rule:** the `## Summary` stays in the Jira comment; the `## Detail` is written to a **git file**, and the Jira comment carries a **pointer** to it. Jira holds *state + a cheap snapshot + a live pointer*; git holds the *canonical content*. This cuts Jira-write latency, lets specs be diffed and reviewed in the same PR as the code, and removes the duplication that comes from re-deriving specs across stores.

Design + rationale: `docs/specs/2026-07-08-ai-sdlc-hybrid-artifact-store-design.md`.

**Where detail files live:**

| Artifact | Author phase | Detail file |
|---|---|---|
| Technical Specification | Architect (3) | `docs/sdlc/{STORY-KEY}/tech-spec.md` |
| Names Reserved | Architect (3) | `docs/sdlc/{STORY-KEY}/names-reserved.md` *(own file — the integrator reads only this, never the full tech spec)* |
| Critical User Journeys | Architect (3, epic) | `docs/sdlc/{EPIC-KEY}/cujs.md` |
| Design Specification | Designer (3.5) | `docs/sdlc/{STORY-KEY}/design-spec.md` |
| Integration Notes | Integrator (3.6) | `docs/sdlc/{STORY-KEY}/integration-notes.md` |

**The Jira comment** an agent posts is now just the `## Summary` bullets followed by a pointer footer:

```markdown
## Summary
- Approach: streaming XML SAX parser (handles 100MB+ files)
- New module: `src/parsers/xml.py` exposing `parse_stream(io.IOBase)`
- Depends on stdlib `xml.sax` only — no new packages
- Test strategy: 5 fixture files covering malformed/valid/large
- Risk: SAX is callback-based; refactor needed if we want async later

📄 Detail: https://github.com/{org}/{repo}/blob/{base_branch}/docs/sdlc/CSI-105/tech-spec.md
```

**Pointer format:** a clickable GitHub blob URL **tracking the base branch** — `{Repo Web Base}/blob/{base_branch}/{path}` (both `Repo Web Base` and `Base Branch` come from the context block). It is branch-relative, not sha-pinned, so it always resolves to the *current* detail (consistent with "the pointer is truth" below) and the agent can write it in one pass without knowing the phase-end commit sha. The orchestrator derives `Repo Web Base` once (from `git remote get-url origin`, normalizing `git@github.com:org/repo.git` or `https://github.com/org/repo.git` → `https://github.com/org/repo`) and passes it in the context block. Agents that need to **read** the detail use the repo-relative path locally (they have `Repo Path` + the worktree) — no network. The URL is for the human-facing Jira pointer only.

**Summary is a snapshot; the pointer is truth.** The summary is written once, when the artifact is created. If a later phase edits the detail file, the agent does **NOT** re-post the summary — the pointer always leads to the current file. Consequence: **the Jira summary may lag the detail; follow the pointer for current truth.** (This is deliberate — re-syncing on every edit is the Jira-write cost this model exists to eliminate.)

**Reading detail:** agents `Read` the local file at the repo-relative path (windowed with `offset`/`limit` for large files). This replaces the old `jira_get_issue` fetch of a comment body — faster and free of network round-trips.

**Migration / mixed-mode:** if no `docs/sdlc/{KEY}/` file exists (an epic that ran under the old all-in-Jira model), fall back to reading the detail from the Jira comment body as before. New artifacts always write the hybrid way; old ones stay readable. No back-fill.

### 2.6 Fast Mode — the `Jira:` axis and the Fast Work Ledger

Fast mode skips **only the Jira ceremony** during a build (no ticket creation, no status transitions, no summary comments, no Bug issues) while keeping **every** engineering gate — planner, plan-challenger, architect, designer, integrator, developer, tester (incl. smoke-path + live-process E2E gates), QA reviewer, bug-fixer, Phase 7.5 PR merge. It is enabled *because* §2.5 already moved all spec detail into git: the content the pipeline needs is local, so Jira status can be replaced by an orchestrator-held ledger. When the wave finishes, the orchestrator can optionally reconstruct the full Jira hierarchy in retrospect (see `sdlc-jira-creator` Reconcile Mode).

Design + rationale: `docs/specs/2026-07-19-ai-sdlc-fast-mode-design.md`.

**The `Jira: on|off` context axis.** Fast mode adds one line to the SDLC Context block, parallel to `Self-Learning: ON|OFF`:

```
Jira: off
```

- **Default:** an absent `Jira:` line means `Jira: on` — normal mode. Every agent behaves exactly as before until the orchestrator sends `Jira: off`. (This is why the per-agent `## Fast Mode` sections are inert until the orchestrator wires the offer.)
- **Distinct from QA's `Mode: fast`.** The QA reviewer's existing `Mode: fast` means "lightweight review — skip skill loading + test re-run." That is orthogonal: it controls *how heavy the gate is*, not *whether Jira is used*. The two combine freely — a `Jira: off` wave can still ask QA for a `Mode: fast` review. Never overload `Mode: fast` to mean Jira-skip.

**Per-agent behavior when `Jira: off`.** Each per-story agent (architect, developer, tester, qa-reviewer, bug-fixer, integrator, designer):

1. **Skips the startup `jira_get_issue`** and reads its work unit's description + acceptance criteria from `docs/sdlc/_wave-{WAVE-ID}/plan.md` (the `## {KEY}` section for its synthetic key). Sibling spec detail is read from the local `docs/sdlc/{KEY}/*.md` files — already the §2.5 default.
2. **Skips all Jira writes** (`jira_transition_issue`, `jira_add_comment`, `jira_create_issue`) and **loads no `mcp__mcp-atlassian__*` tools** — the mandatory startup ToolSearch is skipped entirely, saving latency + tokens.
3. **Writes its summary artifact to a git file** instead of a Jira comment:

   | Agent | Fast-mode artifact file |
   |---|---|
   | architect | `docs/sdlc/{KEY}/tech-spec.md`, `names-reserved.md`, `cujs.md` *(already git — just drop the Jira comment)* |
   | designer | `docs/sdlc/{KEY}/design-spec.md` *(already git)* |
   | integrator | `docs/sdlc/{KEY}/integration-notes.md` *(already git)* |
   | developer | `docs/sdlc/{KEY}/impl-complete.md` |
   | tester | `docs/sdlc/{KEY}/test-results.md` |
   | qa-reviewer | `docs/sdlc/{KEY}/qa-review.md` |
   | bug-fixer | `docs/sdlc/{KEY}/bug-fix-{bug-id}.md` |

4. **Returns its verdict in its return text** — the orchestrator parses this to update the ledger and route the unit:

   ```
   Status: <phase>            # architected | ready | in-review | testing | done | blocked
   PR: <url or n/a>
   Verdict: PASS | FAIL | APPROVED | ISSUES | n/a
   Bug: <one-line failure + failing test>   # only on FAIL / ISSUES
   ```

Everything else (worktree, code, TDD, tests, smoke artifacts, live-process gates, PR) is **identical** — those are already git/file-based.

**Synthetic work-unit keys.** With no jira-creator to mint keys, work units are named **`{PROJECT}-F{n}`** (`F` = fast; e.g. `CSI-F1`). Real Jira keys are always `{PROJECT}-{integer}`, so `{PROJECT}-F{integer}` can never collide. The synthetic key drops into every existing convention unchanged: dir `docs/sdlc/CSI-F1/`, branch `CSI-F1/{slug}`, worktree `{repo}.worktrees/CSI-F1`. At reconciliation the ledger records the `CSI-F1 → CSI-1234` back-mapping. The wave itself gets a **`WAVE-ID` = `{PROJECT}-W{YYYYMMDD-HHMMSS}`**, stamped once by the orchestrator at wave start (agents can't call `date` deterministically); it names the wave dir and the resume file.

**Wave directory layout.**

```
docs/sdlc/
  _wave-{WAVE-ID}/
    plan.md          # requirements source: one `## {KEY}` section per work unit
    ledger.md        # machine state (committed copy, see below)
  CSI-F1/            # per-unit artifacts, synthetic key — identical to normal layout
    tech-spec.md  names-reserved.md  design-spec.md  integration-notes.md
    impl-complete.md  test-results.md  qa-review.md  bug-fix-CSI-F1-B1.md
```

**The Fast Work Ledger** is the machine-readable state of the wave — it replaces Jira status as the message bus. The orchestrator holds it in two places: as a `## Fast Work Ledger` block in the resume file, and committed to git at `docs/sdlc/_wave-{WAVE-ID}/ledger.md` on the base branch (durable copy — survives loss of the memory file; readable by `--docs` and reconciliation). One entry per work unit:

```yaml
- key: CSI-F1                    # synthetic key
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

The failure loop runs off the ledger: tester/QA return a `Bug:` block, the orchestrator appends it to `bugs[]` (id `{KEY}-B{n}`, `loop: n`) and spawns the bug-fixer with `Jira: off`; the **max-3-loops cap is unchanged**, counted from `bugs[].loop` instead of closed child Bugs. On the 3rd failure the unit is marked `blocked` and surfaced to the user. See `references/workflow-states.md` for the ledger-phase ↔ Jira-status equivalence table.

### 3. What NOT to store in artifacts

- ❌ **Full test output** — Store `15/16 passed; failing: test_parse_malformed_xml (expected ValueError, got None at line 42)`. Re-run tests in the worktree if detail is needed.
- ❌ **Code snippets** — Reference commit SHA + file path. The worktree is the source of truth: `See src/parsers/xml.py:42-78 in commit abc1234`.
- ❌ **Restated requirements** — Don't quote the story description in the tech spec; don't quote the failing test source in the bug report. The reader has the same access you do.
- ❌ **Accumulating threads** — When a detail artifact is revised (e.g., bug-fixer updates the tech spec), **edit the detail file in git** (its history preserves the prior version) — do not post a new Jira comment. Per §2.5 the summary is a snapshot and is not re-synced; the pointer already leads to the current file. (Non-detail results that have no git file — e.g. a one-off dev-result summary comment — still follow the old rule: post a fresh comment with "Supersedes prior; see commit XYZ".)
- ❌ **Full file contents** — Tech specs reference files by path; don't paste the file in.

### 4. Net effect

| Phase | Old default ("read the ticket") | With artifact discipline |
|---|---|---|
| Architect | full story desc + planner notes | story summary + acceptance criteria |
| Integrator (3.6) | full thread on every story | local `names-reserved.md` per sibling story (own file — no tech-spec read) |
| Tester | story + tech spec + design + dev result | tech spec summary + dev-result summary + worktree |
| QA | everything above + test results | all summaries + test-result file |
| Bug-fixer | full thread | bug report + tech spec summary |
| Conflict resolver (7.5) | reads no Jira | only the open PR list; conflict files in worktree |

Roughly 40-60% reduction per agent run, no quality loss — detail is one targeted read away.

## E2E Testing Requirement

**Every story with user-facing changes MUST have at least one Playwright E2E spec** that drives a real headless browser. This applies to any story that modifies:
- Frontend code (React components, pages, layouts, styles)
- HTTP/SSE endpoints consumed by the frontend
- CLI commands that produce user-visible output

The E2E spec must:
1. Exercise the primary user flow the story implements
2. Assert zero `pageerror` and zero `console.error`
3. Assert expected DOM elements are visible with non-zero bounding-box dimensions
4. Save a screenshot to `tests/artifacts/{STORY-KEY}/`

**Rationale:** Unit tests with hand-rolled fixtures shipped 5 wire-format bugs (CSI-526..531) and a dashboard outage (CSI-536/537) to "Done" without catching them. A real browser screenshot would have caught all of them. The smoke artifact is the evidence QA cross-checks.

**Exemptions:** Stories that are purely backend-internal (no user-facing surface — e.g., schema migrations, DuckDB queries, background jobs) are exempt.

**Enforcement:** The orchestrator checks `## Test Results` for the phrase "E2E:" or "Playwright:" on any story with frontend changes. If absent, the tester is re-spawned with explicit instructions to add browser coverage before the story can advance to Testing.

## Pipeline Phases

```
Phase 0: Init → Phase 1: Plan → Phase 2: Jira → Phase 3: Architect
  → Phase 3.5: Design (optional, user-facing stories only)
  → Phase 3.6: Integrator (cross-story collision audit)
  → Phase 4: Develop → Phase 5: Test → Phase 6: QA → Phase 7: Bug Fix
  → Phase 7.5: Continuous merge of Done PRs into base branch
  → Phase 8: Completion + Promotion
```

Phase 3.5 (Design) is skipped for purely backend stories. When it runs, the user approves the design before development begins.

Phase 3.6 (Integrator) runs after every Phase 3 batch. It reads the `## Names Reserved` and `#### Files to Create/Modify` sections from each story's tech spec, posts `## Integration Notes` on every affected story, and forces architects to revise tech specs when a hard name collision is detected. Read-only on code; only writes to Jira. See `sdlc-integrator.md`.

Phase 7.5 (Continuous merge) runs immediately after each story reaches `Done`. It attempts `gh pr merge` on the story's PR; on a multi-PR mechanical conflict it dispatches the `sdlc-conflict-resolver` agent which union-merges safe additive collisions (imports, router registrations, dep lists, barrel re-exports). Semantic conflicts hard-stop and route through the bug-fix loop.

## Branching Model

The pipeline supports two branching models, detected automatically in Phase 0:

**Dev/Prod model** (`dev` + `main` branches):
- Agents branch from `dev`, PRs target `dev`
- After all stories are Done, orchestrator offers to promote `dev` → `main`
- Context block sets: `Base Branch: dev`, `PR Target: dev`

**Single-branch model** (default):
- Agents branch from `main`, PRs target `main`
- Context block sets: `Base Branch: main`, `PR Target: main`

Agents never need to know which model is active — they use `{base_branch}` and `{pr_target_branch}` from the context block.

## Workspace Isolation — Git Worktrees

When the orchestrator runs multiple agents concurrently (e.g., developing two independent stories at once), they MUST NOT share a single working directory. A plain `cd {repo_path} && git checkout {branch}` from one agent yanks the working tree out from under the other.

The pipeline solves this with **git worktrees** — one worktree per story branch.

**Convention:**

- Worktrees are created as a sibling of the repo: `{repo_path}.worktrees/{STORY-KEY}`
  - Example: repo at `~/git/jiralyzer-dev` → worktree at `~/git/jiralyzer-dev.worktrees/CSI-105`
- The orchestrator (Phase 4 onward) creates the worktree before spawning the first agent for a story, and removes it in Phase 8 after the story reaches Done.
- Each agent prompt receives a `Worktree Path` field in the SDLC context block. Agents operate inside the worktree, NOT in the main `Repo Path`.
- The main `Repo Path` is for read-only operations only (reading `CLAUDE.md`, scanning project structure for context). All `git checkout`, edits, commits, and pushes happen in the `Worktree Path`.

**Lifecycle:**

```
Phase 4 (Developer):   orchestrator runs `git -C {repo_path} worktree add {worktree_path} -b {STORY-KEY}/{slug} {base_branch}`
                       → developer works in {worktree_path}
Phase 5 (Tester):      reuses the same {worktree_path} (story branch already checked out there)
Phase 6 (QA):          reads from {worktree_path} (read-only)
Phase 7 (Bug Fixer):   reuses the same {worktree_path}
Phase 8 (Completion):  after story is Done & PR merged, orchestrator runs `git -C {repo_path} worktree remove {worktree_path}`
```

**Same-story agents are serialized** — developer → tester → QA → bug-fixer all touch the same branch, so they run sequentially per story. Only **different stories run in parallel**, each in its own worktree.

**Why this matters:**

- Two developers branching from `dev` simultaneously no longer fight over `HEAD`
- A bug-fixer running on `STORY-A` cannot accidentally check out `STORY-A`'s branch in the main repo while the tester for `STORY-B` is mid-run
- `git status`, `git diff`, and `pytest` results are stable per agent
- If an agent crashes, the worktree is recoverable — `git worktree list` shows all live worktrees

**Cleanup rules:**

- The orchestrator owns the worktree lifecycle. Agents NEVER run `git worktree add` or `git worktree remove`.
- If a worktree path already exists when the orchestrator tries to create it (e.g., resuming a pipeline), reuse it — do not delete and recreate.
- If a story is abandoned/blocked, the orchestrator removes the worktree in Phase 8 along with the others.

## Required MCP Server: mcp-atlassian

The AI-SDLC pipeline requires the standalone `mcp-atlassian` MCP server (configured via `/mcp`). All Jira operations use `mcp__mcp-atlassian__jira_*` tools.

**IMPORTANT:** MCP tools are deferred — agents MUST use `ToolSearch` to load tool schemas before calling them.

**IMPORTANT:** Plugin subagents cannot access MCP tools (Claude Code limitation #25200, #38920). The orchestrator MUST spawn Jira-needing agents as general-purpose `Agent()` calls (no `subagent_type`) with the agent file body as the prompt. Only the planner (no Jira) can use typed subagent spawning.

| Operation | MCP Tool |
|-----------|----------|
| Search issues | `mcp__mcp-atlassian__jira_search` |
| Get issue details | `mcp__mcp-atlassian__jira_get_issue` |
| Create issue | `mcp__mcp-atlassian__jira_create_issue` |
| Update issue | `mcp__mcp-atlassian__jira_update_issue` |
| Add comment | `mcp__mcp-atlassian__jira_add_comment` |
| Transition status | `mcp__mcp-atlassian__jira_transition_issue` |
| Get transitions | `mcp__mcp-atlassian__jira_get_transitions` |
| Create link | `mcp__mcp-atlassian__jira_create_issue_link` |
| Link to epic | `mcp__mcp-atlassian__jira_link_to_epic` |
| List projects | `mcp__mcp-atlassian__jira_get_all_projects` |
| Look up user | `mcp__mcp-atlassian__jira_get_user_profile` |

## Agent Workflow Rules

1. **Load MCP tools first** — Use `ToolSearch` with `select:mcp__mcp-atlassian__jira_get_issue,...` before any Jira call
2. **Read only the artifacts your prompt names** — The orchestrator lists `Read Artifacts` in your context block. Read those, not the full comment thread. If you need something else, stop and ask the orchestrator.
3. **Write exactly one artifact** — Your phase produces one comment, and it opens with a `## Summary` of 3-5 bullets (see Artifact Discipline above).
4. **Never inline full output** — No full test logs, no pasted code, no restated requirements. Reference commits / file paths / failing test names instead.
5. **Use markdown in Jira** — The `mcp__mcp-atlassian__jira_add_comment` body parameter accepts Markdown directly
6. **Transition tickets** — Move tickets to the correct status when done
7. **On defect, create a child Bug and move the Story to In Progress** — Create a child issue with `issue_type: "Bug"` and `parent: {STORY-KEY}`, then transition the parent Story to **In Progress**. The Bug Fixer transitions the Story to **In Review** when the fix is pushed.
8. **Commit messages** — Always include the Jira ticket key: `{STORY-KEY}: {summary}`
9. **Branch naming** — Use `{story-key}/{short-slug}` (e.g., `PROJ-42/xml-parser`)
10. **PR target** — Always use `--base {pr_target_branch}` when creating PRs
11. **Operate in your worktree** — All git/edit/test commands run with `cd {worktree_path}` (or `git -C {worktree_path}`). Never `cd {repo_path}` for write operations. Never run `git worktree add/remove` from an agent — that is the orchestrator's job.

## Dynamic Agent Spawning — When and How

A *dynamic agent* is a general-purpose `Agent()` the orchestrator spawns with an **orchestrator-authored, task-specific instruction prompt**, for work that **no existing `sdlc-<role>` owns** (e.g. operating a live cloud environment, running a benchmark, a one-off migration). This is powerful but is in direct tension with the core rule "every phase must run through the proper agent." Uncontrolled, it becomes a loophole to skip pipeline gates (a hand-rolled fixer that dodges bug-fixer → tester → QA). The following governs it.

**Validity test — ALL 5 must hold before proposing a dynamic spawn:**

1. **No existing role fits.** Never a shortcut around a defined phase agent. If developer/tester/architect/qa/etc. owns the work, that role MUST be used.
2. **Bounded and single-purpose.** Clear inputs, exactly one concrete deliverable, and it terminates (a verdict, a measurement, a migration) — not open-ended "help with X."
3. **Specialized reason to isolate.** The work needs domain-specific knowledge such that inlining it would bloat the orchestrator or a generic role's prompt, AND it is not merely "read some files and summarize" (that is general-purpose/Explore — no custom role needed). Also qualifies if it must keep something out of orchestrator context (credentials, very large outputs).
4. **Guardrails travel verbatim (with teeth).** A dynamic agent inherits NO role file. Before spawning, the orchestrator MUST emit an explicit checklist naming which standing guardrails/memories it is injecting verbatim into the prompt (e.g. AWS-safety posture, no-unapproved-CI/CD, creds-never-printed protocol). If a relevant guardrail exists and is not listed, do NOT spawn.
5. **Still tracked.** The dynamic agent reports to a Jira ticket and/or returns structured evidence — auditable, not off-book.

**Graduation rule:** If the same dynamic role is spawned 2+ times, OR the role touches production/external systems even once, promote it to a permanent, version-controlled `sdlc-<role>.md` agent file (reviewed) rather than re-authoring it ad hoc.

**Autonomy ladder (phased rollout — the orchestrator does NOT self-advance; the user promotes the phase after reviewing the decision log):**

- **Phase 1 (CURRENT / default):** The orchestrator MUST pause and ASK the user before spawning ANY dynamic agent — read or write. It presents the 5-point justification including the guardrail checklist, and waits for approve/deny. Every decision is journaled to the self-learning log so the criteria can be tightened.
- **Phase 2** (advance only when the log shows the criteria are reliable): read-only/analysis dynamic spawns become free; any dynamic agent that WRITES to external systems or the repo still requires user approval.
- **Phase 3** (eventually): fully automatic when all 5 criteria hold.

## Performance Rules — How Agents Use Jira

Every agent should treat Jira round-trips as the bottleneck of the pipeline. Follow these rules in every agent run:

### 1. Parallelize Jira reads and writes

When you need multiple independent Jira calls (e.g., reading a parent story + a child bug, or transitioning a ticket + adding a comment), issue them as **parallel tool calls in a single message**. Do NOT chain them sequentially.

**Examples:**
- Reading the bug + parent story → one message, two `jira_get_issue` calls
- Posting a result comment + transitioning status → one message, two calls
- Reading multiple stories in a batch → one message, N calls

The only time calls must be sequential is when the result of one is the input to the next (e.g., create issue → use returned key to create a link).

### 2. Use the transition map from the orchestrator's context block

The orchestrator discovers the project's transition IDs once in Phase 0 and passes them in every agent prompt as `Transition Map: {status_name: transition_id, ...}`.

**Always use the map first.** Do NOT call `mcp__mcp-atlassian__jira_get_transitions` on the happy path — the map already has what you need.

```
# Pseudo-code for transitioning to "Ready for Dev":
transition_id = transition_map["Ready for Dev"]
mcp__mcp-atlassian__jira_transition_issue(issue_key, transition_id)
```

**Fallback** — If the status you need is **not** in the map (rare; usually means the workflow has a status you haven't seen):
1. Load `jira_get_transitions` via ToolSearch
2. Call it once to find the missing transition ID
3. Proceed with `jira_transition_issue`
4. Note the missing status in your final Jira comment so the orchestrator can refresh the map

This means individual agents do NOT include `jira_get_transitions` in their startup ToolSearch — they only load it on miss.

### 3. Batch comment + transition where the API allows

A single status-change message often combines "post results" + "move to next status". Always issue them as **parallel calls**, not sequential — the order doesn't matter and the API handles both independently.
