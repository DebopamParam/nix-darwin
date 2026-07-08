#!/usr/bin/env bash
# clean.sh — single entry point for all manual cleanup on this machine.
# Dispatches to app-zap.sh (uninstall apps + their data) and
# machine-clean.sh (garbage from things you keep: nix store, brew,
# Docker/OrbStack, dev caches).
#
# Usage (aliased to `my-machine-clean`):
#   my-machine-clean                # interactive menu
#   my-machine-clean apps [flags]   # pick apps to remove with all their data
#                                   #   flags pass through: --dry-run --permanent
#   my-machine-clean orphans        # leftover ~/Library data of apps already gone
#   my-machine-clean system         # nix GC, brew, Docker, npm/uv/pip/Xcode caches
#   my-machine-clean deep           # same, aggressive (machine-clean.sh --deep)

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mode="${1:-}"
[[ $# -gt 0 ]] && shift

if [[ -z "$mode" ]]; then
  choice="$(printf '%s\n' \
    "apps     Remove selected apps + ALL their data (brew/mas/manual)" \
    "orphans  Find & remove leftover data of apps already deleted" \
    "system   Reclaim space: nix store GC, brew, Docker, dev caches" \
    "deep     Aggressive system clean (full nix GC, greedy prunes)" \
    | fzf --header="What do you want to clean? (Esc to cancel)" \
          --border=rounded --height=40% --prompt="Clean › " \
          --preview-window=hidden)" || { echo "Cancelled."; exit 0; }
  mode="${choice%% *}"
fi

case "$mode" in
  apps)    exec bash "$DIR/app-zap.sh" "$@" ;;
  orphans) exec bash "$DIR/app-zap.sh" --orphans "$@" ;;
  system)  exec bash "$DIR/machine-clean.sh" "$@" ;;
  deep)    exec bash "$DIR/machine-clean.sh" --deep "$@" ;;
  -h|--help) sed -n '2,/^set -/{ /^set -/d; s/^# \{0,2\}//; p }' "$0" ;;
  *) echo "Unknown mode: $mode (expected: apps | orphans | system | deep)" >&2; exit 1 ;;
esac
