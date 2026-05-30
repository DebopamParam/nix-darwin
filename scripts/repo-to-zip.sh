#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# repo-to-zip.sh — Zip the current directory, honoring .gitignore
#
# Usage:
#   repo-to-zip [output.zip] [source_dir]
#
# Defaults:
#   output.zip = <dirname>.zip   (inside the directory itself)
#   source_dir = .
#
# Behavior:
#   - Inside a git repo: zips exactly the files git would track,
#     i.e. tracked files + untracked files that are NOT ignored
#     (respects .gitignore, nested .gitignore, and global excludes).
#   - Outside a git repo: falls back to zipping everything, while
#     still skipping a few obvious noise dirs (.git, node_modules).
# ─────────────────────────────────────────────────────────────

SOURCE_DIR="${2:-.}"

cd "$SOURCE_DIR"

DIR_NAME="$(basename "$(pwd)")"
OUTPUT="${1:-${DIR_NAME}.zip}"

# Resolve OUTPUT to an absolute path so `cd`-relative zipping is safe.
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT")" && pwd)"
OUTPUT="${OUTPUT_DIR}/$(basename "$OUTPUT")"

# Remove any stale archive so we never append to an old one.
rm -f "$OUTPUT"

command -v zip >/dev/null 2>&1 || {
  echo "error: 'zip' not found in PATH" >&2
  exit 1
}

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "→ git repo detected — honoring .gitignore"
  # --cached           : tracked files
  # --others           : untracked files
  # --exclude-standard : drop anything ignored by .gitignore/excludes
  # -z + xargs -0      : NUL-delimited to survive spaces/newlines in names
  git ls-files -z --cached --others --exclude-standard \
    | xargs -0 zip -q "$OUTPUT" --
else
  echo "→ not a git repo — zipping everything (skipping .git, node_modules)"
  zip -q -r "$OUTPUT" . \
    -x '*/.git/*' '.git/*' '*/node_modules/*' 'node_modules/*' "$(basename "$OUTPUT")"
fi

COUNT="$(unzip -l "$OUTPUT" | tail -1 | awk '{print $2}')"
SIZE="$(du -h "$OUTPUT" | cut -f1)"
echo "✓ created ${OUTPUT} (${COUNT} files, ${SIZE})"
