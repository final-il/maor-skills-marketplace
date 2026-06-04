---
name: jira-sync-external
description: |
  Air-gapped Jira sync — EXTERNAL (online) side. Trigger when the user wants to pull from Jira
  Cloud into the local SQLite mirror, query the external store, export an outbound package zip
  to ship to the internal side, ingest a package brought back from the internal side, or push
  internal-side edits into Jira Cloud.

  Also trigger for: "pull from Jira", "sync from Jira Cloud", "export the package",
  "push to Jira", "ingest the internal package", "what does the external store have",
  "I'm on the external side", "online terminal", "send the delta to Jira", "did the push land".

  This is the ONLINE side — talks to Jira Cloud directly via REST API. For making OFFLINE edits
  or ingesting external-side packages, use the `jira-sync-internal` skill instead.
---

# Jira Sync — External (Online) Side

You are the user's assistant on the **external / online** side of the air-gapped Jira sync. You can:

- **Pull** from Jira Cloud into the local SQLite store (`/rest/api/3/search/jql` + nextPageToken)
- **Read** the external store (issues, comments, attachments, history) using plain SQL
- **Export** an outbound package zip to hand to the internal operator
- **Ingest** a package zip the internal operator hands back
- **Push** internal-side edits (from an ingested package) into Jira Cloud

You are the only side that touches Jira directly. The flow is:

```
Jira ──pull──► YOU ──ZIP──► internal ──edits──► ZIP back ──► YOU push ──► Jira
```

## First action — confirm side and config

Before answering anything substantive, run a sanity check:

```bash
echo "SIDE=$SIDE"
echo "JIRA_URL=$JIRA_URL"
echo "EXTERNAL_STORE_PATH=$EXTERNAL_STORE_PATH"
echo "PROJECT_KEY=${PROJECT_KEY:-JS}"
ls -la "${EXTERNAL_STORE_PATH:-/Users/maorb/git-dev/jira-filebased-sync/.manual-test/external_store}/sync.db" 2>/dev/null
```

If `SIDE` is unset or not `external`, source the config first:

```bash
set -a; . /Users/maorb/git-dev/jira-filebased-sync/.manual-test/external.env; set +a
```

If the store doesn't exist yet, initialize:

```bash
SSL_CERT_FILE=/Users/maorb/.config/uv/ca-bundle.pem \
  uv --directory /Users/maorb/git-dev/jira-filebased-sync/sync-engine run sync-engine init-db
```

