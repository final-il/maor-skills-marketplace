---
name: airlock-jira
description: |
  Read and update Jira from the internal (island) network using the `airlock-jira` CLI. On this network
  there is NO direct Jira access — no internet, no credentials — so `airlock-jira` is the ONLY way to
  reach Jira: it relays every call internal → Aurora → S3 → external worker → real Jira and back. So ANY
  request to touch Jira here should use this skill.

  Trigger whenever the user wants to get / look up / read a Jira ticket or its status/fields/raw JSON
  (keys like CREQ-2971, CSI-780), comment on a ticket, transition / move / close a ticket, or hit any
  Jira REST endpoint — whether or not they say "airlock" or "through the boundary". Also trigger when
  the user runs `airlock-jira`, when a run fails ("SSM tunnel not up", expired creds, a worker timeout)
  and they need the fix, or when they ask how to test the passthrough end-to-end.

  Do NOT trigger for pure infrastructure questions unrelated to running a Jira call — Aurora/SSM/squid/
  worker daemon internals, Terraform, or debugging the boundary's plumbing itself.
---

# Using `airlock-jira` — Jira through the Airlock boundary

`airlock-jira` is a CLI that lets the internet-isolated internal network read and update Jira. On this
network it is the **only** way to reach Jira — there's no outbound internet, no Jira credential, and no
direct API/MCP — so every Jira interaction goes through it. Each call is submitted as `airlock_producer`
into an Aurora control-plane table over an SSM port-forward tunnel; an external worker in account 913
picks it up, adds the Jira token, calls real Jira through an egress proxy, sanitizes the response, and
hands it back. The internal side never opens an outbound socket and never sees the token.

Because it crosses a real trust boundary and can mutate live tickets, treat it like a production tool:
run the preflight, prefer reads, and confirm before writes.

## The command

`airlock-jira` is on `PATH` (a wrapper at `~/.local/bin/airlock-jira`). The wrapper sets the AWS
environment and **preflights the tunnel and credentials for you** before running the Python CLI, so
you usually just call it and read its output.

```
# reads (GET)
airlock-jira <ISSUE-KEY>                       # e.g. airlock-jira CREQ-2971  (bare key == get)
airlock-jira <ISSUE-KEY> --fields summary,status,assignee
airlock-jira get --path /rest/api/3/myself     # arbitrary read-only REST path
airlock-jira <ISSUE-KEY> --raw | jq .          # raw JSON body only, for piping

# search (JQL) — a read; use the /search/jql endpoint (the old /rest/api/3/search is REMOVED)
airlock-jira get --path '/rest/api/3/search/jql?jql=project%20%3D%20CSI%20AND%20text%20~%20%22jiralyzer%22&fields=summary,status,issuetype,assignee&maxResults=50'
# → parse with: airlock-jira get --path '…/search/jql?…' --raw | jq -r '.issues[] | "\(.key)  \(.fields.status.name)  \(.fields.summary)"'

# writes (POST — mutate a live ticket; prompt for confirmation unless --yes)
airlock-jira comment <ISSUE-KEY> "text"        # add a comment (plain text → ADF)
airlock-jira transitions <ISSUE-KEY>           # list available transitions (this is a read)
airlock-jira transition <ISSUE-KEY> Done       # by status name (resolved to a transition id)
airlock-jira transition <ISSUE-KEY> 41 --yes   # by raw transition id, no prompt
```

Progress and summaries go to **stderr**; the JSON body goes to **stdout**, so `--raw | jq` stays
clean. Each run mints a fresh idempotency key, so it's always a real Jira call, not a cached dedup hit.
A read returns in a few seconds; give a slow worker more time with `--timeout <seconds>` (default 120).

## Reads are safe; writes mutate live tickets

`comment` and `transition` change a real ticket. The CLI prompts `[y/N]` before a write and refuses a
`--yes`-less write on non-interactive stdin (so a piped command can't silently mutate).

**When you (Claude) run a write on the user's behalf, get explicit confirmation of the specific action
first** — which ticket, what comment text, which target status — then pass `--yes` to run it
non-interactively. Never fire an unrequested or speculative write. If the user only asked to *read*,
never escalate to a write. This matches the standing rule: confirm before sending anything outward.

For `transition`, prefer a **status name** (`Done`, `In Progress`) over a raw id — the CLI lists the
issue's transitions through the boundary and resolves the name, which is robust across projects. If
you're unsure what's available, run `airlock-jira transitions <ISSUE>` first and show the user.

## Preflight — what the wrapper checks, and how to fix failures

The wrapper exits early with a clear message if a prerequisite is missing. Don't try to work around
these — surface the fix to the user.

| Symptom (exit code) | Meaning | Fix |
| --- | --- | --- |
| `SSM tunnel not up on localhost:15432` (3) | The port-forward to Aurora is down | The wrapper prints the exact `aws ssm start-session …` command. The user runs it in another terminal (or via `!` in-session) and leaves it open. |
| `AWS creds … missing or expired` (4) | STS creds for profile `airlock-054` expired | User pastes fresh `airlock-054` creds into `/tmp/.airlock-aws-creds`. |
| Hangs, then a time-out / `ResultTimeout` | External worker (account 913) not claiming | Worker daemon likely down — nothing the user can fix locally; escalate. |
| `NotAuthorized` on submit | Connecting principal lacks the passthrough grant | Should not happen for the shipped CLI (it connects as `airlock_producer`); flag it. |

These preconditions (tunnel, creds, worker) are environmental and short-lived — the PoC creds are
re-pasted periodically. If a call fails preflight, report which check failed and the fix, rather than
retrying blindly.

## How to help the user

On this network there is no other route to Jira — no direct API, no MCP, no browser — so *any* request
that touches a Jira ticket resolves to an `airlock-jira` call. Don't wait for the words "airlock" or
"through the boundary"; "what's the status of CREQ-2971", "comment on CSI-780", and "close this ticket"
all mean the same thing here.

- **Read / look up / check a ticket** ("what's CREQ-2971", "status of CSI-780", "pull the raw JSON")
  → `airlock-jira CREQ-2971` (add `--fields` if they name specific fields; `--raw | jq` to extract one
  value; `get --path /rest/api/3/...` for an arbitrary read-only endpoint).
- **Find / list / search tickets** ("all jiralyzer tickets in CSI", "open bugs in PROJ") → a JQL search
  via `get --path '/rest/api/3/search/jql?jql=<url-encoded JQL>&fields=…&maxResults=50'`. Use
  `/search/jql` — the legacy `/rest/api/3/search` is removed and returns a migration error. Results are
  paged: the response's `isLast` is `false` when there's more, so page with `nextPageToken` (or a
  higher `maxResults`) and tell the user when you've capped the list rather than implying it's complete.
- **Comment on / update a ticket** → confirm the exact text, then
  `airlock-jira comment CSI-780 "…" --yes`.
- **Move / transition / close a ticket** → confirm intent, then
  `airlock-jira transition CSI-780 Done --yes` (run `transitions` first if the target status is
  uncertain).
- **"how do I test airlock-jira / the passthrough end-to-end?"** → have them run a read first
  (`airlock-jira CREQ-2971`) to prove the loop, then a `transitions` read, then a guarded write.

Report Jira's HTTP status and a short summary. Never paste a Jira token or any secret into output or a
ticket — the boundary is designed so you never see one; keep it that way.
