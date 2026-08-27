# Orchestrator Phase Playbooks (load on demand)

Execution *mechanics* for orchestrator phases whose **decisions, gates, caps, and triggers**
stay resident in `commands/sdlc.md`. The orchestrator loads the relevant section here when it
reaches that phase. Nothing here is a decision point — those remain in the command file so
routing is never gated on an on-demand read. This file exists purely for context economy on the
always-resident orchestrator; it is authoritative for the *how*, not the *whether/when*.

---

## phase-7-5 — Continuous merge of Done PRs (mechanics)

> Resident in `commands/sdlc.md`: the trigger, the `MAX_UNMERGED_DONE_PRS` drift cap, the
> simple-merge decision (zero vs. sibling unmerged PRs), and the Step 7.5.4 drift-gate halt.
> This section is only the PR-lookup, conflict-resolver dispatch, and cleanup mechanics.

### Locate the PR (Step 7.5.1)
Find the PR for the just-Done story:
- Preferred: read the PR URL from the developer's `## Implementation Complete` comment.
- Fallback: `gh pr list --head {STORY-KEY}/{slug} --base {pr_target_branch} --json number,url,headRefName --limit 1`.

If no open PR is found (e.g. already merged manually), log it and move on — the story stays Done.

To decide simple-merge vs. pile-up (this is the resident decision in 7.5.2), enumerate siblings:
`gh pr list --base {pr_target_branch} --state open --json number,headRefName --limit 50`,
filtered to the current epic's story branches.

### Conflict-resolver dispatch — multi-PR pile-up (Step 7.5.3)
1. **Set up a dedicated merge worktree** (NOT a story worktree):
   ```bash
   MERGE_WT="{repo_path}.worktrees/.merge-{epic-key}-$(date +%Y%m%d-%H%M%S)"
   git -C {repo_path} fetch origin {base_branch}
   git -C {repo_path} worktree add "$MERGE_WT" "origin/{base_branch}"
   ```
2. **Spawn `sdlc-conflict-resolver` as general-purpose `Agent()`** (pointer not body) with:
   - Pointer to `Agent Paths.conflict-resolver`
   - SDLC context block, including: `Repo Path: {repo_path}`, `Base Branch: {base_branch}`,
     `PR Target: {pr_target_branch}`, `Merge Worktree Path: {MERGE_WT}`,
     `Read Artifacts: none — agent reads only the open PR list + conflict files in the worktree`,
     `Write Artifact: ## Merge Result (one comment per affected story); optional Bug issues for escalations`
   - Task: the epic key + comma-separated PR numbers (just-Done PR + every other open PR targeting
     `{base_branch}` from this epic's stories, oldest first)
   - `model: "sonnet"`
   - **Fast wave (`Jira: off`):** add `Jira: off`; escalations come back as `Bug:` blocks in the
     agent's return text (no Jira Bug), which you record in the ledger `bugs[]`.
3. The agent merges PRs in topological order, applies safe-pattern unions, pushes once at the end.
4. **On agent return:**
   - Every merged PR: log it; stories stay `Done`; PRs auto-close on push.
   - Every escalated PR: a child Bug was filed (or, fast mode, a `Bug:` block returned) + a
     `## Merge Result` posted. Route those through the standard Phase 7 bug-fix loop.
5. **Clean up the merge worktree:**
   ```bash
   git -C {repo_path} worktree remove "$MERGE_WT"
   ```
