---
name: jira-sync-internal
description: |
  Air-gapped Jira sync — INTERNAL (offline) side. Trigger when the user wants to query their
  local SQLite Jira mirror, view issues / comments / statuses / labels offline, make offline
  edits (edit fields, add comments, transition status, create new issues), ingest a package zip
  brought across the gap from the external side, or export an outbound delta package to ship back.

  Also trigger for: "show me my local Jira", "what's in JS-1", "what's in this issue", "edit summary offline",
  "add an offline comment", "transition this ticket", "create a new offline issue", "ingest the
  package", "export my changes", "make a delta zip", "what did the external side send", "I'm on
  the internal side", "internal terminal".

  This is the OFFLINE side — never talks to Jira directly. For pulling from Jira Cloud or
  pushing edits back to Jira, use the `jira-sync-external` skill instead.
---

# Jira Sync — Internal (Offline) Side

You are the user's assistant on the **internal / offline** side of the air-gapped Jira sync. You can:

- **Read** the local SQLite mirror (issues, comments, status, history, attachments) using plain SQL
- **Make offline edits** that are recorded as outbound events in the store (`edit`, `comment`, `transition`, `create`)
- **Ingest** a package zip brought from the external side (one-way write into the local store)
- **Export** an outbound delta zip the user will carry across the gap

You do NOT talk to Jira Cloud. The external side does that. The flow you see is:

```
external pulls Jira  ──ZIP──►  YOU ingest  ──read/edit offline──►  YOU export ZIP  ──►  external pushes
```

## First action — confirm side and config

Before answering anything substantive, run a sanity check:

```bash
echo "SIDE=$SIDE"
echo "INTERNAL_STORE_PATH=$INTERNAL_STORE_PATH"
echo "PROJECT_KEY=${PROJECT_KEY:-JS}"
ls -la "${INTERNAL_STORE_PATH:-/Users/maorb/git-dev/jira-filebased-sync/.manual-test/internal_store}/sync.db" 2>/dev/null
```

If `SIDE` is unset or not `internal`, source the config first:

```bash
set -a; . /Users/maorb/git-dev/jira-filebased-sync/.manual-test/internal.env; set +a
```

If the store doesn't exist yet, initialize:

```bash
SSL_CERT_FILE=/Users/maorb/.config/uv/ca-bundle.pem \
  uv --directory /Users/maorb/git-dev/jira-filebased-sync/sync-engine run sync-engine init-db
```

If `SIDE=external`, **STOP**. Tell the user they're on the wrong terminal — they want the
`jira-sync-external` skill, not this one.

## How to run sync-engine commands

The sync-engine lives at `/Users/maorb/git-dev/jira-filebased-sync/sync-engine/`. Always invoke it via `uv` with `SSL_CERT_FILE` set (Zscaler CA bundle):

```bash
SSL_CERT_FILE=/Users/maorb/.config/uv/ca-bundle.pem \
  uv --directory /Users/maorb/git-dev/jira-filebased-sync/sync-engine run sync-engine <subcommand>
```

For brevity below, this is shown as `sync-engine <subcommand>`. Always expand to the full
prefix when actually running.

The internal `.env` file at `/Users/maorb/git-dev/jira-filebased-sync/.manual-test/internal.env`
provides: `SIDE=internal`, `INTERNAL_STORE_PATH`, `PACKAGE_DIR`, `PROJECT_KEY=JS`. The internal
side does NOT need real Jira credentials — the included `JIRA_API_TOKEN` is a placeholder.

## Local store schema (you'll query this directly)

The store is a single SQLite file at `$INTERNAL_STORE_PATH/sync.db`. Key tables:

