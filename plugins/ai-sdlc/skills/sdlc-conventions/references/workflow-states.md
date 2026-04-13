# AI-SDLC Workflow States

## Status Definitions

| Status | Meaning | Entered By | Exited By |
|--------|---------|------------|-----------|
| **To Do** | Story created, not yet designed | Jira Creator agent | Architect agent |
| **Planning** | Architect is designing the tech spec | Architect agent (start) | Architect agent (end) |
| **Ready for Dev** | Tech spec complete, implementation can begin | Architect agent | Developer agent |
| **In Progress** | Developer is actively writing code | Developer agent (start) | Developer agent (end) |
| **In Review** | Code written and PR opened, awaiting tests | Developer agent | Tester agent |
| **Testing** | Tests written and passing, awaiting QA review | Tester agent | QA Reviewer agent |
| **Done** | QA passed, story complete | QA Reviewer agent | — |
| **Bug** | Issue found by tester or QA, needs fixing | Tester or QA agent | Bug Fixer agent |

## Transition Rules

- Transitions go **forward only**, except:
  - Bug Fixer moves a story **back** to "In Review" after fixing
  - QA Reviewer can move a story **back** to "Bug" if issues found
- The orchestrator discovers transition IDs dynamically at startup using `getTransitionsForJiraIssue`
- If the Jira project uses different status names, the orchestrator maps them at init time

## Bug Lifecycle

1. Tester or QA finds an issue
2. Creates a **Bug sub-task** under the parent Story
3. Transitions the parent Story to "Bug" status
4. Bug Fixer agent picks up the Bug sub-task
5. Fixes the code, runs tests
6. Transitions Bug sub-task to "Done"
7. Transitions parent Story back to "In Review"
8. Tester re-validates

## Max Retry

A story can go through the Bug → Fix → Re-test loop at most **3 times**. After that, the orchestrator flags it for human review and moves to the next story.

## Fallback Statuses

If the Jira project does not have all these statuses, use this minimal mapping:
- To Do, In Progress, Done (standard Jira defaults)
- Use Jira comments to track sub-states (e.g., "## Status: Ready for Dev")
