---
name: jiralyzer
description: |
  Jira ticket analytics using natural language. Trigger when user asks about Jira ticket data,
  resolution times, re-assignment patterns, workload distribution, status transitions, ticket
  analytics, cycle time, or burndown metrics.

  Also trigger for: "analyze my Jira tickets", "show me ticket trends", "Jira dashboard",
  "ticket metrics", "cycle time analysis", "who has the most tickets", "resolution time by priority",
  "most re-assigned tickets", "status transition matrix", "workload distribution".
---

# Jiralyzer — Natural Language Jira Analytics

You help users analyze Jira ticket data using the `jiralyzer` CLI tool. You translate natural language questions into DuckDB SQL queries, execute them, interpret results, and generate visualizations.

## First-Time Setup

Before doing anything else, walk through these steps in order. **If any step fails, stop and tell the user what's wrong. Do not skip steps or attempt workarounds.**

### Step 1: Install `uv` if missing

```bash
which uv
```

If `uv` is not found, install it:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Verify it works:
```bash
uv --version
```

### Step 2: Check for `.env` file

```bash
cat /Users/maorb/git-dev/jiralyzer/.env 2>/dev/null
```

If the file does not exist, **stop and ask the user to provide values for these variables:**

| Variable | Purpose | Example |
|---|---|---|
| `JIRA_URL` | Jira instance URL | `https://your-site.atlassian.net` |
| `JIRA_EMAIL` | Jira API user email | `you@company.com` |
| `JIRA_API_TOKEN` | Jira API token | (from Atlassian account settings) |
| `REQUESTS_CA_BUNDLE` | CA certificate bundle path (for corporate proxy / Zscaler) | `/Library/CompanyCA/zscaler-root.pem` |
| `JIRALYZER_PROJECT_DIR` | Directory where jiralyzer is installed | `/Users/you/git-dev/jiralyzer` |
| `JIRALYZER_DB_PATH` | Full path to the DuckDB database file | `/Users/you/git-dev/jiralyzer/jiralyzer.db` |
| `JIRALYZER_CHART_DIR` | Directory where chart images are saved | `/Users/you/git-dev/jiralyzer/charts` |

Once the user provides the values, create the `.env` file at `$JIRALYZER_PROJECT_DIR/.env` with the values filled in. **Do not proceed until the file exists and all variables are populated.**

### Step 3: Load environment and install dependencies

Source the `.env` file, then run `uv sync` to install all Python dependencies (including DuckDB, Click, Matplotlib, etc.) into the project `.venv`:

```bash
set -a && source /Users/maorb/git-dev/jiralyzer/.env && set +a
cd "$JIRALYZER_PROJECT_DIR" && SSL_CERT_FILE="$REQUESTS_CA_BUNDLE" uv sync
```

### Step 4: Verify everything works

```bash
set -a && source /Users/maorb/git-dev/jiralyzer/.env && set +a

# jiralyzer CLI responds
cd "$JIRALYZER_PROJECT_DIR" && uv run jiralyzer --version

# chart output directory exists
mkdir -p "$JIRALYZER_CHART_DIR"
```

If `jiralyzer --version` fails, stop and report the error. Do not proceed.

## How to Run Commands

**All commands follow this pattern:**

```bash
set -a && source "$JIRALYZER_PROJECT_DIR/.env" && set +a && cd "$JIRALYZER_PROJECT_DIR" && uv run jiralyzer --db "$JIRALYZER_DB_PATH" <command> [args...]
```

For brevity, the rest of this document shows commands as:
```bash
jiralyzer --db "$JIRALYZER_DB_PATH" <command> [args...]
```

But **every invocation** must be wrapped with the source + cd prefix above.

## Workflow

When the user asks an analytics question:

### 1. Identify the target project and ensure its data is loaded

**This step is critical.** The database can contain multiple projects. You must determine which project the user is asking about and verify that project's data is present.

