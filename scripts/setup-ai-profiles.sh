#!/usr/bin/env bash
# setup-ai-profiles.sh — mirror modules/home/ai-profiles.nix for bash machines
# (e.g. Linux dev containers without nix-darwin).
#
# Installs ~/.config/ai-profiles/{profile-sync.sh,init.sh} and sources init.sh
# from ~/.bashrc. The unified model (see notes/temp.md):
#   ~/.claude / ~/.codex        canonical home (all non-auth config)
#   ~/.claude-<p> / ~/.codex-<p> profile home (symlinks + real auth files only)
#
# Usage:
#   ./setup-ai-profiles.sh           # install / re-run safely
#   ./setup-ai-profiles.sh --uninstall
#
# Then launch with: claude-use <profile> / codex-use <profile>

set -euo pipefail

INIT_DIR="$HOME/.config/ai-profiles"
SYNC_FILE="$INIT_DIR/profile-sync.sh"
INIT_FILE="$INIT_DIR/init.sh"
BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> ai-profiles >>>"
MARKER_END="# <<< ai-profiles <<<"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }

uninstall() {
  log "Removing ai-profiles bash integration"
  if [ -f "$BASHRC" ] && grep -qF "$MARKER_BEGIN" "$BASHRC"; then
    tmp=$(mktemp)
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
      $0==b {skip=1; next}
      $0==e {skip=0; next}
      !skip
    ' "$BASHRC" > "$tmp"
    mv "$tmp" "$BASHRC"
    ok "Removed block from $BASHRC"
  fi
  rm -f "$SYNC_FILE" "$INIT_FILE"
  ok "Removed init scripts (profile dirs and symlinks left intact)"
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

mkdir -p "$INIT_DIR"

log "Writing $SYNC_FILE"
cat > "$SYNC_FILE" <<'EOF'
#!/usr/bin/env bash
# Usage: profile-sync.sh <canonical-dir> <profile-home> <auth-basename...>
set -euo pipefail

canon="$1"; home="$2"; shift 2
auth=" $* "
mkdir -p "$canon" "$home"

shopt -s dotglob nullglob

is_auth() { case "$auth" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Promote genuinely-new non-auth profile-local entries into canonical.
for e in "$home"/*; do
  n="$(basename "$e")"
  is_auth "$n" && continue
  case "$n" in *.pre-unify.bak) continue ;; esac
  [ -L "$e" ] && continue
  if [ ! -e "$canon/$n" ] && [ ! -L "$canon/$n" ]; then
    mv "$e" "$canon/$n"
  fi
done

# Link every canonical non-auth entry into the profile home.
for e in "$canon"/*; do
  n="$(basename "$e")"
  is_auth "$n" && continue
  l="$home/$n"
  if [ -L "$l" ] && [ "$(readlink "$l")" = "$e" ]; then
    continue
  fi
  if [ -e "$l" ] || [ -L "$l" ]; then
    rm -rf "$l"
  fi
  ln -s "$e" "$l"
done
EOF
chmod +x "$SYNC_FILE"
ok "$SYNC_FILE installed"

log "Writing $INIT_FILE"
cat > "$INIT_FILE" <<'EOF'
_AI_SYNC="$HOME/.config/ai-profiles/profile-sync.sh"

# ── Claude ──────────────────────────────────────────────────────
claude-use() {
  if [ -z "${1:-}" ]; then echo "usage: claude-use <profile>  (list: claude-ls)" >&2; return 1; fi
  local p="$1"; shift
  local h="$HOME/.claude-$p"
  bash "$_AI_SYNC" "$HOME/.claude" "$h" .claude.json .credentials.json
  CLAUDE_CONFIG_DIR="$h" command claude "$@"
}
claude-ls() { ls -d "$HOME"/.claude-*/ 2>/dev/null | sed 's#.*/\.claude-##; s#/##'; }
claude() {
  echo "❌  Don't run 'claude' directly. Use: claude-use <profile>" >&2
  echo "    profiles: $(claude-ls | paste -sd' ' -)" >&2
  return 1
}

# ── Codex ───────────────────────────────────────────────────────
codex-use() {
  if [ -z "${1:-}" ]; then echo "usage: codex-use <profile>  (list: codex-ls)" >&2; return 1; fi
  local p="$1"; shift
  local h="$HOME/.codex-$p"
  bash "$_AI_SYNC" "$HOME/.codex" "$h" auth.json
  CODEX_HOME="$h" command codex "$@"
}
codex-ls() { ls -d "$HOME"/.codex-*/ 2>/dev/null | sed 's#.*/\.codex-##; s#/##'; }
codex() {
  echo "❌  Don't run 'codex' directly. Use: codex-use <profile>" >&2
  echo "    profiles: $(codex-ls | paste -sd' ' -)" >&2
  return 1
}
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

log "Done. Open a new bash shell (or 'source ~/.bashrc') and try: claude-use <profile> / codex-use <profile>"
