#!/bin/bash
# Install Claude Code Thinking Tokens Statusline
# Usage: ./install.sh        (install)
#        ./install.sh remove  (uninstall)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_CONFIG='{"type":"command","command":"~/.claude/statusline.sh"}'

# Colors
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
RESET='\033[0m'

info()  { printf "${GREEN}[ok]${RESET}  %s\n" "$1"; }
warn()  { printf "${YELLOW}[!!]${RESET}  %s\n" "$1"; }
error() { printf "${RED}[err]${RESET} %s\n" "$1"; exit 1; }

# --- Uninstall ---
if [ "$1" = "remove" ]; then
  echo "Removing statusline..."
  [ -f "$TARGET" ] && rm "$TARGET" && info "Removed $TARGET" || warn "$TARGET not found"
  if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
    jq 'del(.statusLine)' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    info "Removed statusLine from $SETTINGS"
  fi
  echo "Done."
  exit 0
fi

# --- Install ---
echo "Installing Claude Code Thinking Tokens Statusline..."
echo ""

# Check dependencies
command -v jq &>/dev/null || error "jq is required but not installed. Install: brew install jq (macOS) or apt install jq (Linux)"

# Check Claude Code directory
[ -d "$HOME/.claude" ] || error "$HOME/.claude not found. Is Claude Code installed?"

# Copy statusline script
cp "$SCRIPT_DIR/statusline.sh" "$TARGET"
chmod +x "$TARGET"
info "Copied statusline.sh to $TARGET"

# Merge statusLine config into settings.json
if [ -f "$SETTINGS" ]; then
  # Check if statusLine already exists
  existing=$(jq -r '.statusLine // empty' "$SETTINGS" 2>/dev/null)
  if [ -n "$existing" ]; then
    warn "Existing statusLine config found, overwriting"
  fi
  jq --argjson sl "$STATUSLINE_CONFIG" '. + {statusLine: $sl}' "$SETTINGS" > "${SETTINGS}.tmp"
  mv "${SETTINGS}.tmp" "$SETTINGS"
  info "Updated statusLine in $SETTINGS"
else
  echo "{\"statusLine\": $STATUSLINE_CONFIG}" | jq '.' > "$SETTINGS"
  info "Created $SETTINGS with statusLine config"
fi

echo ""
info "Installation complete!"
echo ""
echo "  The statusline will appear in your next Claude Code session."
echo "  Start a new session with: claude"
echo ""
echo "  To remove: ./install.sh remove"
