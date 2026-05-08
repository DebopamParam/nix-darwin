#!/usr/bin/env bash
# Pick & install Claude Code plugins declared in modules/claude/plugins/plugins.toml.
# Uses fzf for multi-select. Idempotent — already-installed plugins are filtered out.
#
# Usage:
#   scripts/bootstrap-claude-plugins.sh            # interactive picker
#   scripts/bootstrap-claude-plugins.sh --all      # install everything not already installed
#   scripts/bootstrap-claude-plugins.sh --list     # just print the manifest entries

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO/modules/claude/plugins/plugins.toml"

GREEN='\033[1;32m' BLUE='\033[1;34m' YELLOW='\033[1;33m' DIM='\033[2m' RESET='\033[0m'

[[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }

MODE="pick"
case "${1:-}" in
  --all)  MODE="all" ;;
  --list) MODE="list" ;;
  -h|--help)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

# ── Resolve CLAUDE_CONFIG_DIR for a profile ──────────────────────
# The claude-personal/claude-work helpers are shell aliases that just set
# CLAUDE_CONFIG_DIR before invoking `claude`. We replicate that here so the
# script works in non-interactive shells (and on Linux VMs without aliases).
config_dir_for_profile() {
  case "$1" in
    personal) echo "$HOME/.claude-personal" ;;
    work)     echo "$HOME/.claude-work" ;;
    default|"") echo "" ;;  # use claude's default
    *)        echo "$HOME/.claude-$1" ;;
  esac
}

# Run `claude` with the profile's CLAUDE_CONFIG_DIR set.
run_claude() {
  local profile="$1"; shift
  local cdir; cdir="$(config_dir_for_profile "$profile")"
  if [[ -n "$cdir" ]]; then
    CLAUDE_CONFIG_DIR="$cdir" claude "$@"
  else
    claude "$@"
  fi
}

# Stable label for cache keys / messages.
cli_label() {
  local profile="$1"
  if [[ "$profile" == "default" || -z "$profile" ]]; then echo "claude"
  else echo "claude($profile)"
  fi
}

# ── TOML parser (only handles the flat schema we use) ────────────
# Emits, on stdout, one record per blank-line-separated [[section]] block:
#   <section>|<key>=<value>;<key>=<value>;...
parse_manifest() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[\[([a-z]+)\]\]/ {
      if (section) print section "|" rec
      match($0, /\[\[([a-z]+)\]\]/, m); section = m[1]; rec = ""; next
    }
    /^[[:space:]]*[a-z_]+[[:space:]]*=/ {
      key = $1
      sub(/^[[:space:]]*/, "", key); sub(/[[:space:]]*$/, "", key)
      val = $0; sub(/^[^=]*=[[:space:]]*/, "", val)
      sub(/[[:space:]]*$/, "", val)
      gsub(/^"|"$/, "", val)
      rec = rec (rec ? ";" : "") key "=" val
    }
    END { if (section) print section "|" rec }
  ' "$MANIFEST"
}

# Pull a key out of a "k=v;k=v" record.
field() {
  local rec="$1" key="$2"
  awk -v rec="$rec" -v key="$key" 'BEGIN{
    n = split(rec, a, ";")
    for (i=1; i<=n; i++) {
      eq = index(a[i], "=")
      if (substr(a[i], 1, eq-1) == key) { print substr(a[i], eq+1); exit }
    }
  }'
}

# ── Collect manifest entries ─────────────────────────────────────
mapfile -t RECORDS < <(parse_manifest)

declare -a MARKETPLACES PLUGINS
for line in "${RECORDS[@]}"; do
  section="${line%%|*}"
  rec="${line#*|}"
  case "$section" in
    marketplace) MARKETPLACES+=("$rec") ;;
    plugin)      PLUGINS+=("$rec") ;;
  esac
done

if [[ "$MODE" == "list" ]]; then
  echo -e "${BLUE}Marketplaces:${RESET}"
  for m in "${MARKETPLACES[@]}"; do
    echo "  • $(field "$m" name) → $(field "$m" repo)"
  done
  echo -e "${BLUE}Plugins:${RESET}"
  for p in "${PLUGINS[@]}"; do
    echo "  • $(field "$p" name)@$(field "$p" marketplace) [scope=$(field "$p" scope), profile=$(field "$p" profile)]"
  done
  exit 0
