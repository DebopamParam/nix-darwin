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

# ── Ensure ccstatusline is installed ─────────────────────────────
if ! [[ -f "$(npm root -g 2>/dev/null)/ccstatusline/dist/ccstatusline.js" ]]; then
  echo -e "${BLUE}ccstatusline is not installed globally.${RESET}"
  read -rp "Install it now with 'sudo npm install -g ccstatusline'? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    sudo npm install -g ccstatusline
  else
    echo -e "${DIM}Skipping ccstatusline install — statusline will be empty until installed.${RESET}"
  fi
fi

# ── File pairs ───────────────────────────────────────────────────
declare -a LIVE=(
  "$HOME/.claude/settings.json"
  "$HOME/.claude-personal/settings.json"
  "$HOME/.claude-work/settings.json"
  "$HOME/.config/claude-profiles/statusline.sh"
  "$HOME/.claude/plugins/installed_plugins.json"
  "$HOME/.config/ccstatusline/settings.json"
  "$HOME/.claude/CLAUDE.md"
  "$HOME/.claude/RTK.md"
  "$HOME/.claude-personal/CLAUDE.md"
  "$HOME/.claude-work/CLAUDE.md"
)
declare -a REPO_FILES=(
  "$REPO_CLAUDE/settings.json"
  "$REPO_CLAUDE/settings.json"
  "$REPO_CLAUDE/settings.json"
  "$REPO_CLAUDE/statusline.sh"
  "$REPO_CLAUDE/plugins/installed_plugins.json"
  "$REPO_CLAUDE/ccstatusline-settings.json"
  "$REPO_CLAUDE/CLAUDE.md"
  "$REPO_CLAUDE/RTK.md"
  "$REPO_CLAUDE/personal/CLAUDE.md"
  "$REPO_CLAUDE/work/CLAUDE.md"
)

# ── Directory pairs (synced wholesale via rsync --delete) ────────
declare -a LIVE_DIRS=(
  "$HOME/.claude/agents"
  "$HOME/.claude/commands"
  "$HOME/.claude/hooks"
  "$HOME/.claude-personal/agents"
  "$HOME/.claude-personal/commands"
  "$HOME/.claude-personal/hooks"
  "$HOME/.claude-work/agents"
  "$HOME/.claude-work/commands"
  "$HOME/.claude-work/hooks"
)
declare -a REPO_DIRS=(
  "$REPO_CLAUDE/agents"
  "$REPO_CLAUDE/commands"
  "$REPO_CLAUDE/hooks"
  "$REPO_CLAUDE/personal/agents"
  "$REPO_CLAUDE/personal/commands"
  "$REPO_CLAUDE/personal/hooks"
  "$REPO_CLAUDE/work/agents"
  "$REPO_CLAUDE/work/commands"
  "$REPO_CLAUDE/work/hooks"
)

if $APPLY; then
  SRCS=("${REPO_FILES[@]}")
  DSTS=("${LIVE[@]}")
  DIR_SRCS=("${REPO_DIRS[@]}")
  DIR_DSTS=("${LIVE_DIRS[@]}")
  DIRECTION="nix-darwin → Claude dirs"
else
  SRCS=("${LIVE[@]}")
  DSTS=("${REPO_FILES[@]}")
  DIR_SRCS=("${LIVE_DIRS[@]}")
  DIR_DSTS=("${REPO_DIRS[@]}")
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
changed_dirs=()

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

# ── Check whole-directory diffs ──────────────────────────────────
for i in "${!DIR_SRCS[@]}"; do
  src_dir="${DIR_SRCS[$i]}"; dst_dir="${DIR_DSTS[$i]}"
  [[ -d "$src_dir" ]] || continue
  if [[ ! -d "$dst_dir" ]] || ! diff -rq "$src_dir" "$dst_dir" &>/dev/null; then
    changed_dirs+=("$i")
  fi
done

if [[ ${#changed_files[@]} -eq 0 && ${#changed_plugins[@]} -eq 0 && ${#changed_dirs[@]} -eq 0 ]]; then
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

if [[ ${#changed_dirs[@]} -gt 0 ]]; then
  echo -e "${BLUE}Changed directories:${RESET}"
  for i in "${changed_dirs[@]}"; do
    echo "  • ${DIR_SRCS[$i]} → ${DIR_DSTS[$i]}"
  done
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

# ── Copy whole directories ───────────────────────────────────────
for i in "${changed_dirs[@]}"; do
  src_dir="${DIR_SRCS[$i]}"; dst_dir="${DIR_DSTS[$i]}"
  mkdir -p "$dst_dir"
  rsync -a --delete "$src_dir/" "$dst_dir/"
done

if $APPLY; then
  echo -e "${GREEN}Applied. Claude dirs are now up to date.${RESET}"
else
  echo -e "${GREEN}Synced. Review with 'git diff' in $REPO, then commit.${RESET}"
fi
