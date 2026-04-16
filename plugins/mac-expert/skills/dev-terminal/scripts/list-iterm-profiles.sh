#!/bin/bash
# Lists all Claude-managed iTerm2 Dynamic Profiles
#
# Usage: list-iterm-profiles.sh

PROFILES_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

if [ ! -d "$PROFILES_DIR" ]; then
  echo "No iTerm2 DynamicProfiles directory found."
  exit 0
fi

shopt -s nullglob
FILES=("$PROFILES_DIR"/claude-*.json)
shopt -u nullglob

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No Claude-managed iTerm2 profiles found."
  exit 0
fi

echo "Claude-managed iTerm2 profiles:"
echo ""

for f in "${FILES[@]}"; do
  python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for p in data.get('Profiles', []):
    name = p.get('Name', 'Unknown')
    directory = p.get('Working Directory', 'N/A')
    badge = p.get('Badge Text', '')
    cmd = p.get('Initial Text', 'N/A')
    bg = p.get('Background Color', {})
    r = bg.get('Red Component', 0)
    g = bg.get('Green Component', 0)
    b = bg.get('Blue Component', 0)
    print(f'  {name}')
    print(f'    Directory: {directory}')
    print(f'    Command:   {cmd}')
    print(f'    Badge:     {badge}')
    print(f'    BG Color:  ({r},{g},{b})')
    print(f'    File:      {sys.argv[1]}')
    print()
" "$f"
done
