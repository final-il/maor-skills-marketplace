# AI-SDLC Conditional Entrypoints (loaded on demand)

Loaded by the orchestrator when a User-Reported-Bug, Hotfix, or Feedback-Loop trigger fires (see the stub in `commands/sdlc.md` → "Conditional Entrypoints"). Full flows below.

## User-Reported Bugs

When the user (not an agent) reports a bug — typically while testing a Done story — file it as a `Bug` sub-task and route it through the standard Phase 7 fixer flow. CSI supports the `Bug` issuetype natively; never use `Subtask` as a fallback.

**Trigger:** the user says something like "this story is broken", "PROJ-105 has a bug", or "when I run X I get Y error" while a story is in `Done` (or anywhere downstream of the developer phase).

**Flow:**

1. **Identify the parent Story.** If the user gave a story key, use it. Otherwise ask one clarifying question to pin down which story owns the broken behavior.
2. **Create the Bug** with `mcp__mcp-atlassian__jira_create_issue`:
   - `issue_type: "Bug"`
   - `additional_fields.parent`: the parent story key
   - `additional_fields.labels`: `["ai-sdlc", "{project_name}", "user-reported"]`
   - Description follows the Bug template in `sdlc-conventions` ticket-templates: one-line root-cause hypothesis (or "unknown"), steps to reproduce as the user described them, expected vs actual.
3. **Move the parent Story to `In Progress`** (uses the Transition Map). The Story sits in `In Progress` while the child Bug is being resolved.
4. **Ensure the worktree exists** for the parent story:
   ```bash
   if [ ! -d "{repo_path}.worktrees/{STORY-KEY}" ]; then
     git -C {repo_path} fetch origin
     git -C {repo_path} worktree add "{repo_path}.worktrees/{STORY-KEY}" "{STORY-KEY}/{slug}"
   fi
   ```
   If the original feature branch was deleted post-merge, branch the fix from `{base_branch}` with a new slug like `{BUG-KEY}/fix-{short-desc}` instead.
5. **Spawn `sdlc-bug-fixer` as a general-purpose `Agent()`** (per "How to Spawn Agents") with the standard context block, the Bug key, and the parent story key. The bug fixer treats user-reported bugs identically to agent-reported ones.
6. **Run Phase 5 (Test) → Phase 6 (QA)** on the parent story when the bug fixer finishes. Same loop as a normal failure — up to 3 bug-fix iterations before flagging for human review.

**Do NOT:**
- ❌ Fix the bug yourself in the orchestrator — always delegate to `sdlc-bug-fixer`.
- ❌ Skip the test/QA phases after the fix — even small fixes go through the full loop.
- ❌ File the Bug as a top-level issue without a parent — the bug-fixer needs the parent story for context.

## Hotfix Pattern — User-Driven Manual Fix With Late Jira Reconciliation

**When to use:** the user is hands-on in a session, says "just fix X", and the work is small enough that the full Jira ceremony (Bug ticket → bug-fixer agent → tester → QA → 7.5 merge) would be more overhead than the fix itself. The user is the human-in-the-loop, so the value of the ceremony (tracking, async coordination) is partially redundant.

**Critical rule that DOES NOT relax:** the orchestrator still does NOT write code itself. It spawns `sdlc-bug-fixer` (or `sdlc-developer` for a tiny feature) directly, without first creating a Jira Bug. Jira is reconciled afterward.

**Eligibility (all must hold):**
- The user is actively driving the session (not a `/sdlc continue` resume).
- The user explicitly opted in (e.g., "hotfix this", "just patch it", "skip the ceremony").
- The fix touches ≤2 files and has an obvious test the agent can write.
- There is no in-flight epic phase racing for the same files.

**Flow:**
1. **Identify the parent context.** Either the existing parent Story (if one is broken) or — for a tiny feature — the existing Epic the work belongs under. Hotfixes do NOT spawn a new epic.
2. **Spawn the bug-fixer (or developer) directly.** Pass the standard SDLC context block, the user's description as the task, and a flag in the prompt: `Hotfix Mode: true`. The agent works on a worktree (create one off `{base_branch}` with a short slug like `hotfix/{short-desc}`) and follows the normal commit/test/PR flow.
3. **Skip the agent-files-bug step.** The fixer normally expects an existing Bug key; in hotfix mode it operates against the parent story's branch (or a new hotfix branch) and reports back to the orchestrator.
4. **Run Phase 5 (test) + 6 (QA) on the resulting PR.** These are NOT optional — even a hotfix must pass the smoke artifact + live-process gates. The shortcut is the Jira ceremony, not the verification gates.
5. **Reconcile Jira after the user signal.** When the user says "merge it" or "ship it":
   - Create a Bug ticket retroactively (`issue_type: "Bug"`, `parent: {STORY-KEY}` or `parent: {EPIC-KEY}` for tiny features), back-dated description: "Hotfix landed in PR #N — see commit {sha}". Labels: `["ai-sdlc", "{project_name}", "hotfix"]`.
   - Move the Bug straight to `Done` in a single transition.
   - If the parent Story was in `Done`, leave it there.
   - Phase 7.5 merges the PR (or it was merged manually as part of the hotfix flow — either is fine).
   - Update the auto-resume file as usual.

**Why this pattern exists:** previous reform attempts had the orchestrator inline-fix bugs ("just one line, no need for a bug ticket"), which violates `feedback_orchestrator_no_code` and `feedback_orchestrator_no_shortcuts`. The hotfix pattern resolves the tension: the orchestrator never writes code, but the user can opt out of upfront Jira ceremony as long as the verification gates still run and Jira is reconciled before the session closes.

**When NOT to use:**
- ❌ The user is not in the loop (e.g., `/sdlc continue` background runs). Always full ceremony.
- ❌ The fix touches >2 files or affects a wire contract → full bug-fix flow.
- ❌ The parent epic is mid-flight (Phase 4-7 active stories) → conflicts with concurrent worktrees.

## Feedback Loop — Bugs and New Features from Testing

When the product is already built and the user reports a bug or requests a feature discovered during testing:

1. **Don't re-run the full SDLC ceremony** — the project context already exists
2. **Add stories directly** to the existing Jira project under a new or existing epic
3. **Skip Phase 1 (Planning)** — the user already knows what they need; create tickets directly
4. **Skip Phase 3 (Architecture)** if the change is straightforward — post a brief tech spec as a Jira comment and transition to "Selected for Development"
5. **Run Phase 4-7 normally** — develop, test, QA, bug fix

Indicators that this is a feedback loop (not a new project):
- The user says "add this to our project" or references existing Jira project/epic
- The repo already has code, CLAUDE.md, and existing Jira tickets
- The request is a bug fix, missing feature, or gap found during testing
- The scope is small (1-5 stories, not a full project)

In this mode, the orchestrator:
1. Discovers the existing project context (same as Phase 0, but faster — reuse known cloudId, projectKey, transitions)
2. **Run the "Mode selection & offer" gate up front** (a small feedback delta is a strong fast-mode candidate — the heuristic usually recommends fast). If fast: skip step 3's Jira creation, stamp a `WAVE-ID`, write `plan.md` + ledger, and proceed via fast-path routing. If normal: continue below.
3. Creates an epic + stories directly (or adds stories to an existing epic)
4. Sets up dependency links
5. Proceeds to architecture (brief) → develop → test → QA
