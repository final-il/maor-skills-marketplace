# Jiralyzer Plugin — TODO

## Bugs
- [x] SKILL.md had wrong working directory path (`git/jiralyzer-dev` → `git-dev/jiralyzer`)
- [x] `--db` flag was after subcommand (global option must come before subcommand)
- [x] First-time setup didn't install `uv` or run `uv sync`
- [x] First-time setup didn't ask user for env var values and create `.env`

## Improvements
- [x] Added `.env.example` with all required env vars
- [x] Added `.env` to `.gitignore`
- [x] SKILL.md now uses env vars instead of hardcoded paths
- [x] SKILL.md now has "First-Time Setup" section with prerequisite checks

## Ideas
