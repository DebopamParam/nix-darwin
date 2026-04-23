#!/usr/bin/env bash
# machine-clean.sh — safe macOS cleanup
# Covers: Nix, Homebrew, Docker/OrbStack, npm, uv/pip, Xcode

set -euo pipefail

BLUE='\033[1;34m'  GREEN='\033[1;32m'  YELLOW='\033[1;33m'  DIM='\033[2m'  RESET='\033[0m'

sep() { echo -e "\n${DIM}────────────────────────────────────${RESET}"; }

# ── 1. Nix garbage collection ────────────────────────────────────
sep
if [[ "${1:-}" == "--deep" ]]; then
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
brew autoremove        # removes unused dependencies
echo -e "${GREEN}[brew] Done.${RESET}"

# ── 3. Docker / OrbStack ─────────────────────────────────────────
sep
echo -e "${BLUE}[docker] Checking OrbStack...${RESET}"

docker_cleanup() {
  echo -e "${BLUE}[docker] Pruning stopped containers...${RESET}"
  docker container prune -f

  echo -e "${BLUE}[docker] Pruning dangling images...${RESET}"
  docker image prune -f   # dangling only — NOT -a (keeps images used by containers)

  echo -e "${BLUE}[docker] Pruning unused networks...${RESET}"
  docker network prune -f

  # volumes intentionally skipped — too risky, could delete persistent data
  echo -e "${DIM}  (volumes skipped — run 'docker volume prune' manually if needed)${RESET}"
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
    # Wait for OrbStack daemon to be ready
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