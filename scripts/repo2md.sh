#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# repo2md.sh — Flatten a repo into LLM-friendly markdown
#
# Usage:
#   ./repo2md.sh [directory] [output_file]
#
# Defaults:
#   directory   = .
#   output_file = repo_context.md
# ─────────────────────────────────────────────────────────────

TARGET_DIR="${1:-.}"
OUTPUT_FILE="${2:-repo_context.md}"

# ── Ignore patterns ──────────────────────────────────────────
# Directory names to prune entirely
PRUNE_DIRS=(
  .git
  .hg
  .svn
  .direnv
  node_modules
  .next
  .nuxt
  dist
  build
  .turbo
  __pycache__
  .venv
  venv
  .env
  .mypy_cache
  .ruff_cache
  .pytest_cache
  .tox
  '*.egg-info'
  target
  vendor
  .vscode
  .idea
  .terraform
  .cache
  .parcel-cache
  coverage
  .nyc_output
  .DS_Store
  result
)

# File names to skip (exact match)
SKIP_FILES=(
  .gitignore
  .gitmodules
  .gitattributes
  .dockerignore
  Thumbs.db
  .DS_Store
)

# File globs to skip (extension-based)
SKIP_GLOBS=(
  '*.pyc' '*.pyo' '*.pyd'
  '*.min.js' '*.min.css' '*.map'
  '*.lock'
  'package-lock.json' 'yarn.lock' 'pnpm-lock.yaml' 'bun.lockb'
  'uv.lock' 'poetry.lock' 'Cargo.lock'
  # Binary / media
  '*.png' '*.jpg' '*.jpeg' '*.gif' '*.ico' '*.svg' '*.webp' '*.avif'
  '*.mp3' '*.mp4' '*.wav' '*.ogg' '*.webm' '*.flac'
  '*.pdf' '*.zip' '*.tar' '*.gz' '*.bz2' '*.xz' '*.7z' '*.rar'
  '*.bin' '*.exe' '*.dll' '*.so' '*.dylib' '*.a'
  '*.woff' '*.woff2' '*.ttf' '*.eot' '*.otf'
  '*.sqlite' '*.db' '*.sqlite3'
  '*.o' '*.obj' '*.class' '*.jar' '*.war'
  '*.iso' '*.img' '*.dmg'
)

# ── Helpers ──────────────────────────────────────────────────

collect_files() {
  local find_args=( "$TARGET_DIR" )

  # Prune directories entirely from search tree
  if [ ${#PRUNE_DIRS[@]} -gt 0 ]; then
    find_args+=( \( )
    local first=true
    for d in "${PRUNE_DIRS[@]}"; do
      if $first; then
        find_args+=( -name "$d" )
        first=false
      else
        find_args+=( -o -name "$d" )
      fi
    done
    find_args+=( \) -prune -o )
  fi

  # Match regular files
  find_args+=( -type f )

  # Exclude specific file names
  for f in "${SKIP_FILES[@]}"; do
    find_args+=( ! -name "$f" )
  done

  # Exclude specific extensions
  for g in "${SKIP_GLOBS[@]}"; do
    find_args+=( ! -name "$g" )
  done

  # Robustly ignore the output file and the script itself using their inodes
  if [[ -f "$0" ]]; then
    find_args+=( ! -samefile "$0" )
  fi
  if [[ -f "$OUTPUT_FILE" ]]; then
    find_args+=( ! -samefile "$OUTPUT_FILE" )
  fi

  find_args+=( -print )

  find "${find_args[@]}" 2>/dev/null | sort
}

to_rel_path() {
  local path="$1"
  # Edge case: if we are targeting exactly a single file
  if [[ "$path" == "$TARGET_DIR" ]]; then
    echo "$(basename "$path")"
    return
  fi
  # Strip target dir prefixes and normalize
  path="${path#"$TARGET_DIR/"}"
  path="${path#"$TARGET_DIR"}"
  path="${path#./}"
  path="${path#/}"
  echo "$path"
}

ext_to_lang() {
  local base ext
  base="$(basename "$1")"
  ext="${base##*.}"

  # Extensionless / dotfiles
  if [[ "$base" == "$ext" || "$base" == .* ]]; then
    case "$base" in
      Makefile|makefile|GNUmakefile) echo "makefile" ;;
      Dockerfile*)                  echo "dockerfile" ;;
      Justfile|justfile)            echo "justfile" ;;
      Containerfile)                echo "dockerfile" ;;
      Vagrantfile)                  echo "ruby" ;;
      Rakefile|Gemfile)             echo "ruby" ;;
      .bashrc|.bash_profile|.profile) echo "bash" ;;
      .zshrc|.zprofile|.zshenv)     echo "zsh" ;;
      flake.lock)                   echo "json" ;;
      *)                            echo "" ;;
    esac
    return
  fi

  case "$ext" in
    sh|bash)        echo "bash" ;;
    zsh)            echo "zsh" ;;
    fish)           echo "fish" ;;
    py)             echo "python" ;;
    rs)             echo "rust" ;;
    go)             echo "go" ;;
    js|mjs|cjs)     echo "javascript" ;;
    ts|mts|cts)     echo "typescript" ;;
    jsx)            echo "jsx" ;;
    tsx)            echo "tsx" ;;
    rb)             echo "ruby" ;;
    java)           echo "java" ;;
    kt|kts)         echo "kotlin" ;;
    c|h)            echo "c" ;;
    cpp|cc|cxx|hpp) echo "cpp" ;;
    cs)             echo "csharp" ;;
    swift)          echo "swift" ;;
    lua)            echo "lua" ;;
    zig)            echo "zig" ;;
    nix)            echo "nix" ;;
    ex|exs)         echo "elixir" ;;
    erl|hrl)        echo "erlang" ;;
    hs)             echo "haskell" ;;
    ml|mli)         echo "ocaml" ;;
    clj|cljs|cljc)  echo "clojure" ;;
    r|R)            echo "r" ;;
    sql)            echo "sql" ;;
    html|htm)       echo "html" ;;
    css)            echo "css" ;;
    scss|sass)      echo "scss" ;;
    less)           echo "less" ;;
    xml|xsl|xsd)    echo "xml" ;;
    json)           echo "json" ;;
    jsonc|json5)    echo "jsonc" ;;
    yaml|yml)       echo "yaml" ;;
    toml)           echo "toml" ;;
    ini|cfg)        echo "ini" ;;
    conf|cnf)       echo "conf" ;;
    md|mdx)         echo "markdown" ;;
    rst)            echo "rst" ;;
    tex|latex)      echo "latex" ;;
    proto)          echo "protobuf" ;;
    graphql|gql)    echo "graphql" ;;
    tf|tfvars)      echo "hcl" ;;
    vim)            echo "vim" ;;
    el)             echo "elisp" ;;
    cmake)          echo "cmake" ;;
    ps1)            echo "powershell" ;;
    dockerfile)     echo "dockerfile" ;;
    *)              echo "" ;;
  esac
}

