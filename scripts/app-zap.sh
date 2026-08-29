#!/usr/bin/env bash
# app-zap.sh — interactive, manual app remover for ALL applications
# (brew casks, Mac App Store apps, manually installed apps), removing the
# app together with every trace of its data (like AppCleaner, but scripted
# and origin-aware).
#
# Safety model — nothing is ever deleted without:
#   1. a full manifest of every path that will be touched (with sizes)
#   2. an explicit confirmation, then a typed "yes"
#   3. deletion goes to the Trash (recoverable) unless --permanent
#   4. every path is checked against a hard allowlist/denylist first
#
# Usage:
#   app-zap.sh              # pick installed apps → preview → confirm → Trash
#   app-zap.sh --orphans    # find leftover data of apps no longer installed
#   app-zap.sh --dry-run    # stop after showing the manifest
#   app-zap.sh --permanent  # rm -rf instead of Trash (still double-confirmed)

set -euo pipefail

BLUE='\033[1;34m' GREEN='\033[1;32m' YELLOW='\033[1;33m' RED='\033[1;31m' DIM='\033[2m' RESET='\033[0m'

NIX_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOMEBREW_NIX="$NIX_REPO/modules/homebrew.nix"

DRY_RUN=false
PERMANENT=false
ORPHANS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true ;;
    --permanent) PERMANENT=true ;;
    --orphans)   ORPHANS=true ;;
    -h|--help)   sed -n '2,/^set -/{ /^set -/d; s/^# \{0,2\}//; p }' "$0"; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

# ── User-data locations swept for app data (also the Trash allowlist) ───────
USER_DATA_DIRS=(
  "$HOME/Library/Application Support"
  "$HOME/Library/Caches"
  "$HOME/Library/Preferences"
  "$HOME/Library/Containers"
  "$HOME/Library/Group Containers"
  "$HOME/Library/Saved Application State"
  "$HOME/Library/Logs"
  "$HOME/Library/LaunchAgents"
  "$HOME/Library/WebKit"
  "$HOME/Library/HTTPStorages"
  "$HOME/Library/Cookies"
)

# System-level locations (/Library/{Application Support,LaunchAgents,
# LaunchDaemons,Preferences}, see sweep_system_data) are listed in the
# manifest but NEVER deleted by this script — root-owned, manual sudo only.

