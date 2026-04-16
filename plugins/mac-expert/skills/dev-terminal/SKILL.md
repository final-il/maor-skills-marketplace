---
name: dev-terminal
description: >
  This skill should be used when the user asks to "create a dev terminal", "set up a terminal for my project",
  "create dev and prod terminals", "set up iTerm profiles", "create a dedicated terminal", "configure terminal
  for my repo", "open terminal in project directory", "create a Claude terminal", or wants dedicated iTerm2
  terminal profiles that auto-launch Claude Code in specific project directories with distinct visual themes.
  Also trigger when the user mentions "dev terminal", "prod terminal", "project terminal", or wants to
  visually distinguish between development and production environments in their terminal setup.
version: 0.2.0
---

# Dev Terminal — Dedicated iTerm2 Profiles for Claude Code Projects

Create dedicated, visually distinct iTerm2 terminal profiles that automatically open Claude Code in the correct project directory. Each profile gets its own background color, foreground color, full ANSI color palette, and a visible badge so the user can instantly tell which environment they're working in.

## Prerequisites

- **iTerm2** must be installed. If not present, install via: `brew install --cask iterm2`
- **Locale fix**: If iTerm2 shows a locale warning on first launch, add to `~/.zshrc`:
  ```bash
  export LANG="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"
  ```

## How It Works

iTerm2 supports **Dynamic Profiles** — JSON files in `~/Library/Application Support/iTerm2/DynamicProfiles/` that are automatically loaded and live-reloaded. Each profile specifies a working directory, startup command, background color, foreground color, full ANSI color palette, and badge configuration.

## Workflow

### Gathering Requirements

Before creating profiles, collect the following for each terminal:

1. **Profile name** — use the naming convention `<product>-dev` or `<product>-prod` (e.g., "jiralyzer-dev", "jiralyzer-prod"). For general-purpose terminals use a descriptive name (e.g., "git-workspace").
2. **Project directory** — absolute path to the project (e.g., `/Users/maorb/git/jiralyzer-dev`)
3. **Theme / colors** — the user may reference a macOS Terminal.app theme by name (see Theme Reference below) or specify custom colors. Always set both background AND foreground colors.
4. **Badge text** — short label shown on the terminal (e.g., "DEV", "PROD", "WORKSPACE")
5. **Startup command** — what to run on open (default: `claude`)

If the user provides a product name and dev/prod paths, generate sensible defaults for colors, badges, and naming (`<product>-dev`, `<product>-prod`) without asking.

### Creating Profiles

Use the bundled script to create each profile:

```bash
bash scripts/create-iterm-profile.sh "<name>" "<directory>" "<BG R,G,B>" "<FG R,G,B>" "<badge>" "<command>"
```

Parameters:
- `name`: Profile name shown in iTerm2's Profiles menu
- `directory`: Absolute path — the terminal opens here
- `BG R,G,B`: Background color as float values 0.0-1.0 (e.g., `0.0,0.0,0.2`)
- `FG R,G,B`: Foreground color as float values 0.0-1.0 (e.g., `0.9,0.9,0.9`). Default: light gray
- `badge`: Short text badge (optional, defaults to uppercase name)
- `command`: Startup command (optional, defaults to `claude`)

The script automatically includes:
- Full 16-color ANSI palette (all light/bright for dark backgrounds)
- Bold, cursor, selection colors
- Badge with white color at 50% opacity, bold font, compact size (0.25 x 0.15)
- Cursor text color matching the background (for visibility)

Example for a product called "myapp" with dev and prod:
```bash
bash scripts/create-iterm-profile.sh "myapp-dev" "/Users/user/git/myapp-dev" "0.0,0.0,0.2" "0.9,0.9,1.0" "DEV" "claude"
bash scripts/create-iterm-profile.sh "myapp-prod" "/Users/user/git/myapp" "0.12,0.12,0.12" "0.8,0.8,0.8" "PROD" "claude"
```

### Important: Full Color Configuration

Every profile MUST include all of these color keys to prevent dark-on-dark text:
- **Foreground Color** — main text color (must be light on dark backgrounds)
- **Bold Color** — bold text (should be bright/white)
- **Cursor Color** — cursor block color
- **Cursor Text Color** — text inside cursor (should match background)
- **Selected Text Color** — text in selections (white)
- **Selection Color** — selection highlight background
- **Ansi 0-15 Colors** — full 16-color ANSI palette, all bright enough to read on the background
- **Badge Color** — with Alpha Component for visibility control

If the user reports text is invisible or hard to read, check that ALL color keys above are set. The create script handles this automatically.

### Customizing After Creation

The profile JSON files can be edited directly and changes take effect immediately (live-reload). To customize a specific theme further, edit the JSON at `~/Library/Application Support/iTerm2/DynamicProfiles/claude-claude-profile-<name>.json`.

Common customizations:
- **Badge size**: Adjust `Badge Max Width` (0.0-1.0) and `Badge Max Height` (0.0-1.0). Default is 0.25 x 0.15 (compact).
- **Badge visibility**: Adjust `Badge Color` > `Alpha Component` (0.0 invisible to 1.0 fully opaque). Default is 0.5.
- **Transparency**: Add `"Transparency": 0.15` for a slight see-through effect.

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

## Theme Reference (macOS Terminal.app Equivalents)

When the user references a Terminal.app theme by name, use these color mappings:

| Theme        | Background (R,G,B)    | Foreground (R,G,B)    | Notes                       |
|--------------|----------------------|----------------------|-----------------------------|
| Ocean        | `0.0, 0.1, 0.2`     | `0.8, 0.95, 1.0`    | Deep blue-green, cyan text  |
| Blue         | `0.0, 0.0, 0.67`    | `1.0, 1.0, 1.0`     | Medium blue, white text     |
| Clear Dark   | `0.12, 0.12, 0.12`  | `0.8, 0.8, 0.8`     | Dark charcoal, light gray. Add `"Transparency": 0.15` |
| Pro          | `0.0, 0.0, 0.0`     | `1.0, 1.0, 1.0`     | Pure black, white text      |
| Homebrew     | `0.0, 0.0, 0.0`     | `0.0, 1.0, 0.0`     | Black, green text           |
| Novel        | `0.93, 0.87, 0.73`  | `0.15, 0.12, 0.08`  | Warm paper, dark text       |
| Grass        | `0.0, 0.1, 0.0`     | `0.8, 1.0, 0.8`     | Dark green, light green     |
| Red Sands    | `0.47, 0.15, 0.02`  | `0.85, 0.78, 0.66`  | Dark red-brown, sand text   |

For light-background themes (Novel), ANSI colors must be adjusted to be dark instead of bright.

## Bundled Scripts

- **`scripts/create-iterm-profile.sh`** — Create a new iTerm2 Dynamic Profile with full colors, badge, and ANSI palette
- **`scripts/list-iterm-profiles.sh`** — List all Claude-managed profiles with their settings
- **`scripts/remove-iterm-profile.sh`** — Remove a profile by name
