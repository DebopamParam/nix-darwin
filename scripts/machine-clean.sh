#!/usr/bin/env bash
# machine-clean.sh — safe macOS cleanup
# Covers: Nix, Homebrew, Docker/OrbStack, npm, uv/pip, Xcode
#
# Docker cleanup behavior:
# - Always prunes stopped containers, dangling images, and unused networks
# - Uses fzf to optionally prune:
#   - Docker build cache
#   - Docker volumes
#   - All unused images
#
# Usage:
#   machine-clean.sh
#   machine-clean.sh --deep

set -euo pipefail

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
RESET='\033[0m'

sep() {
  echo -e "\n${DIM}────────────────────────────────────${RESET}"
}

has_arg() {
  local wanted="$1"
  shift
  for arg in "$@"; do
    [[ "$arg" == "$wanted" ]] && return 0
  done
  return 1
}

select_docker_optional_cleanups() {
  local selected=""

  if ! command -v fzf > /dev/null 2>&1; then
    echo -e "${YELLOW}[docker] fzf not found — optional Docker cleanup skipped.${RESET}"
    echo -e "${DIM}  Install fzf or use the safe defaults only.${RESET}"
    return 0
  fi

  local options=(
    "build-cache|Prune Docker build cache|Safe-ish, but future Docker builds may be slower"
    "all-unused-images|Prune all unused images|More aggressive than dangling-only; may remove images you will need to pull/build again"
    "volumes|Prune unused volumes|Risky: can delete database/project data stored in Docker volumes"
  )

  echo -e "${BLUE}[docker] Optional cleanup selector${RESET}"
  echo -e "${DIM}  Tab to select, Enter to confirm, Esc to skip optional Docker cleanup.${RESET}"

  selected=$(
    printf '%s\n' "${options[@]}" |
      awk -F'|' '{ printf "%-20s %-36s %s\n", $1, $2, $3 }' |
      fzf \
        --multi \
        --prompt="Docker cleanup › " \
        --header="Optional Docker cleanup. Volumes are risky." \
        --height=50% \
        --border=rounded \
        --marker="✓" \
        --preview-window=hidden
  ) || selected=""

  [[ -z "$selected" ]] && return 0

  if echo "$selected" | awk '{print $1}' | grep -qx "build-cache"; then
    echo -e "${BLUE}[docker] Pruning build cache...${RESET}"
    docker builder prune -f
  else
    echo -e "${DIM}  (build cache skipped)${RESET}"
  fi

  if echo "$selected" | awk '{print $1}' | grep -qx "all-unused-images"; then
    echo -e "${YELLOW}[docker] Pruning all unused images...${RESET}"
    docker image prune -a -f
  else
    echo -e "${DIM}  (all unused images skipped — dangling images already pruned)${RESET}"
  fi

  if echo "$selected" | awk '{print $1}' | grep -qx "volumes"; then
    echo -e "${YELLOW}[docker] Pruning unused volumes...${RESET}"
    docker volume prune -f
  else
    echo -e "${DIM}  (volumes skipped — safest default)${RESET}"
  fi
}

# ── 1. Nix garbage collection ────────────────────────────────────
sep
if has_arg "--deep" "$@"; then
  echo -e "${BLUE}[nix] Aggressive cleanup! Removing ALL unpinned garbage...${RESET}"
  nix-collect-garbage -d
  sudo nix-collect-garbage -d
else
  echo -e "${BLUE}[nix] Collecting garbage older than 15 days...${RESET}"
  sudo nix-collect-garbage --delete-older-than 15d
fi
echo -e "${GREEN}[nix] Done.${RESET}"

# ── 2. Homebrew ──────────────────────────────────────────────────
sep
echo -e "${BLUE}[brew] Removing old versions and stale downloads...${RESET}"
brew cleanup
brew autoremove