# ── Safety guard ─────────────────────────────────────────────────────────────
# A path may only be trashed if it survives BOTH the denylist and the
# allowlist. Anything else is refused loudly.
is_safe_path() {
  local p="$1"
  [[ "$p" == /* ]] || return 1          # absolute only
  case "$p" in *..*|*$'\n'*) return 1 ;; esac
  # Hard denials: roots, home itself, documents, this repo
  case "$p" in
    "/"|"/Applications"|"/Library"|"$HOME"|"$HOME/"|"$HOME/Applications"|"$HOME/Library")           return 1 ;;
    "$HOME/Documents"|"$HOME/Documents/"*)  return 1 ;;
    "$NIX_REPO"|"$NIX_REPO/"*)              return 1 ;;
  esac
  # Allowlist: app bundles + the swept user-data dirs
  case "$p" in
    "/Applications/"?*|"$HOME/Applications/"?*) return 0 ;;
  esac
  local d
  for d in "${USER_DATA_DIRS[@]}"; do
    case "$p" in "$d"|"$d/") return 1 ;; "$d/"?*) return 0 ;; esac
  done
  return 1
}

# ── Trash (default) or permanent removal ────────────────────────────────────
trash_path() {
  local p="$1"
  if ! is_safe_path "$p"; then
    echo -e "${RED}REFUSED (outside safety allowlist): $p${RESET}" >&2
    return 1
  fi
  [[ -e "$p" || -L "$p" ]] || return 0
  if $PERMANENT; then
    rm -rf "$p"
    return 0
  fi
  # Prefer Finder (proper Trash with Put Back); fall back to a plain move.
  if ! osascript -e 'on run argv' \
                 -e 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)' \
                 -e 'end run' "$p" >/dev/null 2>&1; then
    local base dest
    base="$(basename "$p")"
    dest="$HOME/.Trash/$base"
    [[ -e "$dest" ]] && dest="$HOME/.Trash/$base.$(date +%s).$RANDOM"
    mv "$p" "$dest"
  fi
}

human_size() {  # bytes-in-KB → human
  local kb="$1"
  if   [[ "$kb" -ge 1048576 ]]; then awk -v k="$kb" 'BEGIN{printf "%.1fG", k/1048576}'
  elif [[ "$kb" -ge 1024   ]]; then awk -v k="$kb" 'BEGIN{printf "%.1fM", k/1024}'
  else echo "${kb}K"; fi
}

path_kb() {
  local kb
  kb="$(du -sk "$1" 2>/dev/null | awk '{print $1}')"
  echo "${kb:-0}"
}

bundle_id_of() {  # <path/to/App.app> → bundle id or empty
  local app="$1" bid=""
  bid="$(mdls -name kMDItemCFBundleIdentifier -raw "$app" 2>/dev/null || true)"
  [[ "$bid" == "(null)" ]] && bid=""
  if [[ -z "$bid" && -f "$app/Contents/Info.plist" ]]; then
    bid="$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" 2>/dev/null || true)"
  fi
  echo "$bid"
}

# ── Data sweep: every path plausibly belonging to <bundle-id, app-name> ─────
# Matching is deliberately conservative: exact bundle-id (or bundle-id.*
# for flat files) and exact app-name directory matches only.
sweep_user_data() {
  local bid="$1" name="$2" e
  local -a cands=(
    "$HOME/Library/Application Support/$name"
    "$HOME/Library/Caches/$name"
    "$HOME/Library/Logs/$name"
  )
  if [[ -n "$bid" ]]; then
    cands+=(
      "$HOME/Library/Application Support/$bid"
      "$HOME/Library/Caches/$bid"
      "$HOME/Library/Containers/$bid"
      "$HOME/Library/Logs/$bid"
      "$HOME/Library/WebKit/$bid"
      "$HOME/Library/HTTPStorages/$bid"
      "$HOME/Library/HTTPStorages/$bid.binarycookies"
      "$HOME/Library/Cookies/$bid.binarycookies"
      "$HOME/Library/Saved Application State/$bid.savedState"
      "$HOME/Library/Preferences/$bid.plist"
    )
    # Globbed families: extra prefs, launch agents, group containers
    # ("<TEAMID>.<bid>" / "group.<bid>"). Unmatched globs stay literal
    # and are filtered by the -e test below.
    for e in "$HOME/Library/Preferences/$bid".*.plist \
             "$HOME/Library/LaunchAgents/$bid"*.plist \
             "$HOME/Library/Group Containers/"*".$bid" \
             "$HOME/Library/Group Containers/group.$bid"*; do
      cands+=("$e")
    done
  fi
  for e in "${cands[@]}"; do
    [[ -e "$e" || -L "$e" ]] && echo "$e"
  done
  return 0
}

sweep_system_data() {  # report-only
  local bid="$1" name="$2" e
  local -a cands=( "/Library/Application Support/$name" )
  if [[ -n "$bid" ]]; then
    cands+=( "/Library/Application Support/$bid" )
    for e in "/Library/LaunchAgents/$bid"*.plist \
             "/Library/LaunchDaemons/$bid"*.plist \
             "/Library/Preferences/$bid"*.plist; do
      cands+=("$e")
    done
  fi
  for e in "${cands[@]}"; do
    [[ -e "$e" ]] && echo "$e"
  done
  return 0
}

# ── Final confirmation gate (shared by both modes) ──────────────────────────
confirm_or_abort() {
  local n_items="$1" n_apps="$2" verb ans
  verb="moved to Trash"; $PERMANENT && verb="PERMANENTLY deleted (rm -rf)"
  echo ""
  $PERMANENT && echo -e "${RED}⚠ --permanent: there is NO undo.${RESET}"
  read -rp "$(printf "Proceed? %s item(s) across %s selection(s) will be %s. [y/N] " "$n_items" "$n_apps" "$verb")" ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted — nothing was touched."; exit 0; }
  read -rp "Final check — type 'yes' to continue: " ans
  [[ "$ans" == "yes" ]] || { echo "Aborted — nothing was touched."; exit 0; }
}

# ═════════════════════════════════════════════════════════════════════════════
#  MODE: --orphans — data whose app is gone
# ═════════════════════════════════════════════════════════════════════════════
if $ORPHANS; then
  echo -e "${BLUE}Building index of installed apps...${RESET}"
  installed_keys="$(mktemp)"
  trap 'rm -f "$installed_keys"' EXIT

  # key = first 3 dot-components of the bundle id (so helper/child ids like
  # com.foo.app.helper still match their parent app com.foo.app)
  key_of() { echo "$1" | cut -d. -f1-3; }

  while IFS= read -r app; do
    bid="$(bundle_id_of "$app")"
    [[ -n "$bid" ]] && key_of "$bid"
  done < <(find /Applications "$HOME/Applications" /System/Applications \
             -maxdepth 3 -name "*.app" -prune 2>/dev/null) | sort -u > "$installed_keys"

  echo -e "${BLUE}Scanning ~/Library for orphaned app data...${RESET}"
  candidates=()
  for dir in "${USER_DATA_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r entry; do
      base="$(basename "$entry")"
      # normalize to a bundle-id-ish key
      cand="$base"
      cand="${cand%.plist}"; cand="${cand%.savedState}"; cand="${cand%.binarycookies}"
      cand="${cand#group.}"
      # strip a leading 10-char team id ("ABCDE12345.com.foo.bar")
      first="${cand%%.*}"
      if [[ "${#first}" -eq 10 && "$first" =~ ^[A-Z0-9]+$ ]]; then cand="${cand#*.}"; fi
      # must look like reverse-DNS (≥3 components), never Apple's
      [[ "$cand" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9._-]+$ ]] || continue
      case "$cand" in com.apple.*) continue ;; esac
      grep -qxF "$(key_of "$cand")" "$installed_keys" && continue
      kb="$(path_kb "$entry")"
      candidates+=("$(printf '%s\t%s' "$entry" "$(human_size "$kb")")")
    done < <(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null)
  done

  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo -e "${GREEN}No orphaned app data found.${RESET}"; exit 0
  fi

  echo -e "${DIM}Tab to select, Enter to confirm, Esc to cancel${RESET}"
  selected="$(printf '%s\n' "${candidates[@]}" | sort | fzf \
    --multi --delimiter='\t' \
    --with-nth=1,2 \
    --header="Orphaned data (no matching installed app). Tab=toggle, Enter=review" \
    --border=rounded --height=80% --prompt="Orphans › " --marker="✓")" \
    || { echo "Cancelled."; exit 0; }

  paths=()
  while IFS=$'\t' read -r p _; do [[ -n "$p" ]] && paths+=("$p"); done <<< "$selected"
  [[ ${#paths[@]} -gt 0 ]] || { echo "Nothing selected."; exit 0; }

  echo -e "\n${BLUE}Will remove:${RESET}"
  total_kb=0
  for p in "${paths[@]}"; do
    kb="$(path_kb "$p")"; total_kb=$((total_kb + kb))
    printf '  %8s  %s\n' "$(human_size "$kb")" "$p"
  done
  echo -e "  ${DIM}total: $(human_size "$total_kb")${RESET}"

  $DRY_RUN && { echo -e "\n${YELLOW}--dry-run: stopping here.${RESET}"; exit 0; }
  confirm_or_abort "${#paths[@]}" "${#paths[@]}"
  for p in "${paths[@]}"; do trash_path "$p" && echo -e "${GREEN}✓${RESET} $p"; done
  echo -e "\n${GREEN}Done.${RESET} $($PERMANENT || echo 'Everything is in the Trash — recoverable until you empty it.')"
  exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
#  MODE: default — pick installed apps and zap them (app + all data)
# ═════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}Enumerating installed applications...${RESET}"

# brew cask token → its .app artifact names ("token<TAB>App Name.app")
brew_map="$(mktemp)"; trap 'rm -f "$brew_map"' EXIT
if command -v brew >/dev/null; then
  # shellcheck disable=SC2046  # cask tokens never contain whitespace
  brew info --cask --json=v2 $(brew list --cask 2>/dev/null) 2>/dev/null \
    | jq -r '.casks[] as $c | $c.artifacts[]? | select(.app) | .app[]
             | (if type=="string" then . else .target end)
             | "\($c.token)\t\(.)"' > "$brew_map" 2>/dev/null || true
fi

entries=()   # "<kind>\t<app-path>\t<token-or-id>\t<display>"
while IFS= read -r app; do
  base="$(basename "$app")"
  token="$(awk -F'\t' -v a="$base" '$2 == a {print $1; exit}' "$brew_map")"
  if [[ -n "$token" ]]; then
    kind="brew"; extra="$token"; label="[brew]   ${base%.app}  ${DIM}($token)${RESET}"
  elif [[ -e "$app/Contents/_MASReceipt/receipt" ]]; then
    kind="mas"; extra="-"; label="[mas]    ${base%.app}"
  else
    kind="manual"; extra="-"; label="[manual] ${base%.app}"
  fi
  entries+=("$(printf '%s\t%s\t%s\t%s' "$kind" "$app" "$extra" "$label")")
done < <(find /Applications "$HOME/Applications" -maxdepth 2 -name "*.app" -prune 2>/dev/null | sort)

[[ ${#entries[@]} -eq 0 ]] && { echo "No applications found."; exit 0; }

echo -e "${DIM}Tab to select, Enter to review (nothing is deleted yet), Esc to cancel${RESET}"
selected="$(printf '%s\n' "${entries[@]}" | fzf --ansi \
  --multi --delimiter='\t' --with-nth=4 \
  --header="Select apps to ZAP (app + ALL its data). Tab=toggle, Enter=review" \
  --border=rounded --height=80% --prompt="Zap › " --marker="✓" \
  --preview='echo "Path: {2}"; du -sh {2} 2>/dev/null | cut -f1 | sed "s/^/Size: /"' \
  --preview-window=down:3)" \
  || { echo "Cancelled."; exit 0; }

# ── Build the deletion manifest ──────────────────────────────────────────────
sel_kinds=(); sel_apps=(); sel_tokens=(); sel_names=(); sel_bids=()
while IFS=$'\t' read -r kind app token _; do
  [[ -n "$app" ]] || continue
  sel_kinds+=("$kind"); sel_apps+=("$app"); sel_tokens+=("$token")
  sel_names+=("$(basename "$app" .app)")
  sel_bids+=("$(bundle_id_of "$app")")
done <<< "$selected"
[[ ${#sel_apps[@]} -gt 0 ]] || { echo "Nothing selected."; exit 0; }

all_user_paths=()   # "<index>\t<path>" — user-deletable
all_sys_paths=()    # report-only
total_kb=0

echo ""
for i in "${!sel_apps[@]}"; do
  app="${sel_apps[$i]}"; name="${sel_names[$i]}"; bid="${sel_bids[$i]}"; kind="${sel_kinds[$i]}"
  echo -e "${BLUE}── $name ${DIM}[$kind]${RESET}${BLUE} ──${RESET}"
  [[ -n "$bid" ]] && echo -e "   ${DIM}bundle id: $bid${RESET}" \
                  || echo -e "   ${YELLOW}bundle id not readable — only exact-name data matches below${RESET}"
  if pgrep -qif "$app" 2>/dev/null; then
    echo -e "   ${YELLOW}⚠ appears to be running — quit it before zapping${RESET}"
  fi

  kb="$(path_kb "$app")"; total_kb=$((total_kb + kb))
  printf '   %8s  %s\n' "$(human_size "$kb")" "$app"
  all_user_paths+=("$(printf '%s\t%s' "$i" "$app")")

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    kb="$(path_kb "$p")"; total_kb=$((total_kb + kb))
    printf '   %8s  %s\n' "$(human_size "$kb")" "$p"
    all_user_paths+=("$(printf '%s\t%s' "$i" "$p")")
  done < <(sweep_user_data "$bid" "$name")

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    kb="$(path_kb "$p")"
    printf '   %8s  %s  ' "$(human_size "$kb")" "$p"
    echo -e "${YELLOW}(root-owned — not removed by this script)${RESET}"
    all_sys_paths+=("$p")
  done < <(sweep_system_data "$bid" "$name")
  echo ""
done

echo -e "${BLUE}Total to remove: $(human_size "$total_kb") across ${#all_user_paths[@]} path(s) for ${#sel_apps[@]} app(s)${RESET}"
if [[ ${#all_sys_paths[@]} -gt 0 ]]; then
  echo -e "${YELLOW}Note: ${#all_sys_paths[@]} system path(s) listed above are NOT removed by this script.${RESET}"
fi

$DRY_RUN && { echo -e "\n${YELLOW}--dry-run: stopping here. Nothing was touched.${RESET}"; exit 0; }
confirm_or_abort "${#all_user_paths[@]}" "${#sel_apps[@]}"

# ── Execute ──────────────────────────────────────────────────────────────────
brew_removed_tokens=()
for i in "${!sel_apps[@]}"; do
  app="${sel_apps[$i]}"; name="${sel_names[$i]}"; kind="${sel_kinds[$i]}"; token="${sel_tokens[$i]}"
  echo -e "\n${BLUE}Zapping $name...${RESET}"

  if [[ "$kind" == "brew" ]]; then
    # Let brew run the maintained zap stanza first, then sweep residue.
    brew uninstall --cask --zap --force "$token"
    brew_removed_tokens+=("$token")
  fi

  # Trash the app bundle (if still present) and every swept data path.
  for entry in "${all_user_paths[@]}"; do
    idx="${entry%%$'\t'*}"; p="${entry#*$'\t'}"
    [[ "$idx" == "$i" ]] || continue
    if [[ -e "$p" || -L "$p" ]]; then
      trash_path "$p" && echo -e "  ${GREEN}✓${RESET} $p"
    fi
  done

  [[ "$kind" == "mas" ]] && echo -e "  ${DIM}Note: the App Store will still list $name as purchased.${RESET}"
done

# ── Keep the nix config in sync (brew apps only) ────────────────────────────
for token in "${brew_removed_tokens[@]:-}"; do
  [[ -n "$token" ]] || continue
  line_no="$(grep -n "\"$token\"" "$HOMEBREW_NIX" | head -1 | cut -d: -f1 || true)"
  if [[ -n "$line_no" ]]; then
    echo ""
    echo -e "${YELLOW}$token is still declared in modules/homebrew.nix:${line_no}${RESET}"
    echo -e "  ${DIM}$(sed -n "${line_no}p" "$HOMEBREW_NIX")${RESET}"
    echo -e "  If left in place, the next rebuild will REINSTALL it."
    read -rp "Remove that line from homebrew.nix now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      sed -i.appzap-bak "${line_no}d" "$HOMEBREW_NIX" && rm -f "$HOMEBREW_NIX.appzap-bak"
      echo -e "${GREEN}Removed.${RESET} Review with: git -C $NIX_REPO diff modules/homebrew.nix"
    else
      echo -e "${DIM}Left in place — remember to remove it before the next rebuild.${RESET}"
    fi
  fi
done

echo ""
if $PERMANENT; then
  echo -e "${GREEN}Done. Items were permanently deleted.${RESET}"
else
  echo -e "${GREEN}Done. Everything is in the Trash — recoverable until you empty it.${RESET}"
fi
