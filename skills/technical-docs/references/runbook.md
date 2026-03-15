# Runbook / Playbook Template

```yaml
---
doc_type: runbook
title: "[Procedure Name] Runbook"
author: ""
date: YYYY-MM-DD
version: "1.0"
status: draft
audience: devops
tags: []
---
```

## Structure

```markdown
# [Procedure Name] Runbook

## Overview
One paragraph: what this runbook covers and when to use it.

## Prerequisites
- Required access / permissions
- Required tools installed
- Required knowledge / training
- Environment details (account IDs, regions, endpoints)

## Procedure

### Step 1: [Action]
**What**: Description of what to do
**Why**: Why this step matters
**Command/Action**:
\```bash
# command here
\```
**Expected output**: What you should see
**If it fails**: What to do if this step doesn't work

### Step 2: [Action]
...

## Verification
How to confirm the procedure completed successfully.
- Check 1: ...
- Check 2: ...
- Check 3: ...

## Rollback
If something goes wrong, how to undo the changes:
1. ...
2. ...

## Escalation
| Condition | Who to Contact | How |
|-----------|---------------|-----|
| Step N fails after retry | [Team/Person] | [Slack/Page/Email] |
| Data loss suspected | [Team/Person] | [Slack/Page/Email] |

## Appendix
- Related runbooks
- Change history
- Known issues
```
