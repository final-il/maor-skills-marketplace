# Recipes — Python

On-demand tooling gotchas for Python stories. **Not always-loaded.** An agent reads this file only when the story it is implementing touches Python tooling (pytest, packaging, imports, virtualenvs). Agents reach it via the one-line pointer in their role file:

> See `references/recipes-python.md` for Python tooling gotchas — load on demand.

## Recipe format

Each recipe is a `### <short title>` section with exactly three fields:

- **Trigger** — the condition under which this recipe applies (when to use it).
- **Recipe** — the actual command, flag, or gotcha to apply.
- **When-it-rots** — the condition under which this recipe becomes stale and should be re-verified or pruned. Recipes are closer to training data than operating instructions; they rot as the tool changes, so every recipe carries its own expiry signal.

Recipes are pruned by the periodic consolidation pass over `references/recipes-*.md` (see the self-learning design's "pruning pass, scoped"). Pruning a recipe never changes always-loaded behavior.

---

## Recipes

### pytest can't import the package under test (`ModuleNotFoundError`)

- **Trigger:** `pytest` fails to import the source package (e.g. `ModuleNotFoundError: No module named '<pkg>'`) even though the code is present, typically a `src/`-layout project.
- **Recipe:** Set the import root so pytest can find the package. In `pyproject.toml`:
  ```toml
  [tool.pytest.ini_options]
  pythonpath = ["src"]
  ```
  (Equivalent one-offs: run with `PYTHONPATH=src pytest`, or install the package editable with `pip install -e .` / `uv pip install -e .`.)
- **When-it-rots:** pytest changes the `pythonpath` ini option, or the project migrates off the `src/` layout / adopts an editable install as standard — then this recipe is unnecessary.
