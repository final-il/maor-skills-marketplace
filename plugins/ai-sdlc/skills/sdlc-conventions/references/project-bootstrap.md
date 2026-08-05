# AI-SDLC New-Project Bootstrap (loaded on demand)

Loaded by Phase 0 when starting a brand-new product (no git repo). Covers GitHub repo creation, dev/prod clone layout, git identity, `.claude/settings.json`, initial CLAUDE.md, org confirmation, and protected-`main`/Cycode handling.

      **If NEW product (no git repo, or user confirms new project):**
   - Ask the user for the product name (e.g., "jiralyzer")
   - Ask: "Should I set up the full dev/prod structure?" (recommend yes)
   - If yes, create the dev/prod structure:
     ```bash
     # Create the repo on GitHub
     gh repo create final-il/{product-name} --private

     # Clone as dev directory
     cd ~/git
     git clone https://github.com/final-il/{product-name}.git {product-name}-dev
     cd {product-name}-dev

     # Configure git identity
     git config user.email "maorb@final.co.il"
     git config user.name "Maor B"

     # Create dev branch
     git checkout -b dev
     git push origin dev

     # Clone prod directory (stays on main)
     cd ~/git
     git clone https://github.com/final-il/{product-name}.git {product-name}
     cd {product-name}
     git config user.email "maorb@final.co.il"
     git config user.name "Maor B"
     ```
   - Create project-level settings for dev directory:
     ```bash
     mkdir -p ~/git/{product-name}-dev/.claude
     ```
     Write `~/git/{product-name}-dev/.claude/settings.json`:
     ```json
     {
       "enabledPlugins": {
         "ai-sdlc@maor-skills-marketplace": false,
         "ai-sdlc@maor-skills-marketplace-dev": true
       },
       "extraKnownMarketplaces": {
         "maor-skills-marketplace-dev": {
           "source": {
             "source": "git",
             "url": "https://github.com/final-il/maor-skills-marketplace.git",
             "ref": "dev"
           },
           "autoUpdate": true
         }
       }
     }
     ```
   - Create initial CLAUDE.md with project name, tech stack (ask user), and git conventions
   - Commit initial structure to `dev` branch, push
   - Set working directory to `~/git/{product-name}-dev/`

   **Org conventions — confirm the GitHub org before creating.** The org is not always `final-il`. Ask/confirm which org owns the repo (e.g. `final-israel`, `final-csi`, `final-develop`). Verify it exists with `gh api user/orgs --jq '.[].login'` before `gh repo create` — a wrong org fails with a 404.

   **Protected `main` (Cycode + required PR approvals).** In `final-israel` (and any org with branch protection), `main` rejects direct pushes — it requires the `Cycode: Secrets` status check and PR approvals. Consequences for the pipeline:
   - The initial commit and ALL work go to `dev`; `main` is created/updated ONLY via an approved PR. Never `git push origin main` directly — it fails with `GH013: Repository rule violations`.
   - When `autoInit` leaves the repo empty at branch time, seed the first commit locally on `dev` and push `dev` (not `main`).
   - Phase 8 promotion (dev → main) is a PR that must pass Cycode + get approval — it is NOT a fast-forward merge/push. Surface the PR link to the user rather than attempting to merge.
