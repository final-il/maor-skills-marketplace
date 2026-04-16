---
name: dev-terminal
description: >
  This skill should be used when the user asks to "create a dev terminal", "set up a terminal for my project",
  "create dev and prod terminals", "set up iTerm profiles", "create a dedicated terminal", "configure terminal
  for my repo", "open terminal in project directory", "create a Claude terminal", or wants dedicated iTerm2
  terminal profiles that auto-launch Claude Code in specific project directories with distinct visual themes.
  Also trigger when the user mentions "dev terminal", "prod terminal", "project terminal", or wants to
  visually distinguish between development and production environments in their terminal setup.
version: 0.1.0
---

# Dev Terminal — Dedicated iTerm2 Profiles for Claude Code Projects

Create dedicated, visually distinct iTerm2 terminal profiles that automatically open Claude Code in the correct project directory. Each profile gets its own background color and badge so the user can instantly tell which environment they're working in.

## Prerequisites

- **iTerm2** must be installed. If not present, install via: `brew install --cask iterm2`
- **Locale fix**: If iTerm2 shows a locale warning on first launch, add to `~/.zshrc`:
  ```bash
  export LANG="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"
  ```

## How It Works

iTerm2 supports **Dynamic Profiles** — JSON files in `~/Library/Application Support/iTerm2/DynamicProfiles/` that are automatically loaded and live-reloaded. Each profile specifies a working directory, startup command, background color, and badge text.

## Workflow

### Gathering Requirements

Before creating profiles, collect the following for each terminal:

1. **Profile name** — use the naming convention `<product>-dev` or `<product>-prod` (e.g., "jiralyzer-dev", "jiralyzer-prod")
2. **Project directory** — absolute path to the project (e.g., `/Users/maorb/git/jiralyzer-dev`)
3. **Background color** — to visually distinguish environments. Suggested defaults:
   - Dev: dark blue `(0.0, 0.0, 0.2)`
   - Prod: black `(0.0, 0.0, 0.0)`
   - Staging: dark green `(0.0, 0.1, 0.0)`
   - Test: dark purple `(0.1, 0.0, 0.15)`
4. **Badge text** — short label shown on the terminal (e.g., "DEV", "PROD")
5. **Startup command** — what to run on open (default: `claude`)

If the user provides a product name and dev/prod paths, generate sensible defaults for colors, badges, and naming (`<product>-dev`, `<product>-prod`) without asking.

### Creating Profiles

Use the bundled script to create each profile:

```bash
bash scripts/create-iterm-profile.sh "<name>" "<directory>" "<R,G,B>" "<badge>" "<command>"
```

Parameters:
- `name`: Profile name shown in iTerm2's Profiles menu
- `directory`: Absolute path — the terminal opens here
- `R,G,B`: Background color as float values 0.0-1.0 (e.g., `0.0,0.0,0.2`)
- `badge`: Short text badge (optional, defaults to uppercase name)
- `command`: Startup command (optional, defaults to `claude`)

Example for a product called "myapp" with dev and prod:
```bash
bash scripts/create-iterm-profile.sh "myapp-dev" "/Users/user/git/myapp-dev" "0.0,0.0,0.2" "DEV" "claude"
bash scripts/create-iterm-profile.sh "myapp-prod" "/Users/user/git/myapp" "0.0,0.0,0.0" "PROD" "claude"
```

### Managing Profiles

**List all Claude-managed profiles:**
```bash
bash scripts/list-iterm-profiles.sh
```

**Remove a profile:**
```bash
bash scripts/remove-iterm-profile.sh "<profile-name>"
```

### Per-Project Plugin Configuration

Each project directory can have its own `.claude/settings.json` to control which Claude plugins are active. This means the dev terminal and prod terminal can load different plugins automatically.

To configure project-specific plugins, create or edit `.claude/settings.json` in the project root:

```json
{
  "enabledPlugins": {
    "plugin-dev@marketplace": true,
    "skill-creator@marketplace": true
  }
}
```

Project settings merge with user-level settings (`~/.claude/settings.json`). To disable a globally-enabled plugin for a specific project, set it to `false`:

```json
{
  "enabledPlugins": {
    "plugin-dev@marketplace": false
  }
}
```

### Post-Setup Instructions

After creating profiles, inform the user:

1. **Open profiles**: iTerm2 > Profiles menu > select the profile name
2. **Keyboard shortcut**: Assign a hotkey via iTerm2 > Settings > Profiles > select profile > Keys > Hotkey Window
3. **Profile picker**: Press `Cmd+O` in iTerm2 to see all profiles
4. **Changes are live**: Editing the JSON files takes effect immediately — no restart needed

## Suggested Color Schemes

| Environment | RGB (floats)      | Description   |
|-------------|-------------------|---------------|
| Dev         | `0.0, 0.0, 0.2`  | Dark blue     |
| Prod        | `0.0, 0.0, 0.0`  | Pure black    |
| Staging     | `0.0, 0.1, 0.0`  | Dark green    |
| Test        | `0.1, 0.0, 0.15` | Dark purple   |
| Local       | `0.05, 0.05, 0.05` | Dark gray   |

## Bundled Scripts

- **`scripts/create-iterm-profile.sh`** — Create a new iTerm2 Dynamic Profile
- **`scripts/list-iterm-profiles.sh`** — List all Claude-managed profiles
- **`scripts/remove-iterm-profile.sh`** — Remove a profile by name
