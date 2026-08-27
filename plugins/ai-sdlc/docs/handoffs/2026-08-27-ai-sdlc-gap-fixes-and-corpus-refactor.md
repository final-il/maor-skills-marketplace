## Session Handoff — 2026-08-27

### Project: ai-sdlc plugin (maor-skills-marketplace)
### Branch: dev (even with origin/dev; **all work below uncommitted**)
### Repo: /Users/maorb/git-dev/maor-skills-marketplace

### Original goal
Started as an sdlc-explainer Q&A (why tester+QA, why bug-fixer, is it TDD). Expanded into: (1) a full gap audit of the ai-sdlc system, then (2) a refactor to shrink the grown instruction corpus **without losing quality/determinism**.

### Completed
- **Explainer answers** given (tester=evidence producer, QA=distrustful verifier w/ opus, bug-fixer=surgical minimal-change specialist; dev is TDD, tester is coverage-expansion not TDD).
- **Gap audit** — 5 parallel review agents + self re-verification + **2 Codex peer reviews** → **13 verified gaps, all fixed** across: `entrypoint-modes.md` (feedback-loop skip guard), `commands/sdlc.md` (fast ready-promotion, fast `--docs` path, Phase 8 promotion `git -C`, reconcile-decline keep-file, dev-blocked ledger row, loop-cap resume enforcement, can't-reproduce escalation), `workflow-states.md` (bug-parenting exception), `SKILL.md` (§2.5 scope, spawn model pointer-not-body), `sdlc-architect.md` (canonical "Selected for Development" transition key), `sdlc-tester.md` + `sdlc-qa-reviewer.md` (E2E marker), `sdlc-conflict-resolver.md` (Fast Mode section), `sdlc-handoff/SKILL.md` (fast-wave awareness + Mode/Self-Learning/Codex/Docs blocks + delete rule).
- **Corpus refactor (Codex-reviewed mechanism = build-time composition, NOT runtime injection):**
  - Option 1+2: `build/sdlc-compose.mjs` (`check`/`write`) + `build/fragments/lessons.md` — single source for the 13 byte-identical `## Lessons` blocks; `write` is a verified no-op → determinism-neutral. Drift-check is green.
  - Option 3 (real token win): `references/recipes-wire-and-config.md` — tester/QA wire+smoke+Gate-4 *procedures* moved on-demand; MANDATES/triggers/verdicts stay inline. tester 7039→4994 tok (−29%), QA 5203→4520 (−13%) on non-qualifying spawns.
  - Tier B (conservative): `references/phase-playbooks.md#phase-7-5` — only Phase 7.5 *mechanics* moved; all decisions/gates/drift-cap resident. Orchestrator 23274→22810. **Phase 4-7 + fast-path deliberately left resident** (gate-dense, Codex DO-NOT-TOUCH).
  - Tier C: 2 inert smoke logs → `docs/archive/` (no refs broken).

### Decisions Made
- **Build-time composition, not runtime injection** — Codex rejected injection (competes with the role-file-first authority; fragile precedence). Generated files stay self-contained → runtime path unchanged.
- **Dedup saves ~0 runtime tokens** (per-spawn cost irreducible under pointer-not-body); its value is killing the drift bug-class (root cause of ~9 of the 13 gaps). Only Option 3 + resident trims move real tokens.
- **Did NOT gut orchestrator Phase 4-7** — determinism > the resident-token trim; matches Codex's DO-NOT-TOUCH list.

### In Progress / Next Steps
1. **Optional: final Codex review** of the whole uncommitted diff (confirm no gate weakened, no pointer orphaned).
2. **Bump `plugin.json` 0.1.0 → 0.2.0** (material behavior + structure change; the orchestrator's own rule at `sdlc.md:200`).
3. **Commit on `dev`** with a summary message, then push. Suggested: `ai-sdlc: fix 13 consistency gaps + build-time composition/on-demand recipes to slim corpus`.
4. Consider wiring `node build/sdlc-compose.mjs check` into a pre-commit hook / `hooks/tests`.

### Blockers / Watch Out
- **Nothing committed** — 10 modified files, 3 new (`build/`, 2 refs), 2 renames staged.
- The 5 new on-demand pointers must keep resolving; run `node plugins/ai-sdlc/build/sdlc-compose.mjs check` before commit (currently green).
- Deliberately-left-open (not in the 13): "Bug sub-task" wording drift; Phase 8 CUJ-replay running in-orchestrator (in-source acknowledged); plugin.json version bump (item 2 above).

### Resume Command
`cd /Users/maorb/git-dev/maor-skills-marketplace && git -C . diff --stat -- plugins/ai-sdlc` then proceed with Next Steps 1–3.