1. **Extract the project key** from the user's request (e.g., "analyze CSI-PM" → project key is `CSI-PM`, "CREQ tickets" → project key is `CREQ`).

2. **Check which projects are in the database:**
   ```bash
   jiralyzer --db "$JIRALYZER_DB_PATH" query "SELECT project, COUNT(*) as count FROM tickets GROUP BY project ORDER BY count DESC"
   ```

3. **If the requested project is NOT in the results, sync it first:**
   ```bash
   jiralyzer --db "$JIRALYZER_DB_PATH" sync --project <KEY>
   ```
   If sync fails, stop and report the error to the user. Do not attempt alternative data loading methods.

4. **If the database has no data at all**, ask the user for their Jira project key and run sync.

5. **Always filter queries by project** when multiple projects exist in the database. Add `WHERE project = '<KEY>'` to all queries. Do NOT mix data from different projects.

### 2. Understand the schema

Run `jiralyzer --db "$JIRALYZER_DB_PATH" schema` to get the current table structure. The database has 6 tables:

- **tickets** — One row per Jira issue (key, status, assignee, priority, resolution_days, etc.)
- **status_changes** — Status transition history from changelog
- **assignments** — Assignee change history from changelog
- **comments** — Issue comments
- **custom_fields** — Flexible key-value store for custom fields
- **worklogs** — Time tracking entries

See `references/schema.md` for detailed column descriptions and types.

### 3. Generate SQL

Translate the user's question into DuckDB SQL. Key considerations:

- DuckDB SQL is PostgreSQL-compatible with extensions (FILTER, MEDIAN, list functions)
- Array columns (labels, components, fix_versions, affects_versions) use `unnest()` for expansion
- `resolution_days` is a generated column — no need to compute it
- Use `references/query-patterns.md` for pre-built patterns matching common questions

### 4. Execute and interpret

```bash
# For data analysis
jiralyzer --db "$JIRALYZER_DB_PATH" query "<sql>" --format json

# For display to user
jiralyzer --db "$JIRALYZER_DB_PATH" query "<sql>" --format table
```

Always explain what the results mean in context. Don't just show numbers — provide insights.

### 5. Visualize when appropriate

If the results benefit from a chart, generate one:

```bash
jiralyzer --db "$JIRALYZER_DB_PATH" chart "<sql>" --type <chart_type> --x <col> --y <col> --output "$JIRALYZER_CHART_DIR/chart.png"
```

See `references/visualization-guide.md` for chart type selection guidance.

Chart types: `bar`, `line`, `pie`, `histogram`, `scatter`, `heatmap`, `stacked_bar`
Output formats: `.png` (static Matplotlib, **default — works reliably**), `.html` (interactive Plotly — may be blank behind corporate proxies)

### 6. Present narrative

Combine data and visualization into a concise report:
- Lead with the key insight
- Show the numbers that support it
- Link to the chart if generated
- Suggest follow-up questions

## Semantic Analysis (Categorize, Classify, Understand)

When the user asks to **categorize**, **classify**, **segment**, or **understand** their ticket data, do NOT fall back to SQL `LIKE` keyword matching. You are an LLM — use your semantic understanding.

### Approach

1. **Sample first, don't dump everything.** Query a representative batch (50-100 tickets) with summaries:
   ```bash
   jiralyzer --db "$JIRALYZER_DB_PATH" query "SELECT key, summary, issue_type, priority, status, assignee FROM tickets WHERE project = '<KEY>' ORDER BY key LIMIT 100" --format json
   ```

2. **Read and understand the summaries yourself.** Look for themes, patterns, team names, work types, naming conventions, repeated structures. You are the classifier — not SQL.

3. **Build categories from what you see.** After reading the sample, define categories (e.g., by domain, by work type, by repetitiveness). Then query more batches if needed to validate.

4. **Use SQL only for aggregation, not classification.** Once you've identified categories and the patterns that define them, you can use SQL `CASE WHEN` for counting. But the category definitions come from your semantic understanding, not from guessing keywords.

