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

**Every artifact comment** opens with `## Summary` (3-5 bullets), then `## Detail`. See `SKILL.md` "Artifact Discipline" for the rationale.

### Architect Comment (Tech Spec)
```markdown
## Technical Specification

### Summary
- Approach: {one-line description}
- New/modified files: {count} (e.g., 2 src + 1 test)
- Key dependencies: {libs, modules}
- Risk / open question: {one bullet, or "none"}

### Detail

#### Files to Create/Modify
- `src/module/file.py` — {what to do}
- `tests/test_file.py` — {what to test}

#### Approach
{Implementation approach. Reference existing patterns by file path; do not paste code.}

#### Data Structures
{Key signatures only — `def parse(stream: IO[bytes]) -> list[Record]`. No bodies.}

#### Edge Cases
- {Edge case 1}
- {Edge case 2}
```

### Developer Comment (Implementation Done)
```markdown
## Implementation Complete

### Summary
- Branch: `{STORY-KEY}/{slug}`
- PR: {URL}
- Commits: {count}, last: {sha}
- Deviations from tech spec: {one line, or "none"}

### Detail

#### Changes
- `src/file.py` — {what was changed} (commit {sha})
- `src/other.py` — {what was changed} (commit {sha})

#### Notes
{Decisions made; do NOT paste code — link to commit + path}
```

### Tester Comment (Test Results)
```markdown
## Test Results

### Summary
- Status: PASS / FAIL
- Tests added: {count} ({passed} passed, {failed} failed)
- AC coverage: {N of M} acceptance criteria covered
- First failure (if any): `{test_name}` — {one-line cause}

### Detail

#### Test File
`tests/test_file.py` (commit {sha})

#### Failures
- ❌ `test_parse_malformed_xml` — expected `ValueError`, got `None` at line 42
  (re-run: `pytest tests/test_file.py::test_parse_malformed_xml -x`)

#### AC Coverage Map
- AC1 → `test_basic_parse`
- AC2 → `test_streaming_large_file`
- AC3 → not covered (out of scope this story)

(Do NOT paste full pytest output — name failures and let the bug-fixer re-run.)
```

### QA Comment (Review Results)
```markdown
## QA Review

### Summary
- Status: APPROVED / ISSUES FOUND
- Acceptance criteria: {N of M} pass
- Code quality: {one-line verdict}
- Bugs filed: {count} (keys: {BUG-1, BUG-2})

### Detail

#### Requirements Check
- ✅ AC1 — verified by `test_basic_parse`
- ✅ AC2 — verified by `test_streaming_large_file`
- ❌ AC3 — {what's wrong, with file:line reference}

#### Code Quality
{Observations referencing file:line, not pasted code}

#### Issues → Bug Sub-tasks
- {BUG-KEY}: {one-line description}
- {BUG-KEY}: {one-line description}
```

### Bug Fixer Comment (Fix Done)
```markdown
## Bug Fix Complete

### Summary
- Bug: {BUG-KEY}
- Root cause: {one line}
- Fix: {one line}
- Commits: {count}, last: {sha}

### Detail

#### Changes
- `src/file.py:42-78` — {what changed} (commit {sha})

#### Verification
{How you verified the fix — name the test, not the output}
```
