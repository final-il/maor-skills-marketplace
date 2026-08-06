# AI-SDLC Delivery Lifecycle — Design

**Status:** Approved (2026-08-06). All open questions resolved (see "Resolved decisions" below). Ready for implementation per the sketch at the end.
**Author:** Maor + Claude
**Related:** `2026-07-08-ai-sdlc-hybrid-artifact-store-design.md` (the `docs/sdlc/` git store this builds on), `2026-07-08-ai-sdlc-documentation-phase-design.md` (Phase 7.7, extended here), `2026-07-19-ai-sdlc-fast-mode-design.md` (ledger/wave model this must coexist with). Also see this session's config/infra edits (Gate 4, `## Config & Infra Contract`, target-mode gates) — the Delivery Model is the environment those gates run *in*.
**Reference implementation:** `~/git-dev/jiralyzer` — `docs/cicd.md`, `deploy/*.sh`, `Jenkinsfile`, `docker-compose*.yml`. Used throughout as **one worked example of a stack-agnostic contract**, never as the prescribed stack.

---

## Problem

ai-sdlc knows how to go **idea → merged code on `dev`**. It does **not** know a project's **delivery contract** — how code on `dev` becomes a running, tested thing on a staging server, then production, and how every documentation surface (git, Confluence, **and in-app content**) stays in sync with what shipped.

Everything past "PR merged to `dev`" is currently either absent or improvised:

1. **No environments beyond local.** The tester runs live-process + config/infra gates *in the worktree* (local Mac). There is no concept of a **remote staging server** — nothing copies the build there, nothing tests *against it*. Auth/proxy bugs that only appear behind the real front door (the exact motivation for this session's Gate 4) can be *asserted* against config, but never *observed* on the real deployed system.
2. **No CI/CD awareness.** The pipeline never triggers a build, never ships an image/artifact, never touches a server, and has no idea a Jenkins job or an Artifactory repo exists. For jiralyzer, all of that lives in `docs/cicd.md` + `deploy/*.sh` — **outside** ai-sdlc.
3. **The flow is re-discovered (or guessed) every run.** How to reach Jenkins, how to `scp` to the stg host, which env file, the nginx front door, the smoke assertions — none of this is a persisted, known fact of the project. Branch model is *auto-detected* each run (dev/prod vs single) rather than *decided* and recorded.
4. **Docs stop at README/Confluence.** Phase 7.7 covers repo docs + Confluence but not **in-app user-facing content** — the home-page feature list, how-tos, coming-soon announcements, in-app changelog — which for jiralyzer were updated by hand per feature. Nothing checks that git/Confluence/in-app agree.

### The jiralyzer flow this generalizes (confirmed from the repo)

```
LOCAL (Mac): dev in worktree → local tests → local uvicorn + Playwright E2E → iterate
   │  (user decides "run CI/CD now")
   ▼
JENKINS (build only): Lint & Test → Version (single source) → Build & Push → Xray Scan
   │   pushes linux/amd64 image to Artifactory
   │  (MANUAL: deploy/deploy.sh <env> on the host)
   ▼
STAGING (remote amd64 host, behind nginx, AUTH_MODE=users):
   pull image → compose up (nginx front door) → deploy/smoke.sh <base_url>
   test + fix on BOTH stg (real) AND local; Playwright E2E against remote or local
   │  (manual gate: smoke passes, UI validated)
   ▼
PRODUCTION (same deploy.sh, prod env)
```

`deploy/deploy.sh` is explicitly **portable** ("nothing is CSI030-specific… point it at a fresh host by writing the env file + placing the TLS cert"). `deploy/smoke.sh` encodes the real post-deploy assertions (liveness, readiness, SPA root, and the Grafana `public_url` == browser base-URL check that a bare 200 misses). `docs/cicd.md` already maps each local step 1:1 onto a future Jenkins/Artifactory/k8s owner. **This design lifts that pattern into ai-sdlc as a first-class, reusable, persisted artifact.**

---

## Core idea: the **Delivery Model** — a decided, persisted, replayed contract

A single per-project git artifact, `docs/sdlc/delivery-model.md`, that is the delivery equivalent of the **ownership registry** (§2.5a): **decided once** (with the user, informed by the architecture), **persisted in git**, and **read on every subsequent run** so the pipeline *knows* the flow instead of guessing it.

Guiding principles (consistent with this session's generality work):
- **Derived, not imposed.** The branch strategy and environment topology are *consequences* of the tech stack + runtime shape, which are only known **after** planning + architecture. A k8s microservice with GitOps, jiralyzer's "build image → ship → compose-up on one stg host", and a pure library that publishes to a package registry each want a different Delivery Model. The pipeline **proposes** a fitting model *after* it understands the project, and the user confirms/edits.
- **Stack-agnostic contract, project-specific values.** The Delivery Model defines *roles/stages* (build, ship, deploy, smoke, version, promote) as a contract; the concrete commands/URLs/hosts are project-specific values discovered once via Q&A and written to git. jiralyzer's buildx→Artifactory→compose→nginx is **one filled-in example**, not the template's spine.
- **Know, don't rediscover.** Once written, Phase 0 loads it into the context block. No agent re-asks "how do I reach the stg host?" — it's a field.
- **Outward/destructive ops still ask first.** Triggering a build or deploying to a remote host is an outward action. Default is *prepare + runbook + ask*; auto-deploy is an opt-in per-project field. (Respects the workspace CLAUDE.md rule.)

### `docs/sdlc/delivery-model.md` — shape

```markdown
# Delivery Model — {Project Name}

## Runtime shape
{server-deployed container | k8s workload | CLI/binary | static site | library/package | serverless} — one line why (from the architecture).

## Environments
| Env    | Purpose                    | Host / target                        | How to reach it            | Runtime mode |
|--------|----------------------------|--------------------------------------|----------------------------|--------------|
| local  | dev + fast iteration       | this Mac (worktree)                  | n/a                        | dev-open     |
| stg    | integration + UI/E2E gate  | {ssh alias / host}                   | {ssh alias, scp target}    | {AUTH_MODE=users, behind nginx} |
| prod   | production                 | {host / cluster}                     | {…}                        | {…}          |

## Branch strategy
- Model: {story→dev→main | FR→DEV→MAIN three-tier | release-train | trunk+tags | …}
- Branch→environment map: {feature branches = local; DEV = deploys to stg; MAIN = prod}
- PR target for stories: {dev}
- Promotion path + gate: {dev→main on explicit user request after stg validation}
- Why this model fits: {one line tying it to runtime shape + env needs}

## CI/CD
- Tooling: {Jenkins job URL + how to trigger | GitHub Actions workflow | none — local buildx}
- Artifact store: {Artifactory repo path | GHCR | none — local tarball}
- Trigger authority: {ask-then-run | auto-on-merge}
- Stages (contract): Lint & Test → Version → Build & Push → {Scan} → (Deploy owned below)

## Deploy mechanism (the build→ship→deploy→smoke contract)
- Build:   {`deploy/build.sh` — buildx linux/amd64 | `docker build` | `helm package` | …}
- Ship:    {push to Artifactory | `docker save|gzip` + scp | `helm push` | publish to registry}
- Deploy:  {`deploy/deploy.sh <env>` on host | `kubectl apply`/`helm upgrade` | …}
- Smoke:   {`deploy/smoke.sh <base_url>` — the real post-deploy assertions}
- Deploy authority: {prepare+runbook, human runs | auto-deploy stg, gate prod}

## Version / release
- Single version source: {`deploy/bump-version.sh` | release-please | tag-driven}
- Tag convention: {`v{X.Y.Z}` on main}
- Where version surfaces at runtime: {`GET /api/health` | `--version` | package metadata}

## Remote test / E2E
- Smoke against: {stg base URL}
- UI/E2E: {Playwright against remote base URL | against local dev server}, headed/headless
- Test-in-target-mode: {which gates must run in the stg runtime mode, per Config & Infra Contract}

## In-app content surfaces (doc-sync targets)
- {home page feature list: web/frontend/src/pages/Home.tsx}
- {how-tos / help: …}
- {coming-soon / announcements: …}
- {in-app changelog / version banner: …}

## Doc surfaces (must stay in sync)
- git: README.md, docs/<feature>.md, CHANGELOG
- Confluence: {space + parent}
- in-app: {the surfaces above}
```

---

## Phases — the two goals

### Goal 1 — decide + *know* the full lifecycle

#### Phase 3.7 — Delivery Model design (NEW; after architecture, before/with design gate)

Runs **once per project** (idempotent: skips with a log line if `delivery-model.md` already exists and is current). Placed after Phase 3 (architecture) because only then is the tech stack + runtime shape known — satisfying the "derived, not imposed" principle.

- **Agent:** a new `sdlc-delivery-architect` (opus). (Decided — see Resolved decisions.)
- **Input:** epic + all story tech specs + `ownership.md` + CLAUDE.md + repo probe (existing `deploy/`, `Dockerfile`, CI config, branches).
- **Behavior:**
  1. Infer the runtime shape from the architecture.
  2. **Discover** any existing delivery machinery (deploy scripts, Dockerfile, Jenkinsfile/CI, branch topology) and record it.
  3. **Propose** a fitting Delivery Model — branch strategy + environments + CI/CD + deploy contract — *derived* from the runtime shape.
  4. **Ask the user the project-specific questions once** (ssh alias for stg? Jenkins job URL / how to trigger? how many environments? deploy authority?). These become persisted fields, never re-asked.
  5. Write `docs/sdlc/delivery-model.md`; return a summary for user approval (approval-gated like every other design artifact; `--auto` auto-approves).
- **`--bootstrap` mode (greenfield):** when no delivery machinery exists (or the user passes `--bootstrap`), the agent also **scaffolds the delivery skeleton** from the stack-agnostic template — proposes `deploy/` scripts (build/deploy/smoke/version), a Dockerfile (or the runtime-appropriate equivalent), CI config, and branch-protection setup — filled for the detected stack, with jiralyzer as the reference for a server-deployed container. All scaffolding is a **proposal the user approves** before anything is written; it lands as its own story/PR, not a silent write.

#### Phase 0 — load the Delivery Model (CHANGED)

Today Phase 0 *auto-detects* dev/prod vs single-branch. Change: if `docs/sdlc/delivery-model.md` exists, **load it** and populate the context block from it (`Base Branch`, `PR Target`, `Promotion Path`, `Environments`, `Deploy Commands`, `CI/CD trigger`). The auto-detect becomes a *fallback* only when no Delivery Model exists yet (first run, before Phase 3.7). Every downstream agent thus knows the flow from step one.

New context-block fields (all optional; absent = pre-Delivery-Model project, behave as today):
```
Delivery Model: docs/sdlc/delivery-model.md   (or "none — pre-model")
Environments: local, stg, prod
Deploy Contract: build=deploy/build.sh ship=… deploy=deploy/deploy.sh smoke=deploy/smoke.sh
CI/CD: {trigger cmd/url | none}   Trigger Authority: ask-then-run
Deploy Authority: prepare-runbook
```

### Goal 2 — execute + verify delivery + doc sync

#### Phase 8 — extend Completion with a staging-deploy gate (CHANGED)

After `dev` is green and all PRs merged (today's Phase 8 state), follow the Delivery Model to reach staging and **verify on the real server**:

1. **Build** — if CI/CD exists: **ask** ("Ready to run the build+push for stg?") then trigger it per `Trigger Authority`. If local-only: run the build/ship steps.
2. **Deploy to stg** — per `Deploy Authority`:
   - `prepare-runbook` (default): generate a concrete, ordered deploy runbook (the exact `deploy/deploy.sh stg …` invocation + prereqs) and a smoke checklist, then **pause** for the user to run it and confirm. Resume on confirmation.
   - `auto-deploy-stg`: run the deploy commands against stg directly (ssh/scp/compose up), then continue.
3. **Remote smoke + CUJ replay against stg** — run `deploy/smoke.sh <stg base URL>` and replay the epic's CUJs **against the deployed stg system in its real runtime mode** (not local). This is where "test on the real server" becomes a pipeline gate, and where auth/proxy bugs finally become observable. Save artifacts under `tests/artifacts/epic-{KEY}/stg-*`.
4. **Prod promotion** — unchanged intent (explicit user request / `--auto`), but promotion now *means* "deploy to prod via the same Delivery Model deploy contract," reusing steps 1–3 against the prod env.

Fast-mode note: the staging gate is git/command-based, so it runs identically in a `Jira: off` wave (read CUJs from the wave dir, as Phase 8 already does).

#### Phase 7.7 — extend Documentation with in-app content + doc-sync (CHANGED)

`sdlc-documenter` gains two responsibilities beyond README/`docs/`/changelog/Confluence:

1. **In-app user-facing content.** Using the shipped features (from the epic's tech specs + merged diff) and the Delivery Model's `## In-app content surfaces` list, propose **surgical edits** to the home-page feature list, how-tos, coming-soon/announcements, and in-app changelog. Same discipline as README edits: verbatim-anchor `Edit`s, approval-gated, never a rewrite. These land as code edits on the docs commit/PR.
2. **Doc-sync check.** Cross-check that all three surfaces — git docs, Confluence, in-app — reflect the shipped feature set. Report drift (e.g. "README lists feature X; home page doesn't mention it; Confluence page is stale") as a checklist for the user to approve fixes. Prevents the hand-maintained in-app content from silently lagging.

---

## Deploy authority — the resolved default (from the real jiralyzer flow)

The user's actual pattern was: *"we dev on Mac, test, copy to stg, test+fix on both, I ask when to run CI/CD, we test UI with Playwright on remote or locally."* That maps to a **hybrid**, encoded as Delivery Model fields rather than a global toggle:

- **Build/CI:** pipeline *can* trigger, but **asks first** (`Trigger Authority: ask-then-run`) — matches "I ask when to run CI/CD."
- **Deploy to remote:** default **`prepare-runbook`** (pipeline prepares everything, human runs the actual `scp`/`ssh`/`deploy.sh`) — safe under the destructive-ops rule; upgradeable to `auto-deploy-stg` per project once trusted.
- **Post-deploy:** pipeline runs remote smoke + E2E automatically and reports.

---

## `sdlc-conventions` changes

- **New §2.7 — Delivery Model.** Define the artifact, its lifecycle (decided Phase 3.7, loaded Phase 0, executed Phase 8), and the context-block fields. Cross-link §2.5 (git store) and the Config & Infra Contract.
- **Rewrite `## Branching Model`.** Today it hardcodes two auto-detected models. New text: the branch strategy is a **field of the Delivery Model**, *derived* from runtime shape after architecture; the two current models become two *examples* alongside three-tier (FR/DEV/MAIN) and trunk-plus-tags. Auto-detect survives only as the pre-model fallback.
- **Extend `## Pipeline Phases`** with 3.7 and the Phase 8 staging gate.

---

## Non-goals

- **Not a CI system.** ai-sdlc triggers/records CI; it does not replace Jenkins/Actions.
- **Not silent remote execution.** No deploy to a remote host without the resolved Deploy Authority explicitly permitting it; default asks.
- **Not a forced staging step for every project.** A library that publishes to a registry has no "stg server" — its Delivery Model says so, and Phase 8's staging gate no-ops for that runtime shape.
- **Not baking jiralyzer's stack in.** Docker/compose/nginx/Jenkins/Artifactory appear only as one filled example of the contract.

---

## Resolved decisions (2026-08-06 review)

All six open questions are decided. This section is now decision-of-record; the implementation sketch below reflects them.

1. **New agent.** `sdlc-delivery-architect` (opus) — a dedicated agent, not a pass on `sdlc-architect`. Delivery reasoning (env topology, branch model, CI/CD, deploy contract, promotion) is distinct from per-story tech design and would overload the already-large architect file.
2. **Phase 3.7** — slots directly after 3.6 (integrator). All per-story architecture is settled by 3.6, so the Delivery Model derives from a complete picture. No reserved gap.
3. **Auto-detect the gap, propose, require approval** — no `--bootstrap` flag. When zero delivery machinery is detected (no `deploy/`, no Dockerfile-equivalent, no CI config), the agent proposes a scaffold and pauses for approval; nothing is written silently. A first run of a greenfield project therefore triggers the offer without the user needing to know a flag exists.
4. **Its own "delivery setup" story/PR** in the current epic — the scaffold flows through the normal dev→test→QA→merge gates like any other work, so it is reviewed and tested, never a side write. (No separate `/sdlc bootstrap` entry point.)
5. **Template home** — ship the stack-agnostic delivery skeleton as an on-demand reference at `skills/sdlc-conventions/references/recipes-delivery.md`, loaded by the delivery-architect, mirroring the existing `recipes-iac.md` pattern.
6. **Remote E2E mechanics** — capture the self-signed-TLS / ssh-tunnel handling (the same `-k`/tunnel logic `deploy/smoke.sh` already uses) as a recipe inside `recipes-delivery.md`.

### Design note surfaced in review: Phase 8 is a resumable checkpoint, not a single pass

A staging deploy is a long, human-in-the-loop, outward action that can pause for hours (default authority = `prepare-runbook` → human runs it → confirm). Phase 8 must therefore be a **resumable checkpoint**: it writes its progress (built? deployed to stg? smoke passed?) to the resume file / Fast Work Ledger so `/sdlc continue {KEY}` (or `continue {WAVE-ID}` in fast mode) re-enters at the right sub-step rather than re-running the build. Each Phase 8 sub-step (build → deploy stg → remote smoke+CUJ replay → prod) is an independently resumable state.

---

## Implementation sketch (once approved)

Anchored `.md` edits, in dependency order:
1. `skills/sdlc-conventions/references/recipes-delivery.md` — NEW: stack-agnostic delivery skeleton (the `delivery-model.md` shape) + jiralyzer worked example + remote-E2E recipe (self-signed TLS / ssh tunnel). Built first so the agent + conventions can point at it.
2. `agents/sdlc-delivery-architect.md` — NEW agent (opus). Inputs, discover-existing-machinery behavior, propose-and-approve Delivery Model, auto-detect-gap → offer scaffold as a "delivery setup" story, load `recipes-delivery.md` on demand.
3. `sdlc-conventions/SKILL.md` — add §2.7 (Delivery Model: artifact, lifecycle 3.7→0→8, context-block fields), rewrite `## Branching Model` (strategy is a derived Delivery-Model field; current two models become examples alongside three-tier + trunk-plus-tags; auto-detect survives as pre-model fallback), extend `## Pipeline Phases` with 3.7 + Phase 8 staging gate.
4. `commands/sdlc.md` — Phase 0 (load Delivery Model, auto-detect as fallback + new context-block fields), Phase 3.7 (NEW), Phase 8 (staging-deploy gate + prod-via-contract, **as a resumable checkpoint** — each sub-step writes resume state), core-principle line ("Tested = … in the target environment" already added; add "Delivery is a decided contract, not rediscovered").
5. `agents/sdlc-documenter.md` + Phase 7.7 — in-app content targets + doc-sync check across git/Confluence/in-app.
6. `.claude-plugin` / marketplace.json + CLAUDE.md — register `sdlc-delivery-architect`; note the plugin-cache re-sync in done criteria; bump `plugin.json` version (pipeline behavior changes materially).
7. Dogfood: run `/sdlc` on a small change to confirm the new phases parse and the Delivery Model round-trips (including a `continue` mid-Phase-8 to prove the checkpoint resumes).