Quick auth probe (don't actually pull yet — too many events):

```bash
SSL_CERT_FILE=/Users/maorb/.config/uv/ca-bundle.pem \
  curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    "$JIRA_URL/rest/api/3/myself" | jq -r '.displayName // .errorMessages'
```

If `SIDE=internal`, **STOP**. Tell the user they're on the wrong terminal — they want the
`jira-sync-internal` skill, not this one.

## How to run sync-engine commands

The sync-engine lives at `/Users/maorb/git-dev/jira-filebased-sync/sync-engine/`. Always invoke it via `uv` with `SSL_CERT_FILE` set (Zscaler CA bundle):

```bash
SSL_CERT_FILE=/Users/maorb/.config/uv/ca-bundle.pem \
  uv --directory /Users/maorb/git-dev/jira-filebased-sync/sync-engine run sync-engine <subcommand>
```

For brevity below, this is shown as `sync-engine <subcommand>`. Always expand to the full
prefix when actually running.

The external `.env` file at `/Users/maorb/git-dev/jira-filebased-sync/.manual-test/external.env`
provides: `SIDE=external`, `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`, `EXTERNAL_STORE_PATH`,
`PACKAGE_DIR`, `PROJECT_KEY=JS`. Treat the API token as secret — never paste it into Jira
comments, never commit `.env`.

## Pulling from Jira Cloud

```bash
sync-engine pull
```

What it does:
- Builds JQL: `project = $PROJECT_KEY [AND updated >= <cursor>] ORDER BY updated ASC`
- Calls `GET /rest/api/3/search/jql` with `expand=changelog,renderedFields`
- Paginates via `nextPageToken` (the deprecated `/rest/api/3/search` is NOT used)
- Diffs each issue against the local store and appends events
- Advances the `external_pull_cursor` watermark only on success (re-runs are idempotent)

Output: `{"issues_seen": N, "events": M, "skipped_duplicates": K, "last_updated": "...", "project_key": "JS"}`

> **Project key:** Sync work uses Jira project **`JS`** (jira-sync). All test/dev tickets and
> packages should live in `JS-*`. Older notes may reference `CSI-*` — that was the previous
> dev project; do not push or pull against it.

### Narrowing the pull (first-time on a big project)

The default JQL pulls the whole project. On the first run this can be hours. To narrow:

1. **Time-bounded first pull** — pre-seed the cursor:
   ```bash
   sqlite3 "$EXTERNAL_STORE_PATH/sync.db" \
     "INSERT INTO sync_state (key, value)
      VALUES ('external_pull_cursor',
              '{\"updated_after\": \"2026-05-01 00:00\", \"seen_event_ids\": [], \"last_exported_event_id\": null}');"
   ```
   Subsequent pulls advance from the new watermark.

2. **Single-ticket smoke test** — there is no `--jql` flag. Either pre-seed the cursor very
   recently (catches just the latest changes) or temporarily edit `_build_jql` in
   `sync-engine/src/sync_engine/jira/pull.py`. Don't ship that edit.

If the cursor needs a full reset, delete the row:
```bash
sqlite3 "$EXTERNAL_STORE_PATH/sync.db" "DELETE FROM sync_state WHERE key='external_pull_cursor';"
```

## Local store schema (you'll query this directly)

The store is a single SQLite file at `$EXTERNAL_STORE_PATH/sync.db`. Same schema as the internal
side — see the table list below for the columns you'll use most.

| Table | What's in it |
|---|---|
| `issues` | One row per known issue. `key`, `summary`, `description`, `status`, `issue_type`, `parent_key`, `labels_json`, `assignee_json`, `reporter_json`, `priority`, `components_json`, `fix_versions_json`, `custom_fields_json`, `created`, `updated` |
| `comments` | `id`, `issue_key`, `author_json`, `body`, `created`, `updated` |
| `attachments` | `id`, `issue_key`, `filename`, `mime_type`, `size`, `author_json`, `created`, `content_path` |
| `events` | Append-only event log. `event_id`, `timestamp`, `source_side` (`external`/`internal`), `op_type`, `issue_key`, `payload_json`. |
| `local_key_map` | `local_key` ↔ `remote_key` for issues created on the internal side |
| `ingested_packages` | One row per internal package successfully ingested |
| `exported_events` | Ledger of which events have already been exported to the internal side |
| `sync_state` | Cursors / watermarks (incl. `external_pull_cursor`) |

### Common reads

```bash
# All issues
sqlite3 -header -column "$EXTERNAL_STORE_PATH/sync.db" \
  "SELECT key, status, issue_type, summary FROM issues ORDER BY updated DESC LIMIT 50;"

# Single issue with comments
sqlite3 -header -column "$EXTERNAL_STORE_PATH/sync.db" \
  "SELECT key, status, summary FROM issues WHERE key='JS-1';"
sqlite3 -header -column "$EXTERNAL_STORE_PATH/sync.db" \
  "SELECT created, json_extract(author_json,'\$.display_name') AS author, body
   FROM comments WHERE issue_key='JS-1' ORDER BY created DESC LIMIT 10;"

# Pull cursor — what's the watermark?
sqlite3 "$EXTERNAL_STORE_PATH/sync.db" \
  "SELECT value FROM sync_state WHERE key='external_pull_cursor';" | jq .

# What's pending export to internal? (events not yet shipped)
sqlite3 -header -column "$EXTERNAL_STORE_PATH/sync.db" \
  "SELECT e.seq, e.timestamp, e.op_type, e.issue_key
   FROM events e LEFT JOIN exported_events x ON e.event_id = x.event_id
   WHERE x.event_id IS NULL
   ORDER BY e.seq;"

# Recent activity from Jira (events the pull added)
sqlite3 -header -column "$EXTERNAL_STORE_PATH/sync.db" \
  "SELECT timestamp, issue_key, op_type FROM events
   WHERE source_side='external' ORDER BY seq DESC LIMIT 20;"

# Push history — which internal events were applied
sqlite3 -header -column "$EXTERNAL_STORE_PATH/sync.db" \
  "SELECT timestamp, issue_key, op_type FROM events
   WHERE source_side='internal' ORDER BY seq DESC LIMIT 20;"
```

When the user asks free-form questions, translate to SQL. Show the SQL you ran so the user can
adjust it.

## Exporting a package for the internal side

```bash
sync-engine export --out /Users/maorb/git-dev/jira-filebased-sync/.manual-test/packages
```

Produces `csi-export-<timestamp>.zip`. Contents = every event since the last export cursor
(both `external` events from pulls and `internal` events from earlier internal-→external
round-trips, depending on the implementation — check the JSON output's `direction` field).
Cursor advances after the zip is durably written.

Hand the zip to the internal operator. They run `sync-engine ingest <zip>` on their side.

## Ingesting an internal-side package

When the internal operator hands you a `csi-internal-*.zip`:

```bash
sync-engine ingest /path/to/csi-internal-<timestamp>.zip
```

What it does:
- Verifies manifest + checksum before any DB write
- Idempotent (re-ingest is a no-op)
- Records the package in `ingested_packages`
- Appends `source_side='internal'` events into the local event log

After ingest, the events are sitting in the local store but **have not been pushed to Jira
yet**. That's the next step.

## Pushing internal-side edits to Jira

```bash
sync-engine push /path/to/csi-internal-<timestamp>.zip
```

What it does (per event, in `(timestamp, event_id)` order):

| Event type | Jira API call |
|---|---|
| `IssueUpdated` | `issue_update` (fields) |
| `CommentAdded` | `issue_add_comment` |
| `StatusTransitioned` | resolves status name → transition id, then `set_issue_status_by_transition_id` |
| `IssueCreated` | `create_issue`; binds returned key to the `LOCAL-*` key in `local_key_map` |

Returns: `{successes, failure_count, failures: [{event_id, error}], created_keys: {LOCAL-*: JS-*}}`.

Per-event failures are logged to push state and **do not abort the run**. Re-pushing the same
package is safe — already-applied events are skipped via the event-id ledger.

If `created_keys` is non-empty, the next pull will refresh the local issue rows for the new
`JS-*` keys.

### Verifying a push landed

After `push`, confirm with the live Jira API (don't trust just the local count):

```bash
# Show the live status of an issue you transitioned
SSL_CERT_FILE=/Users/maorb/.config/uv/ca-bundle.pem \
  curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    "$JIRA_URL/rest/api/3/issue/JS-1?fields=status,summary" \
  | jq '{key, status: .fields.status.name, summary: .fields.summary}'
```

For a fuller verification, run another `sync-engine pull` and diff the resulting events.

## Round-trip cheat sheet

```
       ┌────────────────────────────────────┐
       │ YOU (external):                    │
       │   sync-engine pull        ◄── Jira │
       │   sync-engine export → ZIP         │
       └─────────────┬──────────────────────┘
                     │ zip across gap
                     ▼
       ┌────────────────────────────────────┐
       │ internal: ingest → edit → export   │
       └─────────────┬──────────────────────┘
                     │ zip back across gap
                     ▼
       ┌────────────────────────────────────┐
       │ YOU (external):                    │
       │   sync-engine push <zip>   ──► Jira│
       │   sync-engine pull (verify)        │
       └────────────────────────────────────┘
```

## Behavior tips

- **Always `set -a; . external.env; set +a` before commands.** Pydantic-settings fails with
  `Field required` if env vars aren't loaded — `xargs`-style env wrappers drop fields.
- **Push is idempotent and partial-tolerant.** A failed event in a batch doesn't block the
  others. Look at `failures[]` in the JSON output and decide what to retry.
- **Don't paste the API token anywhere.** Not in commit messages, not in Jira comments, not in
  log output the user might share.
- **Show the SQL or `curl` you ran.** Lets the user reproduce or adjust.
- **Aggregate before dumping.** Don't paste 1000 rows. Use `LIMIT 20` + ordering.
- **Don't try to make offline edits here.** Use the `jira-sync-internal` skill on the offline
  terminal. The external side is for talking to Jira; offline edits belong on the internal side.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `Field required [missing] jira_email` | `external.env` not sourced. `set -a; . external.env; set +a` |
| `pull` returns `401` | API token expired or `JIRA_EMAIL`/token mismatch. Re-create at `id.atlassian.com` and update `.env`. |
| `pull` returns `429` | Rate-limited. Atlassian client retries with backoff — wait and retry. |
| `pull` returns `410 Gone` on `/rest/api/3/search` | Stale code; the engine should be using `/rest/api/3/search/jql`. Confirm `dev` is up to date (post CSI-521 fix). |
| `push: 'transition' identifier must be an integer` | Stale code; CSI-525 fix resolves this — confirm `dev` is up to date. |
| `push: no recorded remote Jira key` | Internal package referenced a `LOCAL-*` whose `IssueCreated` was never pushed. Push the originating internal package first. |
| `ingest: refusing to run with side=internal` | Wrong env file. Source `external.env`. |
| `uv sync` fails on TLS | `SSL_CERT_FILE=/Users/maorb/.config/uv/ca-bundle.pem` (absolute path; `~` doesn't expand inline). |
| Stale package zip | Delete from `$PACKAGE_DIR` and re-export — exports are deterministic per cursor. |
