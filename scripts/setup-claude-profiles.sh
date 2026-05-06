#!/usr/bin/env bash
# setup-claude-profiles.sh — mirror modules/home/claude-profiles.nix for bash
#
# Creates ~/.claude-personal and ~/.claude-work, symlinks shared assets from
# ~/.claude into each, installs ~/.config/claude-profiles/init.sh, and wires
# it into ~/.bashrc.
#
# Usage:
#   ./setup-claude-profiles.sh           # install / re-run safely
#   ./setup-claude-profiles.sh --uninstall

set -euo pipefail

INIT_DIR="$HOME/.config/claude-profiles"
INIT_FILE="$INIT_DIR/init.sh"
BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> claude-profiles >>>"
MARKER_END="# <<< claude-profiles <<<"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }

uninstall() {
  log "Removing claude-profiles bash integration"
  if [ -f "$BASHRC" ] && grep -qF "$MARKER_BEGIN" "$BASHRC"; then
    # Strip the block between markers (inclusive)
    tmp=$(mktemp)
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
      $0==b {skip=1; next}
      $0==e {skip=0; next}
      !skip
    ' "$BASHRC" > "$tmp"
    mv "$tmp" "$BASHRC"
    ok "Removed block from $BASHRC"
  fi
  rm -f "$INIT_FILE"
  ok "Removed $INIT_FILE (profile dirs and symlinks left intact)"
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

log "Creating profile directories"
mkdir -p "$HOME/.claude/plugins"
mkdir -p "$HOME/.claude-personal"
mkdir -p "$HOME/.claude-work"

log "Linking shared assets into each profile"
for profile in personal work; do
  ln -sfn "$HOME/.claude/plugins" "$HOME/.claude-$profile/plugins"
  [ -f "$HOME/.claude/settings.json" ] && \
    ln -sfn "$HOME/.claude/settings.json" "$HOME/.claude-$profile/settings.json"
  [ -f "$HOME/.claude/CLAUDE.md" ] && \
    ln -sfn "$HOME/.claude/CLAUDE.md" "$HOME/.claude-$profile/CLAUDE.md"
  ok "~/.claude-$profile ready"
done

log "Writing $INIT_FILE"
mkdir -p "$INIT_DIR"
cat > "$INIT_FILE" <<'EOF'
# Claude Code profile switcher (bash)
# ~ is intentionally evaluated at shell-startup time inside the container,
# so it resolves correctly whether the container user is root, vscode, etc.
_CLAUDE_BASE="$(eval echo ~)"
alias claude-personal="CLAUDE_CONFIG_DIR=${_CLAUDE_BASE}/.claude-personal command claude"
alias claude-work="CLAUDE_CONFIG_DIR=${_CLAUDE_BASE}/.claude-work command claude"

# Block bare `claude` — a function shadows the binary and can't be bypassed
claude() {
  echo "❌  Don't use 'claude' directly. Use:" >&2
  echo "     claude-work      → work account" >&2
  echo "     claude-personal  → personal account" >&2
  return 1
}

unset _CLAUDE_BASE
EOF
chmod +x "$INIT_FILE"
ok "$INIT_FILE installed"

log "Wiring source into $BASHRC"
touch "$BASHRC"
if grep -qF "$MARKER_BEGIN" "$BASHRC"; then
  ok "Already wired (markers present), skipping"
else
  {
    printf '\n%s\n' "$MARKER_BEGIN"
    printf '[ -f "%s" ] && source "%s"\n' "$INIT_FILE" "$INIT_FILE"
    printf '%s\n' "$MARKER_END"
  } >> "$BASHRC"
  ok "Appended source block to $BASHRC"
fi

log "Done. Open a new bash shell (or 'source ~/.bashrc') and try: claude-personal / claude-work"