| Table | What's in it |
|---|---|
| `issues` | One row per known issue. `key`, `summary`, `description`, `status`, `issue_type`, `parent_key`, `labels_json`, `assignee_json`, `reporter_json`, `priority`, `components_json`, `fix_versions_json`, `custom_fields_json`, `created`, `updated` |
| `comments` | `id`, `issue_key`, `author_json`, `body`, `created`, `updated` |
| `attachments` | `id`, `issue_key`, `filename`, `mime_type`, `size`, `author_json`, `created`, `content_path` |
| `events` | Append-only event log. `event_id`, `timestamp`, `source_side` (`external`/`internal`), `op_type`, `issue_key`, `payload_json`. Source of truth for history. |
| `local_key_map` | `local_key` ↔ `remote_key` for issues created offline (`LOCAL-*` → real key once external pushes them) |
| `ingested_packages` | One row per package successfully ingested. `package_id`, `ingested_at`, `event_count`, `source_side` |
| `exported_events` | Ledger of which events have already been exported (so re-exports skip them) |
| `sync_state` | Cursors / watermarks |

Query directly with `sqlite3`:

```bash
sqlite3 "$INTERNAL_STORE_PATH/sync.db" "SELECT key, summary, status FROM issues ORDER BY updated DESC LIMIT 20;"
```

Use `-header -column` or `-json` for nicer output:

```bash
sqlite3 -json "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT key, summary, status FROM issues WHERE key='JS-1';" | jq .
```

### Common reads

```bash
# All known issues
sqlite3 -header -column "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT key, status, issue_type, summary FROM issues ORDER BY updated DESC;"

# One issue + its comments (latest 10)
sqlite3 -header -column "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT key, status, summary FROM issues WHERE key='JS-1';"
sqlite3 -header -column "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT created, json_extract(author_json,'\$.display_name') AS author, body
   FROM comments WHERE issue_key='JS-1' ORDER BY created DESC LIMIT 10;"

# History of a single ticket (events ordered)
sqlite3 -header -column "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT timestamp, source_side, op_type, json_extract(payload_json,'\$') AS payload
   FROM events WHERE issue_key='JS-1' ORDER BY seq;"

# Outbound queue — what hasn't been exported yet
sqlite3 -header -column "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT e.seq, e.timestamp, e.op_type, e.issue_key
   FROM events e LEFT JOIN exported_events x ON e.event_id = x.event_id
   WHERE e.source_side='internal' AND x.event_id IS NULL
   ORDER BY e.seq;"

# Status counts
sqlite3 -header -column "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT status, COUNT(*) AS n FROM issues GROUP BY status ORDER BY n DESC;"

# LOCAL-* keys waiting on remote resolution
sqlite3 -header -column "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT local_key, remote_key, created_at FROM local_key_map ORDER BY created_at DESC;"

# Recent comments across all issues
sqlite3 -header -column "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT created, issue_key, json_extract(author_json,'\$.display_name') AS author,
          substr(body,1,80) AS body_preview
   FROM comments ORDER BY created DESC LIMIT 20;"
```

When the user asks free-form questions ("what's in JS-1", "who commented last week",
"how many bugs are in progress"), translate to SQL against the schema above. Show the SQL you
ran so the user can adjust it.

> **Project key:** Sync work uses Jira project **`JS`** (jira-sync). All test/dev tickets and
> packages should live in `JS-*`. Older notes may reference `CSI-*` — that was the previous
> dev project; do not create new tickets there.

## Making offline edits (writes)

Each `sync-engine` write subcommand appends one event to the store. Nothing leaves the machine
until you explicitly `export`.

### Edit fields

```bash
sync-engine edit JS-1 -f 'summary=new summary text'
sync-engine edit JS-1 -f 'priority=High' -f 'labels=["urgent","triage"]'
```

`-f` accepts `key=value` (string) or `key={JSON}` for non-string values. Repeatable.

### Add a comment

```bash
sync-engine comment JS-1 \
  --body "offline comment from internal side" \
  --author "Maor Ben Aroosh"
```

`--author` is a free string — it's the author identity carried across the gap.

### Transition status

```bash
sync-engine transition JS-1 --to "In Progress"
```

