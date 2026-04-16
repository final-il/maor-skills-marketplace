#!/bin/bash
# Removes a Claude-managed iTerm2 Dynamic Profile by name
#
# Usage: remove-iterm-profile.sh <profile-name>
#   profile-name: The name of the profile to remove (e.g., "Dev Claude")

set -euo pipefail

NAME="${1:?Usage: $0 <profile-name>}"

PROFILES_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

if [ ! -d "$PROFILES_DIR" ]; then
  echo "No iTerm2 DynamicProfiles directory found."
  exit 1
fi

shopt -s nullglob
FILES=("$PROFILES_DIR"/claude-*.json)
shopt -u nullglob

FOUND=0
for f in "${FILES[@]}"; do
  if python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for p in data.get('Profiles', []):
    if p.get('Name') == sys.argv[2]:
        sys.exit(0)
sys.exit(1)
" "$f" "$NAME" 2>/dev/null; then
    rm "$f"
    echo "Removed profile '$NAME' (file: $f)"
    FOUND=1
    break
  fi
done

if [ $FOUND -eq 0 ]; then
  echo "Profile '$NAME' not found."
  exit 1
fi
