#!/bin/bash
# Creates an iTerm2 Dynamic Profile for a Claude Code dev terminal
#
# Usage: create-iterm-profile.sh <name> <directory> <bg-color> [badge-text] [startup-command]
#   name:            Profile name (e.g., "Dev Claude", "Prod Claude")
#   directory:       Working directory path
#   bg-color:        Background color as "R,G,B" floats 0.0-1.0 (e.g., "0.0,0.0,0.2" for dark blue)
#   badge-text:      Optional badge text shown on terminal (default: uppercase of name)
#   startup-command: Optional command to run on open (default: "claude")

set -euo pipefail

NAME="${1:?Usage: $0 <name> <directory> <bg-color> [badge-text] [startup-command]}"
DIRECTORY="${2:?Missing directory}"
BG_COLOR="${3:?Missing bg-color (R,G,B floats)}"
BADGE_TEXT="${4:-$(echo "$NAME" | tr '[:lower:]' '[:upper:]')}"
STARTUP_CMD="${5:-claude}"

# Parse RGB
R=$(echo "$BG_COLOR" | cut -d',' -f1)
G=$(echo "$BG_COLOR" | cut -d',' -f2)
B=$(echo "$BG_COLOR" | cut -d',' -f3)

# Generate a stable GUID from the name
GUID="claude-profile-$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"

PROFILES_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
mkdir -p "$PROFILES_DIR"

PROFILE_FILE="$PROFILES_DIR/claude-${GUID}.json"

cat > "$PROFILE_FILE" <<EOF
{
  "Profiles": [
    {
      "Name": "$NAME",
      "Guid": "$GUID",
      "Custom Directory": "Yes",
      "Working Directory": "$DIRECTORY",
      "Initial Text": "$STARTUP_CMD",
      "Tags": ["Claude"],
      "Badge Text": "$BADGE_TEXT",
      "Background Color": {
        "Red Component": $R,
        "Green Component": $G,
        "Blue Component": $B
      },
      "Foreground Color": {
        "Red Component": 0.9,
        "Green Component": 0.9,
        "Blue Component": 0.9
      }
    }
  ]
}
EOF

echo "Created iTerm2 profile '$NAME' at: $PROFILE_FILE"
echo "  Directory: $DIRECTORY"
echo "  Startup:   $STARTUP_CMD"
echo "  Badge:     $BADGE_TEXT"
echo ""
echo "Open iTerm2 > Profiles > $NAME to use it."
