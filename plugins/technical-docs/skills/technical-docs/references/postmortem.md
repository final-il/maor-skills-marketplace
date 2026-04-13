# Postmortem / Incident Report Template

```yaml
---
doc_type: postmortem
title: "Incident Report: [Brief Description]"
author: ""
date: YYYY-MM-DD
version: "1.0"
status: draft
audience: all
tags: []
---
```

## Structure

```markdown
# Incident Report: [Brief Description]

## Summary
| Field | Value |
|-------|-------|
| Severity | P1 / P2 / P3 / P4 |
| Duration | Start → End (total hours) |
| Impact | What users/systems were affected |
| Detection | How it was discovered (alert, customer report, manual) |
| Resolution | What fixed it |

## Timeline
All times in UTC.

| Time | Event |
|------|-------|
| HH:MM | First alert / symptom detected |
| HH:MM | Incident declared |
| HH:MM | Root cause identified |
| HH:MM | Fix deployed |
| HH:MM | Service restored |
| HH:MM | Incident resolved |

## Root Cause
What actually broke and why. Be specific — name the component, the failure
mode, and the trigger. Avoid blame; focus on systems and processes.

## Impact
- Number of users affected
- Revenue impact (if applicable)
- Data integrity impact
- SLA impact

## What Went Well
- Things that helped detect, respond to, or resolve the incident faster

## What Went Wrong
- Things that delayed detection, response, or resolution

## Action Items
| Priority | Action | Owner | Due Date | Status |
|----------|--------|-------|----------|--------|
| P1 | ... | ... | ... | Open |
| P2 | ... | ... | ... | Open |

## Lessons Learned
Key takeaways that should inform future architecture, process, or tooling decisions.

## References
- Links to dashboards, alerts, Slack threads, related incidents
```
