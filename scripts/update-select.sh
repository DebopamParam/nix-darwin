#!/usr/bin/env bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────
FLAKE_DIR="$HOME/.config/nix-darwin"
BLUE='\033[1;34m'  GREEN='\033[1;32m'  DIM='\033[2m'  YELLOW='\033[1;33m'  RESET='\033[0m'

# ── Gather outdated packages ────────────────────────────────────
items=()

echo -e "${BLUE}Checking Homebrew...${RESET}"
# Note: `brew update` is a no-op here — nix-homebrew pins taps as read-only
# Nix store paths. Brew's outdated info is whatever the current pinned tap
# reports. To see newer versions, update the homebrew-cask flake input.
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pkg=$(echo "$line" | awk '{print $1}')
  cur=$(echo "$line" | awk -F'[()]' '{print $2}' | awk '{print $1}')
  new=$(echo "$line" | awk '{print $NF}')
  items+=("[brew]  $pkg  ($cur → $new)")
done < <(brew outdated --greedy --verbose 2>/dev/null || true)

echo -e "${BLUE}Checking Mac App Store...${RESET}"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # mas outdated format: "123456789 App Name (1.0 -> 2.0)"
  app_id=$(echo "$line" | awk '{print $1}')
  rest=$(echo "$line" | cut -d' ' -f2-)
  items+=("[mas]   $rest  (id:$app_id)")
done < <(mas outdated 2>/dev/null || true)

echo -e "${BLUE}Checking Nix flake inputs...${RESET}"
if [[ -f "$FLAKE_DIR/flake.lock" ]]; then
  while IFS= read -r input; do
    [[ -z "$input" ]] && continue
    locked=$(jq -r --arg i "$input" '.nodes[$i].locked.lastModified // empty' "$FLAKE_DIR/flake.lock" 2>/dev/null)
    if [[ -n "$locked" ]]; then
      age=$(( ($(date +%s) - locked) / 86400 ))
      # Flag stale homebrew-cask — it gates all brew cask versions
      tag=""
      if [[ "$input" == "homebrew-cask" && $age -gt 7 ]]; then
        tag="  ⚠ gates brew versions"
      fi
      items+=("[nix]   $input  (locked ${age}d ago)$tag")
    else
      items+=("[nix]   $input")
    fi
  done < <(jq -r '.nodes.root.inputs | keys[]' "$FLAKE_DIR/flake.lock" 2>/dev/null)
fi

# ── Nothing to do? ──────────────────────────────────────────────
if [[ ${#items[@]} -eq 0 ]]; then
  echo -e "${GREEN}Everything is up to date!${RESET}"
  exit 0
fi

# ── fzf multi-select ────────────────────────────────────────────
echo ""
echo -e "${DIM}Tab to select, Enter to confirm, Esc to cancel${RESET}"
echo ""

selected=$(printf '%s\n' "${items[@]}" | fzf \
  --multi \
  --header="Select packages to update (Tab=toggle, Enter=go)" \
  --border=rounded \
  --height=80% \
  --prompt="Update › " \
  --marker="✓" \
  --preview-window=hidden \
) || { echo "Cancelled."; exit 0; }

# ── Parse selections ────────────────────────────────────────────
brew_pkgs=()
mas_ids=()
nix_inputs=()

while IFS= read -r sel; do
  [[ -z "$sel" ]] && continue
  case "$sel" in
    "[brew]"*)
      pkg=$(echo "$sel" | awk '{print $2}')
      brew_pkgs+=("$pkg")
      ;;
    "[mas]"*)
      app_id=$(echo "$sel" | grep -oE 'id:[0-9]+' | cut -d: -f2)
      mas_ids+=("$app_id")
      ;;
    "[nix]"*)
      input=$(echo "$sel" | awk '{print $2}')
      nix_inputs+=("$input")
      ;;
  esac
done <<< "$selected"

# ══════════════════════════════════════════════════════════════
#  EXECUTION ORDER: nix first → brew → mas
#  Rationale: updating homebrew-cask unlocks newer versions, so
#  brew upgrades must run AFTER the tap has been refreshed.
# ══════════════════════════════════════════════════════════════

# ── 1. Nix flake input updates + rebuild ────────────────────────
if [[ ${#nix_inputs[@]} -gt 0 ]]; then
  echo -e "\n${BLUE}Updating Nix flake inputs:${RESET} ${nix_inputs[*]}"
  cd "$FLAKE_DIR"
  for input in "${nix_inputs[@]}"; do
    nix flake update "$input"
  done

  echo -e "\n${BLUE}Rebuilding nix-darwin...${RESET}"
  sudo darwin-rebuild switch --flake "$FLAKE_DIR"

  # If homebrew-cask was refreshed, offer newly available brew upgrades
  # that weren't visible in the initial scan. Skip anything already queued.
  if [[ " ${nix_inputs[*]} " == *" homebrew-cask "* ]]; then
    echo -e "\n${BLUE}homebrew-cask tap refreshed — scanning for newly available upgrades...${RESET}"

    new_brew=()
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      pkg=$(echo "$line" | awk '{print $1}')
      # Skip if already in user's original selection
      already=false
      for p in "${brew_pkgs[@]}"; do [[ "$p" == "$pkg" ]] && already=true; done
      $already && continue
      cur=$(echo "$line" | awk -F'[()]' '{print $2}' | awk '{print $1}')
      new=$(echo "$line" | awk '{print $NF}')
      new_brew+=("$pkg  ($cur → $new)")
    done < <(brew outdated --greedy --verbose 2>/dev/null || true)

    if [[ ${#new_brew[@]} -eq 0 ]]; then
      echo -e "${DIM}No additional brew upgrades available.${RESET}"
    else
      echo ""
      echo -e "${DIM}Tab to add to upgrade queue, Enter to confirm, Esc to skip${RESET}"
      echo ""
      extra=$(printf '%s\n' "${new_brew[@]}" | fzf \
        --multi \
        --header="Newly available brew upgrades (Tab=toggle, Enter=add, Esc=skip)" \
        --border=rounded \
        --height=60% \
        --prompt="Add › " \
        --marker="✓" \
        --preview-window=hidden \
      ) || extra=""

      if [[ -n "$extra" ]]; then
        while IFS= read -r sel; do
          [[ -z "$sel" ]] && continue
          pkg=$(echo "$sel" | awk '{print $1}')
          brew_pkgs+=("$pkg")
        done <<< "$extra"
      fi
    fi
  fi
fi

# ── 2. Brew upgrades (runs with fresh tap if nix ran first) ─────
if [[ ${#brew_pkgs[@]} -gt 0 ]]; then
  echo -e "\n${BLUE}Upgrading Homebrew packages:${RESET} ${brew_pkgs[*]}"
  brew upgrade "${brew_pkgs[@]}"
fi

# ── 3. MAS upgrades ─────────────────────────────────────────────
if [[ ${#mas_ids[@]} -gt 0 ]]; then
  echo -e "\n${BLUE}Upgrading App Store apps:${RESET} ${mas_ids[*]}"
  for id in "${mas_ids[@]}"; do
    mas upgrade "$id"
  done
fi

echo -e "\n${GREEN}Done!${RESET}"