if [[ "${1:-}" == "--deep" ]]; then
  echo -e "${BLUE}[brew] Deep cleanup: removing cached Homebrew downloads...${RESET}"
  rm -rf "$HOME/Library/Caches/Homebrew/downloads"/*
fi

echo -e "${GREEN}[brew] Done.${RESET}"

# ── 3. Docker / OrbStack ─────────────────────────────────────────
sep
echo -e "${BLUE}[docker] Checking OrbStack...${RESET}"

docker_cleanup() {
  echo -e "${BLUE}[docker] Pruning stopped containers...${RESET}"
  docker container prune -f

  echo -e "${BLUE}[docker] Pruning dangling images...${RESET}"
  docker image prune -f

  echo -e "${BLUE}[docker] Pruning unused networks...${RESET}"
  docker network prune -f

  select_docker_optional_cleanups

  echo -e "${GREEN}[docker] Done.${RESET}"
}

if pgrep -x "OrbStack" > /dev/null 2>&1; then
  docker_cleanup
else
  echo -e "${YELLOW}[docker] OrbStack is not running.${RESET}"
  echo -e "${DIM}  Start OrbStack and press Enter to run Docker cleanup, or 's' to skip:${RESET} \c"
  read -r ans

  if [[ "${ans:-}" =~ ^[Ss]$ ]]; then
    echo -e "${DIM}  Docker cleanup skipped.${RESET}"
  else
    echo -e "${DIM}  Waiting for Docker socket...${RESET}"

    for i in {1..10}; do
      docker info > /dev/null 2>&1 && break
      sleep 2
      echo -e "${DIM}  Still waiting... (${i}/10)${RESET}"
    done

    if docker info > /dev/null 2>&1; then
      docker_cleanup
    else
      echo -e "${YELLOW}[docker] Docker socket not ready after 20s — skipping.${RESET}"
    fi
  fi
fi

# ── 4. npm cache ─────────────────────────────────────────────────
sep
if command -v npm > /dev/null 2>&1; then
  echo -e "${BLUE}[npm] Cleaning cache...${RESET}"
  npm cache clean --force 2>/dev/null
  echo -e "${GREEN}[npm] Done.${RESET}"
else
  echo -e "${DIM}[npm] Not found — skipping.${RESET}"
fi

# ── 4.5 Playwright cache ─────────────────────────────────────────
sep
PLAYWRIGHT_CACHE="$HOME/Library/Caches/ms-playwright"
if [[ -d "$PLAYWRIGHT_CACHE" ]]; then
  size=$(du -sh "$PLAYWRIGHT_CACHE" 2>/dev/null | awk '{print $1}')
  echo -e "${BLUE}[playwright] Removing browser cache (${size})...${RESET}"
  rm -rf "$PLAYWRIGHT_CACHE"
  echo -e "${GREEN}[playwright] Done.${RESET}"
else
  echo -e "${DIM}[playwright] Cache not found — skipping.${RESET}"
fi

# ── 5. uv / pip cache ────────────────────────────────────────────
sep
if command -v uv > /dev/null 2>&1; then
  echo -e "${BLUE}[uv] Cleaning cache...${RESET}"
  uv cache clean
  echo -e "${GREEN}[uv] Done.${RESET}"
elif command -v pip > /dev/null 2>&1; then
  echo -e "${BLUE}[pip] Cleaning cache...${RESET}"
  pip cache purge 2>/dev/null || true
  echo -e "${GREEN}[pip] Done.${RESET}"
else
  echo -e "${DIM}[uv/pip] Not found — skipping.${RESET}"
fi

# ── 6. Xcode derived data ─────────────────────────────────────────
sep
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
if [[ -d "$DERIVED" ]]; then
  size=$(du -sh "$DERIVED" 2>/dev/null | awk '{print $1}')
  echo -e "${BLUE}[xcode] Removing DerivedData (${size})...${RESET}"
  rm -rf "$DERIVED"
  echo -e "${GREEN}[xcode] Done.${RESET}"
else
  echo -e "${DIM}[xcode] DerivedData not found — skipping.${RESET}"
fi

# ── Summary ───────────────────────────────────────────────────────
sep
echo -e "\n${GREEN}✓ Machine cleanup complete.${RESET}"