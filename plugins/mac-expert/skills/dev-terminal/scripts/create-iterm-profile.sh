#!/bin/bash
# Creates an iTerm2 Dynamic Profile for a Claude Code dev terminal
#
# Usage: create-iterm-profile.sh <name> <directory> <bg-color> [fg-color] [badge-text] [startup-command]
#   name:            Profile name (e.g., "jiralyzer-dev", "jiralyzer-prod")
#   directory:       Working directory path
#   bg-color:        Background color as "R,G,B" floats 0.0-1.0 (e.g., "0.0,0.0,0.2" for dark blue)
#   fg-color:        Foreground color as "R,G,B" floats (default: "0.9,0.9,0.9" light gray)
#   badge-text:      Optional badge text shown on terminal (default: uppercase of name)
#   startup-command: Optional command to run on open (default: "claude")

set -euo pipefail

NAME="${1:?Usage: $0 <name> <directory> <bg-color> [fg-color] [badge-text] [startup-command]}"
DIRECTORY="${2:?Missing directory}"
BG_COLOR="${3:?Missing bg-color (R,G,B floats)}"
FG_COLOR="${4:-0.9,0.9,0.9}"
BADGE_TEXT="${5:-$(echo "$NAME" | tr '[:lower:]' '[:upper:]')}"
STARTUP_CMD="${6:-claude}"

# Parse background RGB
BG_R=$(echo "$BG_COLOR" | cut -d',' -f1)
BG_G=$(echo "$BG_COLOR" | cut -d',' -f2)
BG_B=$(echo "$BG_COLOR" | cut -d',' -f3)

# Parse foreground RGB
FG_R=$(echo "$FG_COLOR" | cut -d',' -f1)
FG_G=$(echo "$FG_COLOR" | cut -d',' -f2)
FG_B=$(echo "$FG_COLOR" | cut -d',' -f3)

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
      "Badge Color": {
        "Red Component": 1.0,
        "Green Component": 1.0,
        "Blue Component": 1.0,
        "Alpha Component": 0.5
      },
      "Badge Font": "Helvetica-Bold",
      "Badge Max Width": 0.25,
      "Badge Max Height": 0.15,
      "Background Color": {
        "Red Component": $BG_R,
        "Green Component": $BG_G,
        "Blue Component": $BG_B
      },
      "Foreground Color": {
        "Red Component": $FG_R,
        "Green Component": $FG_G,
        "Blue Component": $FG_B
      },
      "Bold Color": {
        "Red Component": 1.0,
        "Green Component": 1.0,
        "Blue Component": 1.0
      },
      "Cursor Color": {
        "Red Component": $FG_R,
        "Green Component": $FG_G,
        "Blue Component": $FG_B
      },
      "Cursor Text Color": {
        "Red Component": $BG_R,
        "Green Component": $BG_G,
        "Blue Component": $BG_B
      },
      "Selected Text Color": {
        "Red Component": 1.0,
        "Green Component": 1.0,
        "Blue Component": 1.0
      },
      "Selection Color": {
        "Red Component": 0.2,
        "Green Component": 0.3,
        "Blue Component": 0.5
      },
      "Ansi 0 Color": {
        "Red Component": 0.0,
        "Green Component": 0.0,
        "Blue Component": 0.0
      },
      "Ansi 1 Color": {
        "Red Component": 1.0,
        "Green Component": 0.5,
        "Blue Component": 0.5
      },
      "Ansi 2 Color": {
        "Red Component": 0.5,
        "Green Component": 1.0,
        "Blue Component": 0.5
      },
      "Ansi 3 Color": {
        "Red Component": 1.0,
        "Green Component": 1.0,
        "Blue Component": 0.5
      },
      "Ansi 4 Color": {
        "Red Component": 0.5,
        "Green Component": 0.7,
        "Blue Component": 1.0
      },
      "Ansi 5 Color": {
        "Red Component": 1.0,
        "Green Component": 0.5,
        "Blue Component": 1.0
      },
      "Ansi 6 Color": {
        "Red Component": 0.5,
        "Green Component": 1.0,
        "Blue Component": 1.0
      },
      "Ansi 7 Color": {
        "Red Component": 0.9,
        "Green Component": 0.9,
        "Blue Component": 0.9
      },
      "Ansi 8 Color": {
        "Red Component": 0.5,
        "Green Component": 0.5,
        "Blue Component": 0.5
      },
      "Ansi 9 Color": {
        "Red Component": 1.0,
        "Green Component": 0.6,
        "Blue Component": 0.6
      },
      "Ansi 10 Color": {
        "Red Component": 0.6,
        "Green Component": 1.0,
        "Blue Component": 0.6
      },
      "Ansi 11 Color": {
        "Red Component": 1.0,
        "Green Component": 1.0,
        "Blue Component": 0.6
      },
      "Ansi 12 Color": {
        "Red Component": 0.6,
        "Green Component": 0.8,
        "Blue Component": 1.0
      },
      "Ansi 13 Color": {
        "Red Component": 1.0,
        "Green Component": 0.6,
        "Blue Component": 1.0
      },
      "Ansi 14 Color": {
        "Red Component": 0.6,
        "Green Component": 1.0,
        "Blue Component": 1.0
      },
      "Ansi 15 Color": {
        "Red Component": 1.0,
        "Green Component": 1.0,
        "Blue Component": 1.0
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
