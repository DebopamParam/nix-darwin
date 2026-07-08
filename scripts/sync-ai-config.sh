#!/usr/bin/env bash
# Sync canonical Claude + Codex config between the live homes and this repo.
# All non-auth config lives in the canonical homes (~/.claude, ~/.codex);
# profile homes are just symlinks, so there's nothing per-profile to sync.
#
# Usage:
#   sync-ai-config.sh           # live dirs → nix repo   (pull)
#   sync-ai-config.sh --apply   # nix repo → live dirs   (push)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_CLAUDE="$REPO/modules/claude"
REPO_CODEX="$REPO/modules/codex"

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

# ── File pairs (live ↔ repo) ─────────────────────────────────────
declare -a LIVE=(
  "$HOME/.claude/settings.json"
  "$HOME/.claude/CLAUDE.md"
  "$HOME/.claude/RTK.md"
  "$HOME/.config/ai-profiles/statusline.sh"
  "$HOME/.config/ccstatusline/settings.json"
  "$HOME/.codex/config.toml"
  "$HOME/.codex/AGENTS.md"
)
declare -a REPO_FILES=(
  "$REPO_CLAUDE/settings.json"
  "$REPO_CLAUDE/CLAUDE.md"
  "$REPO_CLAUDE/RTK.md"
  "$REPO_CLAUDE/statusline.sh"
  "$REPO_CLAUDE/ccstatusline-settings.json"
  "$REPO_CODEX/config.toml"
  "$REPO_CODEX/AGENTS.md"
)

# ── Directory pairs (synced wholesale via rsync --delete) ────────
declare -a LIVE_DIRS=(
  "$HOME/.claude/agents"
  "$HOME/.claude/commands"
  "$HOME/.claude/hooks"
)
declare -a REPO_DIRS=(
  "$REPO_CLAUDE/agents"
  "$REPO_CLAUDE/commands"
  "$REPO_CLAUDE/hooks"
)

if $APPLY; then
  SRCS=("${REPO_FILES[@]}")
  DSTS=("${LIVE[@]}")
  DIR_SRCS=("${REPO_DIRS[@]}")
  DIR_DSTS=("${LIVE_DIRS[@]}")
  DIRECTION="nix-darwin → live dirs"
else
  SRCS=("${LIVE[@]}")
  DSTS=("${REPO_FILES[@]}")
  DIR_SRCS=("${LIVE_DIRS[@]}")
  DIR_DSTS=("${REPO_DIRS[@]}")
  DIRECTION="live dirs → nix-darwin"
fi

changed_files=()
changed_dirs=()

# ── Check flat file diffs ────────────────────────────────────────
for i in "${!SRCS[@]}"; do
  src="${SRCS[$i]}"; dst="${DSTS[$i]}"
  [[ -f "$src" ]] || continue
  if [[ ! -f "$dst" ]] || ! diff -q "$src" "$dst" &>/dev/null; then
    changed_files+=("$i")
  fi
done

# ── Check whole-directory diffs ──────────────────────────────────
for i in "${!DIR_SRCS[@]}"; do
  src_dir="${DIR_SRCS[$i]}"; dst_dir="${DIR_DSTS[$i]}"
  [[ -d "$src_dir" ]] || continue
  if [[ ! -d "$dst_dir" ]] || ! diff -rq "$src_dir" "$dst_dir" &>/dev/null; then
    changed_dirs+=("$i")
  fi
done

if [[ ${#changed_files[@]} -eq 0 && ${#changed_dirs[@]} -eq 0 ]]; then
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

# ── Copy whole directories ───────────────────────────────────────
for i in "${changed_dirs[@]}"; do
  src_dir="${DIR_SRCS[$i]}"; dst_dir="${DIR_DSTS[$i]}"
  mkdir -p "$dst_dir"
  rsync -a --delete "$src_dir/" "$dst_dir/"
done

if $APPLY; then
  echo -e "${GREEN}Applied. Live dirs are now up to date.${RESET}"
else
  echo -e "${GREEN}Synced. Review with 'git diff' in $REPO, then commit.${RESET}"
fi
