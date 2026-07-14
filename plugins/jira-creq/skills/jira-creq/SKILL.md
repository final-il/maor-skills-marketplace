---
name: jira-creq
description: |
  Create tickets in the CREQ (CSI Request) Jira project the right way the first time. CREQ has
  non-obvious required fields (Zone, Does Impact Production?) and non-standard issue types
  (Ongoing Request / Trouble Ticket — there is NO "Task"), so a naive create call fails.

  Trigger whenever the user asks to create, open, file, or batch-create one or more tickets/issues
  /requests in CREQ or "CSI Request", mentions a CREQ-#### key, or asks about CREQ fields, issue
  types, zones, or assignees. Also trigger for LiteLLM / GenAI infra / SPENT / Grafana-monitoring
  work items headed to CREQ, since those are the common case.
---

# Creating CREQ (CSI Request) Jira Tickets

The CREQ project — display name **CSI Request**, on `https://jira-final-il.atlassian.net` — rejects the
"obvious" create call two ways: it has no `Task` issue type, and it has two required custom fields that
aren't part of any default create form. This skill encodes the working shape so a create succeeds on the
first attempt instead of failing, discovering the fields, and retrying.

Tickets are created through the `mcp__mcp-atlassian__jira_*` tools (the standalone mcp-atlassian server).

## The one-shot recipe

To create a CREQ ticket, call `jira_create_issue` with:

- `project_key`: `"CREQ"`
- `issue_type`: `"Ongoing Request"` (the normal choice — see issue types below)
- `summary`, `description`: as given (description is Markdown)
- `assignee`: the person's **email** (most reliable identifier — see assignees below)
- `additional_fields`: **both** required custom fields, or the create is rejected:

```json
{
  "customfield_10789": {"value": "<Zone>"},
  "customfield_10821": {"value": "<No|Minor|Major>"}
}
```

`customfield_10789` is **Zone** and `customfield_10821` is **Does Impact Production?**. Both are single-select
`option` fields, so they must be passed as `{"value": "..."}`, not a bare string.

If you omit them, the API returns exactly:

```
Does Impact Production? is required.
Zone is required.
```

That error is the signature of this project — if you see it, you forgot the two custom fields.

## Issue types

`jira_get_project_issue_types` for CREQ returns only:

| Name | ID | Notes |
|---|---|---|
| Ongoing Request | `10410` | **Default.** Standard work / change / enablement request. Use this unless told otherwise. |
| Trouble Ticket | `10411` | Incident / problem report. Use only when the item is a fault being reported, not work being requested. |
| Sub-task | `10016` | Subtask under a parent; needs `parent` in `additional_fields`. |

There is deliberately **no `Task` / `Story` / `Bug`** type here. Passing one of those fails. When unsure between
Ongoing Request and Trouble Ticket, ask the user — don't guess, because it changes the queue the ticket lands in.

## Required custom fields (values)

Fetch fresh with `jira_get_field_options` if you suspect the list changed; these are the values as of 2026-07.

**Zone** (`customfield_10789`): `Cloud`, `HelpDesk`, `Labs`, `Office`, `Production`, `Research`, `TBD`

Rule of thumb the user has used: **internal / lab-side work → `Labs`; external / customer-facing cloud work → `Cloud`.**
Don't hard-code this — confirm with the user when a ticket's environment is ambiguous or spans both.

**Does Impact Production?** (`customfield_10821`): `No`, `Minor`, `Major`

Config/enablement/monitoring changes are usually `No` or `Minor`; ask the user rather than assuming `Major`.

Neither value is safe to invent silently — production impact and zone are operationally meaningful. If the user
hasn't specified and it isn't obvious, ask a short clarifying question (offer the option lists) before creating.

Other useful-but-optional CREQ fields (all live under `additional_fields`): `priority` (defaults to **Low** —
bump explicitly if the work is urgent), `customfield_10001` (Team), `customfield_10257` (Quarter),
`customfield_10268` (Year), `customfield_10105` (IT Service), `duedate`, `customfield_10015` (Start date).

## Resolving assignees

Assignee is an email/name/accountId. **Prefer email** — display names collide (e.g. many "Ben …" people).
When given only a display name, resolve it first with `jira_search_assignable_users`
(`project_key: "CREQ"`, `query: "<name>"`) and take the `email` from the match. Known recurring assignees:

| Name | Email |
|---|---|
| Ben Libster | `benl@final.co.il` |
| Yanir Shagan | `yanirs@final.co.il` |

If a name is ambiguous (search returns several), show the candidates and ask — do not assume the first hit.

## Creating many tickets — avoid the batch trap

**`jira_batch_create_issues` has failed silently on CREQ** — it returned "Command failed with no output" and
created *nothing*, likely because it doesn't populate the two required custom fields. Do **not** rely on it here.

Instead, create tickets with **parallel individual `jira_create_issue` calls** (multiple tool calls in one
message). This is fast, each carries the required fields, and each returns a confirmed key.

**Always verify after any create failure.** If a create (especially a batch) errors or returns no output, run a
quick `jira_search` before retrying so you don't create duplicates:

```
project = CREQ AND summary ~ "<distinctive words>" AND created >= -1h ORDER BY created DESC
```

## After creating

Report back a compact table of `key | summary | assignee | zone` with clickable
`https://jira-final-il.atlassian.net/browse/CREQ-####` links, and flag anything you defaulted (priority Low,
a guessed zone, a cross-environment ticket) so the user can correct it.

## Worked example

User: *"Create a CREQ ticket: Enable DeepSeek in External LiteLLM, assign Ben Libster."*

```
jira_create_issue(
  project_key = "CREQ",
  summary     = "Enable DeepSeek in External LiteLLM",
  issue_type  = "Ongoing Request",
  description = "Enable the DeepSeek model in the external LiteLLM environment.",
  assignee    = "benl@final.co.il",
  additional_fields = {
    "customfield_10789": {"value": "Cloud"},   // external → Cloud
    "customfield_10821": {"value": "No"}        // enablement, no prod impact
  }
)
→ CREQ-3706 created (Open, Ongoing Request, assignee Ben Libster)
```