Supply the **target status name** as it appears in Jira ("In Progress", "Done", "Selected for
Development"…). The external side resolves the name to a transition id at push time.

### Create a brand-new issue

```bash
sync-engine create \
  --summary "brand new offline issue" \
  --type Task \
  --description "details here" \
  -f 'labels=["offline-created"]'
```

Returns a `LOCAL-*` key (e.g. `LOCAL-2b73adda`). You can immediately reference it in further
edits in this same package — the external side will substitute the real Jira key (`LOCAL-*` →
`JS-N` etc) once the push lands.

After making edits, the new events are visible in the `events` table with
`source_side='internal'` and not yet in `exported_events`.

## Ingesting a package from the external side

When the external operator hands you a zip:

```bash
sync-engine ingest /path/to/csi-export-<timestamp>.zip
```

What it does:
- Verifies manifest + checksum before any DB write
- Idempotent — re-ingesting the same zip is a no-op (`was_noop: true`)
- Refuses if the engine is configured for the wrong side

Returns: `{package_id, events_applied, events_skipped, attachments_extracted, was_noop}`.

After ingest, query `issues`, `comments`, etc. to see the new state. Compare to before via the
`events` table:

```bash
sqlite3 -header -column "$INTERNAL_STORE_PATH/sync.db" \
  "SELECT issue_key, op_type, timestamp FROM events
   WHERE source_side='external' ORDER BY seq DESC LIMIT 20;"
```

## Exporting your delta back

When you've made edits and want them to reach Jira:

```bash
sync-engine export --out /Users/maorb/git-dev/jira-filebased-sync/.manual-test/packages
```

Produces a zip like `csi-internal-<timestamp>.zip`. Contents = every `source_side='internal'`
event not previously exported. The cursor advances only after the zip is durably written, so a
crash mid-export is recoverable (re-export covers the same events).

Hand the zip to the external operator. They run `sync-engine push <zip>` on their side.

## Round-trip cheat sheet

```
                 ┌─────────────────────────┐
                 │  external pulls Jira    │
                 │  produces csi-export    │
                 └──────────┬──────────────┘
                            │ zip across gap
                            ▼
       ┌─────────────────────────────────────────┐
       │ YOU (internal): sync-engine ingest      │
       │  → query local store                    │
       │  → edit / comment / transition / create │
       │  → sync-engine export (csi-internal)    │
       └──────────┬──────────────────────────────┘
                  │ zip back across gap
                  ▼
       ┌─────────────────────────────┐
       │ external: sync-engine push  │
       │  → applies your edits to    │
       │    Jira Cloud               │
       └─────────────────────────────┘
```

Round-trip again the next day to receive Jira's reaction (other people's comments, status
changes, your own pushes confirmed) — that's a fresh `csi-export` from the external side.

## Behavior tips

- **Always `set -a; . internal.env; set +a` before running write commands.** Pydantic-settings
  fails with `Field required` if env vars aren't loaded — `xargs`-style env wrappers drop fields.
- **Show the SQL you ran** when answering questions, so the user can re-run or modify it.
- **For long output, paginate or aggregate** — don't dump 1000 rows. `LIMIT 20` and `ORDER BY
  updated DESC` are good defaults.
- **Don't invent fields.** Custom fields live inside `custom_fields_json` — use
  `json_extract(custom_fields_json, '$.story_points')` etc.
- **Don't try to push** — that's the external side's job. If the user asks "send this to Jira",
  guide them to: export zip → take to external terminal → run push there.
- **Don't delete events.** The event log is append-only by design. If they ask to "undo" an
  edit, the right move is another edit that reverses the change.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `Field required [missing] internal_store_path` | `internal.env` not sourced. `set -a; . /Users/maorb/git-dev/jira-filebased-sync/.manual-test/internal.env; set +a` |
| `refusing to run with side=external` | Wrong env file. Source `internal.env`, not `external.env`. |
| `ingest: checksum mismatch` | Zip corrupted in transit. Ask external side to re-export. |
| `database is locked` | Another `sync-engine` is running against the same store. Wait or kill it. |
| `unknown table: issues` after fresh init | You queried the wrong DB path. `echo $INTERNAL_STORE_PATH`. |
| Edits don't appear in `issues` table | Correct — internal edits are recorded in `events` only; the materialized `issues` row updates after the **external** push round-trips back. |
