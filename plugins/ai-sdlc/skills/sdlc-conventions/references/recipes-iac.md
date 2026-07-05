# Recipes — IaC (Terraform / OpenTofu)

On-demand tooling gotchas for Infrastructure-as-Code stories. **Not always-loaded.** An agent reads this file only when the story it is implementing touches IaC (Terraform, OpenTofu, `.tf` files, state backends, provider config). Agents reach it via the one-line pointer in their role file:

> See `references/recipes-iac.md` for IaC tooling gotchas — load on demand.

## Recipe format

Each recipe is a `### <short title>` section with exactly three fields:

- **Trigger** — the condition under which this recipe applies (when to use it).
- **Recipe** — the actual command, flag, or gotcha to apply.
- **When-it-rots** — the condition under which this recipe becomes stale and should be re-verified or pruned. Recipes are closer to training data than operating instructions; they rot as the tool changes, so every recipe carries its own expiry signal.

Recipes are pruned by the periodic consolidation pass over `references/recipes-*.md` (see the self-learning design's "pruning pass, scoped"). Pruning a recipe never changes always-loaded behavior.

---

## Recipes

### Detect the IaC CLI before running any command

- **Trigger:** About to run any IaC command (`init`, `plan`, `apply`, `validate`) on a Terraform/OpenTofu story.
- **Recipe:** Detect the available CLI with `command -v terraform || command -v tofu` and use whichever exists. Never assume `terraform`. When both are present, prefer `tofu` only if the project's `README`/`CLAUDE.md` says so.
- **When-it-rots:** A third IaC CLI enters the fleet, or the project standardizes on one CLI and pins it in `CLAUDE.md` (then detection is unnecessary and this recipe can be dropped for that project).

### Never `rm -rf` ignored working dirs

- **Trigger:** Needing to clear a generated/ignored working directory such as `.terraform`, `node_modules`, or `.venv` during an IaC (or any) story.
- **Recipe:** Never `rm -rf` these — a safety hook blocks it. Relocate instead: `mv <dir> /tmp/<dir>-old-$$`.
- **When-it-rots:** The safety hook is removed or its blocked-path list changes; re-verify against the current hook config before relying on the `mv` workaround.
