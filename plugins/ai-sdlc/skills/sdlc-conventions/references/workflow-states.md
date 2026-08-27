# AI-SDLC Workflow States

## Workflow Statuses

Stories move through these statuses: **Backlog, Selected for Development, In Progress, In Review, Testing, Done**.

`Bug` is an issue *type*, not a status. A defect is a child issue (issuetype=Bug) parented to a Story; while the Bug is open, the parent Story sits in **In Progress**.

When a project uses different status names, the orchestrator maps them at Phase 0. Common synonyms:
- "Backlog" / "To Do"
- "Selected for Development" / "Ready for Dev"
- All other names should match exactly.

## Status Definitions

| Status | Meaning | Entered By | Exited By |
|--------|---------|------------|-----------|
| **Backlog** (or **To Do**) | Story created, not yet designed | Jira Creator agent | Architect agent |
| **Selected for Development** (or **Ready for Dev**) | Tech spec complete (+ design spec if UI story), implementation can begin | Architect agent (or Designer after approval) | Developer agent |
| **In Progress** | Developer is actively writing code, OR Bug Fixer is actively resolving a child Bug | Developer agent / Bug Fixer agent | Developer agent / Bug Fixer agent |
| **In Review** | Code written and PR opened, awaiting tests (also where Story returns after a fix) | Developer / Bug Fixer | Tester agent |
| **Testing** | Tests pass, awaiting QA review | Tester agent | QA Reviewer agent |
| **Done** | QA passed (Story) or fix complete (Bug issue) | QA Reviewer / Bug Fixer | — |

## Transition Rules

- Transitions go **forward only**, except:
  - Tester/QA can move a Story **back** to **In Progress** when a defect is found (a child Bug issue is created in parallel)
  - Bug Fixer moves a Story **back** to **In Review** after pushing the fix
- The orchestrator discovers transition IDs dynamically at startup using `mcp__mcp-atlassian__jira_get_transitions`
- The Transition Map passed to agents has keys for each status: `"Backlog"`, `"Selected for Development"`, `"In Progress"`, `"In Review"`, `"Testing"`, `"Done"`.

## Bug Lifecycle

A Bug is a separate Jira issue (issuetype=Bug) parented to a Story. It has its own status independent of the parent. **Exception (defects with no single Story owner):** Phase 8 CUJ-replay defects parent to the QBV (or the most-likely-culprit Story), and hotfix / tiny-feature reconciliation may parent to the Epic (see `commands/sdlc.md` Phase 8 and `entrypoint-modes.md`). Prefer a Story parent whenever one clearly owns the defect.

1. Tester or QA finds a defect (or the user reports one).
2. They create a **Bug issue** with `issue_type: "Bug"` and `parent: {STORY-KEY}`. The Bug starts in `Backlog` / `To Do`.
3. The parent Story is transitioned **back to "In Progress"** — it's actively being fixed again.
4. The Bug Fixer agent picks up the Bug:
   - Transitions the Bug to **In Progress**
   - Fixes the code, pushes the commit
   - Transitions the Bug to **Done**
   - Transitions the parent Story back to **In Review** (re-enters Tester → QA loop)
5. Tester re-runs (Story → Testing on pass, → In Progress + new Bug on another fail).

**Detecting active bug work on a Story:** the orchestrator queries child issues, not parent status.

```
JQL: parent = {STORY-KEY} AND issuetype = Bug AND status != Done
```

A Story is "in the bug-fix loop" if it has any non-Done child Bug. Don't infer this from the Story's own status.

## Max Retry

A Story can go through the In-Progress (fix) → In Review → Testing loop at most **3 times** with a child Bug each round. After that, the orchestrator flags it for human review and moves on.

## Fast Mode — Ledger Phase ↔ Jira Status

In fast mode (`Jira: off`, see `SKILL.md` §2.6) there are no Jira tickets during the build. The **Fast Work Ledger** replaces the Jira status field: each work unit carries a `phase` value that the orchestrator advances from agent return text, exactly where a Jira transition would fire in normal mode. The mapping is 1:1, so a wave can be faithfully reconstructed at reconciliation (see `sdlc-jira-creator` Reconcile Mode).

| Ledger `phase` | Equivalent Jira status | Set by | Set from agent return |
|---|---|---|---|
| `architected` | Backlog (spec written, pre-design) | orchestrator | architect `Status: architected` |
| `ready` | Selected for Development | orchestrator | architect/designer/integrator — unit cleared for dev |
| `in-progress` | In Progress | orchestrator | developer spawned (or bug-fixer active on a `bugs[]` entry) |
| `in-review` | In Review | orchestrator | developer `Status: in-review` + `PR:` |
| `testing` | Testing | orchestrator | tester `Verdict: PASS` |
| `done` | Done | orchestrator | qa-reviewer `Verdict: APPROVED` |
| `blocked` | (no Jira equivalent — surfaced to user) | orchestrator | 3rd failed bug-fix loop on the unit |

**Bug entries.** A ledger `bugs[]` entry (`status: open|fixed`, `loop: n`) is the fast-mode stand-in for a child Bug issue. `open` ⇔ a non-Done child Bug with the parent Story back in `in-progress`; `fixed` ⇔ the child Bug Done and the unit re-routed to `in-review`. The same **3-loop cap** applies, counted from the highest `bugs[].loop` on the unit rather than by querying child issues.

**At reconciliation**, `sdlc-jira-creator` (Reconcile Mode) creates each unit's Story at Backlog and walks it forward to the ledger `phase`'s equivalent status using this table, and creates one child Bug (final status Done) per `bugs[]` entry. A `blocked` unit is left at the furthest status its open bug reached, with a note.
