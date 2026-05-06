#!/usr/bin/env bash
# Usage:
#   sync-claude-config.sh           # Claude dirs → nix repo
#   sync-claude-config.sh --apply   # nix repo → Claude dirs

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_CLAUDE="$REPO/modules/claude"

GREEN='\033[1;32m' BLUE='\033[1;34m' DIM='\033[2m' RESET='\033[0m'

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

# ── File pairs ───────────────────────────────────────────────────
declare -a LIVE=(
  "$HOME/.claude/settings.json"
  "$HOME/.claude-personal/settings.json"
  "$HOME/.claude-work/settings.json"
  "$HOME/.config/claude-profiles/statusline.sh"
  "$HOME/.claude/plugins/installed_plugins.json"
)
declare -a REPO_FILES=(
  "$REPO_CLAUDE/settings.json"
  "$REPO_CLAUDE/settings.json"
  "$REPO_CLAUDE/settings.json"
  "$REPO_CLAUDE/statusline.sh"
  "$REPO_CLAUDE/plugins/installed_plugins.json"
)

if $APPLY; then
  SRCS=("${REPO_FILES[@]}")
  DSTS=("${LIVE[@]}")
  DIRECTION="nix-darwin → Claude dirs"
else
  SRCS=("${LIVE[@]}")
  DSTS=("${REPO_FILES[@]}")
  DIRECTION="Claude dirs → nix-darwin"
fi

# ── Custom local plugins (dirs only, exclude cache + marketplaces) ──
LIVE_PLUGINS_DIR="$HOME/.claude/plugins"
REPO_PLUGINS_DIR="$REPO_CLAUDE/plugins"
EXCLUDE_PLUGINS=("cache" "marketplaces")

if $APPLY; then
  CUSTOM_SRC_BASE="$REPO_PLUGINS_DIR"
  CUSTOM_DST_BASE="$LIVE_PLUGINS_DIR"
else
  CUSTOM_SRC_BASE="$LIVE_PLUGINS_DIR"
  CUSTOM_DST_BASE="$REPO_PLUGINS_DIR"
fi

changed_files=()
changed_plugins=()

# ── Check flat file diffs ────────────────────────────────────────
for i in "${!SRCS[@]}"; do
  src="${SRCS[$i]}"; dst="${DSTS[$i]}"
  [[ -f "$src" ]] || continue
  if [[ ! -f "$dst" ]] || ! diff -q "$src" "$dst" &>/dev/null; then
    changed_files+=("$i")
  fi
done

# ── Check custom plugin diffs ────────────────────────────────────
if [[ -d "$CUSTOM_SRC_BASE" ]]; then
  for plugin_dir in "$CUSTOM_SRC_BASE"/*/; do
    [[ -d "$plugin_dir" ]] || continue
    name=$(basename "$plugin_dir")
    skip=false
    for ex in "${EXCLUDE_PLUGINS[@]}"; do [[ "$name" == "$ex" ]] && skip=true; done
    $skip && continue
    dst_dir="$CUSTOM_DST_BASE/$name"
    if [[ ! -d "$dst_dir" ]] || ! diff -rq "$plugin_dir" "$dst_dir" &>/dev/null; then
      changed_plugins+=("$name")
    fi
  done
fi

if [[ ${#changed_files[@]} -eq 0 && ${#changed_plugins[@]} -eq 0 ]]; then
  echo -e "${GREEN}Already in sync ($DIRECTION). Nothing to do.${RESET}"
  exit 0
fi

echo -e "${BLUE}Direction: $DIRECTION${RESET}"

# ── Show diffs ───────────────────────────────────────────────────
if [[ ${#changed_files[@]} -gt 0 ]]; then
  echo -e "${BLUE}Changed files:${RESET}"
  for i in "${changed_files[@]}"; do echo "  • $(basename "${SRCS[$i]}")"; done
  echo ""
  for i in "${changed_files[@]}"; do
    src="${SRCS[$i]}"; dst="${DSTS[$i]}"
    echo -e "${DIM}── diff: $(basename "$src") ──${RESET}"
    if [[ -f "$dst" ]]; then
      diff "$dst" "$src" || true
    else
      diff /dev/null "$src" || true
    fi
    echo ""
  done
fi

if [[ ${#changed_plugins[@]} -gt 0 ]]; then
  echo -e "${BLUE}Changed/new custom plugins:${RESET}"
  for p in "${changed_plugins[@]}"; do echo "  • $p"; done
  echo ""
fi

read -rp "Copy files? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Copy flat files ──────────────────────────────────────────────
for i in "${changed_files[@]}"; do
  src="${SRCS[$i]}"; dst="${DSTS[$i]}"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  [[ "$(basename "$dst")" == "statusline.sh" ]] && chmod +x "$dst"
done

# ── Copy custom plugins ──────────────────────────────────────────
for p in "${changed_plugins[@]}"; do
  src_dir="$CUSTOM_SRC_BASE/$p"
  dst_dir="$CUSTOM_DST_BASE/$p"
  mkdir -p "$dst_dir"
  rsync -a --delete "$src_dir/" "$dst_dir/"
done

if $APPLY; then
  echo -e "${GREEN}Applied. Claude dirs are now up to date.${RESET}"
else
  echo -e "${GREEN}Synced. Review with 'git diff' in $REPO, then commit.${RESET}"
fi