fi

# Bail early if we can't find claude.
command -v claude >/dev/null 2>&1 || { echo "claude CLI not found in PATH" >&2; exit 1; }

# ── Cache installed-plugin lists per profile ─────────────────────
declare -A INSTALLED_CACHE
installed_for_profile() {
  local profile="$1"
  if [[ -z "${INSTALLED_CACHE[$profile]+x}" ]]; then
    INSTALLED_CACHE[$profile]="$(run_claude "$profile" plugin list --json 2>/dev/null \
      | grep -oE '"id":[[:space:]]*"[^"]+"' \
      | sed -E 's/.*"([^"]+)"$/\1/' | tr '\n' ' ')"
  fi
  echo "${INSTALLED_CACHE[$profile]}"
}

# ── Build selectable list: each line is a tab-delimited spec ──
declare -a SPECS=()
for p in "${PLUGINS[@]}"; do
  name=$(field "$p" name)
  market=$(field "$p" marketplace)
  scope=$(field "$p" scope)
  profile=$(field "$p" profile)
  label=$(cli_label "$profile")
  installed=$(installed_for_profile "$profile")
  if [[ " $installed " == *" $name@$market "* ]]; then
    echo -e "${DIM}already installed:${RESET} $name@$market via $label"
    continue
  fi
  display=$(printf "%-40s %-8s %-10s %s" "$name@$market" "$scope" "$profile" "(via $label)")
  SPECS+=("$display"$'\t'"$name|$market|$scope|$profile")
done

if [[ ${#SPECS[@]} -eq 0 ]]; then
  echo -e "${GREEN}Nothing to install — all manifest plugins already present.${RESET}"
  exit 0
fi

# ── Pick (or take all) ───────────────────────────────────────────
if [[ "$MODE" == "all" ]]; then
  CHOSEN=$(printf '%s\n' "${SPECS[@]}")
else
  command -v fzf >/dev/null 2>&1 || { echo "fzf not installed (try: brew/apt install fzf)" >&2; exit 1; }
  CHOSEN=$(printf '%s\n' "${SPECS[@]}" | fzf --multi \
    --with-nth=1 --delimiter=$'\t' \
    --prompt="Install plugins> " \
    --header="TAB to toggle, ENTER to confirm, ESC to cancel  |  name@market   scope     profile    cli")
fi

if [[ -z "$CHOSEN" ]]; then
  echo "Nothing selected."
  exit 0
fi

# ── For each chosen entry: ensure marketplace, then install ─────
declare -A MARKET_REPO
for m in "${MARKETPLACES[@]}"; do
  MARKET_REPO[$(field "$m" name)]=$(field "$m" repo)
done

declare -A MARKET_ADDED  # key: profile|market
ensure_marketplace() {
  local profile="$1" market="$2"
  local key="$profile|$market"
  [[ -n "${MARKET_ADDED[$key]:-}" ]] && return
  if run_claude "$profile" plugin marketplace list --json 2>/dev/null \
       | grep -oE '"name":[[:space:]]*"[^"]+"' \
       | grep -q "\"$market\""; then
    MARKET_ADDED[$key]=1; return
  fi
  local repo="${MARKET_REPO[$market]:-}"
  [[ -z "$repo" ]] && { echo "No repo defined for marketplace '$market' in manifest" >&2; return 1; }
  echo -e "${BLUE}+ $(cli_label "$profile") plugin marketplace add $repo${RESET}"
  run_claude "$profile" plugin marketplace add "$repo"
  MARKET_ADDED[$key]=1
}

while IFS=$'\t' read -r _display spec; do
  [[ -z "$spec" ]] && continue
  IFS='|' read -r name market scope profile <<< "$spec"
  ensure_marketplace "$profile" "$market"
  echo -e "${BLUE}+ $(cli_label "$profile") plugin install $name@$market --scope $scope${RESET}"
  run_claude "$profile" plugin install "$name@$market" --scope "$scope"
done <<< "$CHOSEN"

echo -e "${GREEN}Done.${RESET}"
