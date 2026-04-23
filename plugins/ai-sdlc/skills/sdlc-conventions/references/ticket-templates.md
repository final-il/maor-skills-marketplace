# AI-SDLC Ticket Templates

## QBV Template (Project Container)

```markdown
# {Project Name} — {Short Description}

## Overview
{1-2 paragraph description of the product/project}

## Tech Stack
{Languages, frameworks, key libraries}

## Repo
{GitHub repo URL or path}

## Epics
- [ ] {Epic 1 title}
- [ ] {Epic 2 title}
- [ ] ...
```

## Epic Template

**Naming convention:** Epic summaries MUST be prefixed with the project name and an em dash: `"{Project Name} — {Epic Title}"`. Example: `"Jiralyzer — Data Processing Pipeline"`.

```markdown
# {Project Name} — {Epic Title}

## Overview
{1-2 paragraph description of the functional area}

## Goals
- {Goal 1}
- {Goal 2}

## Stories
- [ ] {Story 1 title} — {brief description}
- [ ] {Story 2 title} — {brief description}
- [ ] ...

## Dependencies
{Any cross-epic dependencies}

## Definition of Done
- All stories completed and in "Done" status
- All tests passing
- Code reviewed and merged
```

## Story Template

```markdown
# {Story Title}

## Description
{What needs to be built and why}

## Acceptance Criteria
- [ ] Given {precondition}, when {action}, then {expected result}
- [ ] Given {precondition}, when {action}, then {expected result}
- [ ] ...

## Technical Notes
{Filled in by the Architect agent — file paths, function signatures, data structures, algorithms}

## Dependencies
- Blocked by: {STORY-KEY} (if any)
- Blocks: {STORY-KEY} (if any)

## Complexity
{S / M / L}
```

## Bug Template

```markdown
# Bug: {Short description}

## Parent Story
{STORY-KEY}: {Story title}

## Description
{What went wrong}

## Steps to Reproduce
1. {Step 1}
2. {Step 2}

## Expected Behavior
{What should happen}

## Actual Behavior
{What actually happens}

## Error Details
```
{Stack trace, error message, test output}
```

## Suggested Fix
{If the tester/QA has a suggestion}
```

## Comment Formats

### Architect Comment (Tech Spec)
```markdown
## Technical Specification

### Files to Create/Modify
- `src/module/file.py` — {what to do}
- `tests/test_file.py` — {what to test}

### Approach
{Description of the implementation approach}

### Data Structures
{Key data structures, function signatures}

### Edge Cases
- {Edge case 1}
- {Edge case 2}
```

### Developer Comment (Implementation Done)
```markdown
## Implementation Complete

**Branch:** `{STORY-KEY}/{slug}`
**PR:** {PR URL}

### Changes
- `src/file.py` — {what was changed}
- `src/other.py` — {what was changed}

### Notes
{Any deviations from tech spec, decisions made}
```

### Tester Comment (Test Results)
```markdown
## Test Results

**Status:** PASS / FAIL
**Tests added:** {count}
**Test file:** `tests/test_file.py`

### Test Summary
- ✅ {test_name} — {what it validates}
- ✅ {test_name} — {what it validates}
- ❌ {test_name} — {failure reason}

### Coverage
{Which acceptance criteria are covered}
```

### QA Comment (Review Results)
```markdown
## QA Review

**Status:** APPROVED / ISSUES FOUND

### Requirements Check
- ✅ {Acceptance criterion 1}
- ✅ {Acceptance criterion 2}
- ❌ {Acceptance criterion 3} — {what's wrong}

### Code Quality
{Observations about code quality, patterns, potential issues}

### Issues
{List of issues found, if any — each becomes a Bug sub-task}
```
