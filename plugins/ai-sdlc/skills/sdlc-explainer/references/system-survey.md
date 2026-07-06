# System Survey — extracting the current AI-SDLC shape from source

Run this before explaining anything. It produces a structured digest of the system *as it exists right now*, so your explanation and diagrams reflect the current source, not a memory of it.

**Why a survey instead of a fact sheet:** the number of phases, the agent roster, the state names, the verdicts, and the caps all change as the system is developed. A frozen list would be wrong the next time someone edits the pipeline. So we read the source every time and report what is actually there.

## Where the source of truth lives

All paths are relative to the `ai-sdlc` plugin root (`plugins/ai-sdlc/`). Locate the plugin first if you don't know where it is:

```bash
# Find the ai-sdlc plugin (it may live in a -dev or prod marketplace copy)
find ~ -path '*ai-sdlc/commands/sdlc.md' 2>/dev/null
```

| Concern | File(s) |
|---|---|
| Orchestrator: principles, phases, gates, spawn protocol, self-learning loop | `commands/sdlc.md` |
| Agent roster + each role's inputs/outputs/decisions | `agents/*.md` (one file per role) |
| Jira conventions, artifact discipline, worktrees, branching | `skills/sdlc-conventions/SKILL.md` |
| Workflow states, bug lifecycle, retry cap | `skills/sdlc-conventions/references/workflow-states.md` |
| Context-passing protocol between agents | `skills/sdlc-conventions/references/context-protocol.md` |
| Design rationale (the "why" behind subsystems) | `docs/specs/*.md`, `docs/plans/*.md` |

**Rule:** if any two sources disagree, the orchestrator (`commands/sdlc.md`) and the agent files are authoritative for *behavior*; the conventions skill is authoritative for *shared conventions*. Docs explain *why* but may lag behind. Flag any disagreement in your explanation.

## What to extract

Build a digest with these sections. Keep it compact — you're extracting structure, not copying prose.

### 1. Core principles (the idea)
- Read the orchestrator's principles section and the conventions overview.
- Capture each operating principle in one line, in the source's own words.
- Note especially any rule about **what the orchestrator must NOT do** — these are the counter-intuitive load-bearing constraints.

**How:** read the top of `commands/sdlc.md` (principles) and the overview of `skills/sdlc-conventions/SKILL.md`.

### 2. The pipeline (the flow)
- List every phase **in order, as named in the source** — including any sub-phases (fractional numbers) and optional phases.
- For each phase capture: its name/number, which agent (if any) runs it, its one-line purpose, and whether it is **skippable/optional** or **always runs**.
- Mark which phases are **human-gated** (the pipeline pauses for approval).

**How:** scan `commands/sdlc.md` for the phase headers (they are section headings). Do not assume the count or the numbering — read them off. Cross-check against the phase list in `skills/sdlc-conventions/SKILL.md`.

```bash
# List the phase headings in orchestrator order (adjust path)
grep -nE '^##+ Phase' plugins/ai-sdlc/commands/sdlc.md
```

### 3. The agent roster
- List every agent file present. Do not rely on any remembered count — enumerate the directory.
- For each agent capture a compact row: **role (one line) · model tier · reads · writes (artifact header + status transitions) · key decision/verdict**.
- Note which agents touch Jira and which don't.

**How:**
```bash
ls plugins/ai-sdlc/agents/*.md          # the current roster — count from this, never from memory
grep -nE '^(name|description|model):' plugins/ai-sdlc/agents/*.md   # frontmatter
```
Then read each agent file's role definition and its "artifact" / transitions / verdict sections. The model tier may live in the agent frontmatter and/or in a table in `commands/sdlc.md` — reconcile the two.

### 4. Jira coordination model
- The ticket hierarchy (the tiers, top to bottom, plus how defects are represented).
- The story status set and their order.
- The "one artifact per phase" contract (what an agent is allowed to read and write).

**How:** `skills/sdlc-conventions/references/workflow-states.md` for statuses + bug lifecycle; `skills/sdlc-conventions/SKILL.md` for hierarchy + artifact discipline.

```bash
grep -nE '^\| ' plugins/ai-sdlc/skills/sdlc-conventions/references/workflow-states.md   # status table
```

### 5. Decision points (the branches)
This is the richest part of the explanation — enumerate **every place the flow is not a straight line**:
- Verdict-based routing (an agent returns one of several verdicts that change what happens next). Capture the verdict names *as written* and what each triggers.
- Pass/fail gates (a phase either advances the work or sends it backward).
- Loops and their **caps** (how many times something retries before it stops for a human).
- Merge/conflict decisions (when work is combined).
- Any "stop and ask the user" branch.

**How:** search the orchestrator and agent files for routing language.
```bash
grep -niE 'verdict|loopback|escalat|pass|fail|approve|reject|halt|cap|max|retry|→|proceed to' \
  plugins/ai-sdlc/commands/sdlc.md plugins/ai-sdlc/agents/*.md
```
For each hit, read the surrounding lines and record: **trigger → decision → each outcome**. Note the exact verdict/label strings — a reader will grep for them.

### 6. Cross-cutting systems
Things that aren't a single phase but run alongside the pipeline:
- **Workspace isolation** — how concurrent work is kept from colliding.
- **Self-learning / lessons** — how the system captures and applies corrections (if present).
- **Resume / handoff / pause** — how a run is saved and continued.
- **Branching model** — how the system decides where code lands.

**How:** these have dedicated sections in `commands/sdlc.md` and `skills/sdlc-conventions/SKILL.md`. Read them; describe them as you find them (they change).

### 7. Entry points & modes
- How a user starts or resumes the pipeline (the `/sdlc` argument forms and any flags).
- Any special modes (feedback loop, hotfix, auto-approve, etc.).

**How:** the orchestrator's input/flags/mode sections in `commands/sdlc.md`.

## Output of the survey

Hold the digest as a compact structured note for the current task — roughly:

```
PRINCIPLES: [one line each, incl. any "orchestrator must not…" rules]
PHASES: [ordered list: name · agent · purpose · optional? · human-gate?]
AGENTS: [table: role · model · reads · writes · decides]
JIRA: [hierarchy] · [ordered statuses] · [artifact contract]
DECISIONS: [each: trigger → outcomes, with verbatim verdict/label names]
CROSS-CUTTING: [isolation] · [self-learning] · [resume] · [branching]
ENTRY: [start/resume forms + flags + modes]
```

Everything you explain or diagram is built from this digest. When the reader will rely on a fact, cite it as `file:line` so it survives the next change to the system.

## Freshness check

If a path or section named in this survey no longer exists (file renamed, section moved, phase removed), that's expected drift — the system changed. Adapt: find the current equivalent by searching, explain from what's actually there, and note the drift so this reference can be updated later.