is_binary() {
  # Use file(1) mime check (portable across Linux/macOS)
  if command -v file &>/dev/null; then
    file -b --mime-type "$1" 2>/dev/null | grep -qvE 'text|json|xml|javascript|empty'
  else
    # Mac/BSD fallback to identify null bytes
    LC_ALL=C grep -q -m 1 -a $'\0' "$1" 2>/dev/null
  fi
}

# ── Main ─────────────────────────────────────────────────────
main() {
  local files=()
  # Use a while read loop instead of `mapfile` to ensure macOS Bash 3.2 compatibility
  while IFS= read -r line; do
    [[ -n "$line" ]] && files+=("$line")
  done < <(collect_files)

  local file_count=${#files[@]}

  if (( file_count == 0 )); then
    echo "No files found in '$TARGET_DIR' after filtering." >&2
    exit 1
  fi

  echo "Collecting $file_count files from '$TARGET_DIR' → $OUTPUT_FILE" >&2

  {
    echo "# Repository Context"
    echo ""

    # ── Tree ───────────────────────────────────────────────
    echo "## Directory Structure"
    echo ""
    echo '```text'
    if command -v python3 >/dev/null 2>&1; then
      for f in "${files[@]}"; do
        to_rel_path "$f"
      done | python3 -c "
import sys
tree = {}
for line in sys.stdin:
    parts = [p for p in line.strip().split('/') if p]
    node = tree
    for part in parts:
        node = node.setdefault(part, {})
def render(node, prefix=''):
    items = list(node.items())
    for i, (name, subtree) in enumerate(items):
        is_last = (i == len(items) - 1)
        print(f\"{prefix}{'└── ' if is_last else '├── '}{name}\")
        render(subtree, prefix + ('    ' if is_last else '│   '))
print('.')
render(tree)
" 2>/dev/null || {
        # Python crash fallback 
        echo "."
        for f in "${files[@]}"; do
          echo "  $(to_rel_path "$f")"
        done
      }
    else
      # Pure bash fallback (if Python isn't installed)
      echo "."
      for f in "${files[@]}"; do
        echo "  $(to_rel_path "$f")"
      done
    fi
    echo '```'
    echo ""

    # ── File contents ──────────────────────────────────────
    echo "## File Contents"
    echo ""

    for f in "${files[@]}"; do
      local rel_path lang size
      rel_path="$(to_rel_path "$f")"
      lang="$(ext_to_lang "$f")"

      echo "### \`$rel_path\`"
      echo ""

      if is_binary "$f"; then
        echo "*Binary file — skipped*"
      else
        size=$(wc -c < "$f" 2>/dev/null || echo 0)

        # Skip very large files (>500KB)
        if (( size > 512000 )); then
          echo "*File too large ($(( size / 1024 ))KB) — skipped*"
        else
          echo "\`\`\`${lang}"
          cat "$f"
          # Ensure closing fence is on its own line
          [[ -z "$(tail -c 1 "$f" 2>/dev/null)" ]] || echo ""
          echo '```'
        fi
      fi
      echo ""
    done

  } > "$OUTPUT_FILE"

  local out_size
  out_size=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
  echo "Done! $OUTPUT_FILE ($(( out_size / 1024 ))KB)" >&2
}

main