5. **Read ALL tickets, but in chunks.** It is critical to read every ticket for thorough analysis. Use batches of 50-100 with `OFFSET` and `LIMIT`. After each batch, note the patterns and categories you've found so far, then continue to the next batch. This prevents context overflow while ensuring complete coverage.

6. **Identify automation candidates** by looking for:
   - Near-identical summaries (repetitive tasks)
   - Formulaic naming patterns (e.g., "Q2 - {project}: {task} - {team}")
   - Recurring work types that follow a template

7. **Present findings incrementally.** Write your analysis text as you go — don't accumulate everything and try to output it all at once. After each major finding, share it with the user.

### What NOT to do
- Don't dump all tickets in a single query — read in chunks of 50-100 to manage context
- Don't use `LIKE '%keyword%'` as your primary classification strategy
- Don't skip reading the actual ticket content — SQL aggregation on unread data produces shallow insights

## Generating Charts

**Always prefer the `jiralyzer chart` CLI** for visualizations. It produces professional styled PNG charts automatically.

```bash
jiralyzer --db "$JIRALYZER_DB_PATH" chart "<sql>" --type bar --x <col> --y <col> --output "$JIRALYZER_CHART_DIR/chart.png"
```

If you need a custom visualization that the CLI can't produce:
1. **Write the Python script to a file first**, then run it. Do NOT write large inline Python in Bash calls — it times out.
   ```bash
   cat > /tmp/chart_script.py << 'PYEOF'
   import matplotlib.pyplot as plt
   # ... your code ...
   PYEOF
   cd "$JIRALYZER_PROJECT_DIR" && .venv/bin/python3 /tmp/chart_script.py
   ```
2. Keep scripts short — one chart per script, not six.
3. Use the jiralyzer `.venv` Python so matplotlib is available.

## Common Question Patterns

| User asks about... | Tables to query | Typical chart |
|---|---|---|
| Resolution time | tickets (resolution_days) | histogram, bar |
| Status distribution | tickets (status) | pie, bar |
| Workload / assignees | tickets (assignee) | bar |
| Ticket trends | tickets (created, resolved) | line |
| Re-assignments | assignments | bar |
| Status transitions | status_changes | heatmap, stacked_bar |
| Cycle time | status_changes (time between states) | histogram, line |
| Activity / comments | comments | line, bar |
| Time tracking | worklogs | bar, scatter |
| Custom fields | custom_fields | bar |

## Quick Stats

For a quick overview, run:

```bash
jiralyzer --db "$JIRALYZER_DB_PATH" stats              # Text summary
jiralyzer --db "$JIRALYZER_DB_PATH" stats --format json  # Machine-readable
```

This shows: table row counts, date ranges, status distribution, top assignees, resolution metrics.

## Export

For downstream analysis (Snowflake, BigQuery, etc.):

```bash
jiralyzer --db "$JIRALYZER_DB_PATH" export-parquet ./exports/                    # All tables
jiralyzer --db "$JIRALYZER_DB_PATH" export-parquet ./exports/ --tables tickets    # Specific tables
jiralyzer --db "$JIRALYZER_DB_PATH" export-parquet ./exports/ --compression zstd  # Better compression
```

## Rules

- **Source `.env` before every command.** Every bash invocation must start with: `set -a && source "$JIRALYZER_PROJECT_DIR/.env" && set +a && cd "$JIRALYZER_PROJECT_DIR" && uv run jiralyzer --db "$JIRALYZER_DB_PATH" <command>`
- Never access the database directly — always use the CLI
- **If `.env` is missing or sync fails, stop and ask the user.** Do not attempt workarounds.
- **Always identify the target project first.** Check which projects are loaded, sync if needed, and filter all queries with `WHERE project = '<KEY>'` when multiple projects exist
- When generating SQL, prefer CTEs over subqueries for readability
- Always LIMIT results for exploratory queries (LIMIT 20 default)
- If a query fails, check the schema and adjust — column names are exact
