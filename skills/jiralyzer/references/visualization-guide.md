# Jiralyzer Visualization Guide

## Chart Type Selection

| Data Shape | Chart Type | When to Use | Example |
|---|---|---|---|
| Categories -> counts | `bar` | Comparing discrete categories | Tickets by status, priority |
| Time series -> values | `line` | Trends over time | Created vs resolved per week |
| Parts of whole | `pie` | Distribution (< 8 categories) | Ticket type distribution |
| Distribution | `histogram` | Spread of continuous values | Resolution time distribution |
| Two continuous vars | `scatter` | Correlation analysis | Story points vs resolution time |
| Category x category -> value | `heatmap` | Cross-tabulation | Status transition matrix |
| Categories -> stacked groups | `stacked_bar` | Grouped comparison | Tickets by priority per month |

## Output Formats

- `.html` — Interactive Plotly chart (hover, zoom, pan). Best for exploration.
- `.png` — Static Matplotlib image. Best for embedding in docs/reports.

## Command Syntax

```bash
jiralyzer chart "<SQL>" --type <chart_type> --x <x_col> --y <y_col> [options]
```

Options:
- `--type` (required): bar, line, pie, histogram, scatter, heatmap, stacked_bar
- `--x` (required): Column name for x-axis / labels
- `--y` (required): Column name for y-axis / values
- `--group-by`: Column for grouping (stacked_bar)
- `--title`: Custom chart title
- `--output`: Output file path (default: chart.html)
- `--open`: Open chart in browser after creation

## Examples by Chart Type

### Bar — Tickets by Status
```bash
jiralyzer chart \
  "SELECT status, COUNT(*) AS count FROM tickets GROUP BY status ORDER BY count DESC" \
  --type bar --x status --y count --title "Tickets by Status" --output status.html --open
```

### Line — Created vs Resolved Trend
```bash
jiralyzer chart \
  "SELECT DATE_TRUNC('week', created)::DATE AS week, COUNT(*) AS created FROM tickets GROUP BY 1 ORDER BY 1" \
  --type line --x week --y created --title "Tickets Created per Week" --output trend.html --open
```

### Pie — Issue Type Distribution
```bash
jiralyzer chart \
  "SELECT issue_type, COUNT(*) AS count FROM tickets GROUP BY issue_type ORDER BY count DESC" \
  --type pie --x issue_type --y count --title "Issue Type Distribution" --output types.html --open
```

### Histogram — Resolution Time Distribution
```bash
jiralyzer chart \
  "SELECT key, resolution_days FROM tickets WHERE resolution_days IS NOT NULL" \
  --type histogram --x key --y resolution_days --title "Resolution Time Distribution" --output resolution.html --open
```

### Scatter — Story Points vs Resolution Time
```bash
jiralyzer chart \
  "SELECT story_points, resolution_days FROM tickets WHERE story_points IS NOT NULL AND resolution_days IS NOT NULL" \
  --type scatter --x story_points --y resolution_days --title "Story Points vs Resolution" --output sp_vs_res.html --open
```

### Heatmap — Status Transition Matrix
```bash
jiralyzer chart \
  "SELECT from_status, to_status, COUNT(*) AS count FROM status_changes GROUP BY 1, 2" \
  --type heatmap --x from_status --y to_status --title "Status Transitions" --output transitions.html --open
```

### Stacked Bar — Priority by Month
```bash
jiralyzer chart \
  "SELECT DATE_TRUNC('month', created)::DATE AS month, priority, COUNT(*) AS count FROM tickets GROUP BY 1, 2 ORDER BY 1" \
  --type stacked_bar --x month --y count --group-by priority --title "Priority by Month" --output priority_trend.html --open
```

## Best Practices

1. **Limit categories** — Bar/pie charts work best with < 15 categories. Use `LIMIT` or `HAVING COUNT(*) > N`.
2. **Sort meaningfully** — Sort bar charts by value (`ORDER BY count DESC`), time series by date.
3. **Use .html for exploration** — Interactive Plotly charts let users hover for details, zoom, and pan.
4. **Use .png for reports** — Static images embed cleanly in documents.
5. **Title your charts** — Always use `--title` for context. Default titles are generic.
6. **Pick the right granularity** — Use `DATE_TRUNC('week', ...)` for trends, `'month'` for long timeframes.
