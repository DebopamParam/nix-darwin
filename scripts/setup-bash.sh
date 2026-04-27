#!/usr/bin/env bash
# remote-setup.sh — lightweight dev environment for Ubuntu/Debian VMs
#
# Usage:
#   ./remote-setup.sh [--dry-run] [--yes] [--user NAME] [--email EMAIL]
#
#   --yes         skip interactive selector, install all minimal defaults
#   --user NAME   git user.name  (default: DebopamChowdhury)
#   --email EMAIL git user.email (default: debopamwork@gmail.com)
#   --dry-run     print what would happen, touch nothing
#   -h|--help     show this message

set -euo pipefail

GIT_NAME="DebopamChowdhury"
GIT_EMAIL="debopamwork@gmail.com"
DRY_RUN=false
YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --yes)     YES=true ;;
    --user)    GIT_NAME="$2";  shift ;;
    --email)   GIT_EMAIL="$2"; shift ;;
    -h|--help) sed -n '2,/^set -/{ /^set -/d; s/^# \{0,2\}//; p }' "$0"; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "\033[1;34m==>\033[0m $*"; }
ok()   { echo -e "\033[1;32m  ✓\033[0m $*"; }
warn() { echo -e "\033[1;33m  !\033[0m $*"; }
run()  { $DRY_RUN && { echo "  [dry-run] $*"; return; }; "$@"; }
have() { command -v "$1" &>/dev/null; }

apt_get() { run sudo apt-get "$@"; }

arch() { uname -m; }

# ── Component catalogue ───────────────────────────────────────────────────────
# Each entry: "key|label|description"
# Minimal = pre-selected in the fzf picker
# Extras  = unselected by default

MINIMAL_COMPONENTS=(
  "tmux|tmux|terminal multiplexer + config"
  "git-config|git-config|git settings, global .gitignore"
  "shell|shell-aliases|bash aliases, bashrc.d, navigation shortcuts"
  "fzf|fzf|fuzzy finder (Ctrl-R history, tmux-pick, ~4MB)"
  "jq|jq|JSON processor"
  "htop|htop|interactive process viewer"
)

EXTRA_COMPONENTS=(
  "bat|bat|cat with syntax highlighting (~6MB)"
  "eza|eza|modern ls replacement (~7MB)"
  "ripgrep|ripgrep|fast grep replacement, rg (~5MB)"
  "delta|delta|beautiful git diffs pager (~5MB)"
  "zoxide|zoxide|smarter cd with frecency (~4MB)"
  "starship|starship|minimal cross-shell prompt (~8MB)"
  "lazygit|lazygit|terminal git UI (~15MB)"
  "gh|gh|GitHub CLI"
  "uv|uv|fast Python package manager (~10MB)"
  "docker|docker|Docker Engine + CLI"
)

key_of()   { echo "${1%%|*}"; }
label_of() { echo "${1#*|}"; echo "${1}" | cut -d'|' -f2; }
desc_of()  { echo "${1##*|}"; }

# ── Bootstrap fzf (needed for the selector itself) ────────────────────────────
bootstrap_fzf() {
  have fzf && return
  log "Bootstrapping fzf for the selector..."
  apt_get update -qq
  apt_get install -y --no-install-recommends fzf
}

# ── Interactive selector ──────────────────────────────────────────────────────
#
# Two-step fzf:
#   1. Minimal items — all pre-selected, Tab to deselect
#   2. Extras        — all unselected,    Tab to add
#
run_selector() {
  local minimal_keys=() extra_keys=()

  # Step 1: minimal items, all pre-selected
  local minimal_lines=()
  for c in "${MINIMAL_COMPONENTS[@]}"; do
    minimal_lines+=("$(key_of "$c")  $(desc_of "$c")")
  done

  local chosen_minimal
  chosen_minimal=$(
    printf '%s\n' "${minimal_lines[@]}" |
      fzf --multi \
          --bind 'start:select-all' \
          --prompt 'Minimal setup › ' \
          --header $'Tab = toggle  •  Enter = confirm\nMinimal defaults — deselect anything you don'"'"'t want' \
          --height=60% --border=rounded \
          --color='header:italic:blue' \
    || true
  )

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    minimal_keys+=("${line%% *}")
  done <<< "$chosen_minimal"

  # Step 2: extras, all unselected
  local extra_lines=()
  for c in "${EXTRA_COMPONENTS[@]}"; do
    extra_lines+=("$(key_of "$c")  $(desc_of "$c")")
  done

  local chosen_extras
  chosen_extras=$(
    printf '%s\n' "${extra_lines[@]}" |
      fzf --multi \
          --prompt 'Extras › ' \
          --header $'Tab = toggle  •  Enter = confirm  •  Esc = skip all extras' \
          --height=60% --border=rounded \
          --color='header:italic:yellow' \
          --expect=esc \
    || true
  )

  # First line from --expect is the key that was pressed
  local first_line
  first_line=$(echo "$chosen_extras" | head -1)
  if [[ "$first_line" != "esc" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      extra_keys+=("${line%% *}")
    done <<< "$(echo "$chosen_extras" | tail -n +2)"
  fi

  SELECTED_KEYS=("${minimal_keys[@]}" "${extra_keys[@]+"${extra_keys[@]}"}")
}

# ── Default selection (--yes) ─────────────────────────────────────────────────
default_selection() {
  SELECTED_KEYS=()
  for c in "${MINIMAL_COMPONENTS[@]}"; do
    SELECTED_KEYS+=("$(key_of "$c")")
  done
}

selected() {
  local key="$1"
  for k in "${SELECTED_KEYS[@]+"${SELECTED_KEYS[@]}"}"; do
    [[ "$k" == "$key" ]] && return 0
  done
  return 1
}

# ── Installers ────────────────────────────────────────────────────────────────

install_tmux() {
  log "Installing tmux..."
  apt_get install -y --no-install-recommends tmux
  log "Writing ~/.tmux.conf..."
  $DRY_RUN && { echo "  [dry-run] would write ~/.tmux.conf"; return; }
  cat > "$HOME/.tmux.conf" <<'EOF'
set -g default-terminal "screen-256color"
set -s escape-time 0
set -g mouse on
set -g history-limit 50000
set -g display-time 4000
set -g status-interval 5
set -g focus-events on
setw -g mode-keys vi
set -s set-clipboard on
set -g assume-paste-time 50

set -g prefix C-b
bind C-a send-prefix

bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind-key C-S-Right split-window -h -c "#{pane_current_path}"
bind-key C-S-Down  split-window -v -c "#{pane_current_path}"
bind-key C-S-Up    new-window   -c "#{pane_current_path}"

bind-key S-Left  swap-window -t -1 \; select-window -t -1
bind-key S-Right swap-window -t +1 \; select-window -t +1

bind-key -r M-Up    resize-pane -U 5
bind-key -r M-Down  resize-pane -D 5
bind-key -r M-Left  resize-pane -L 5
bind-key -r M-Right resize-pane -R 5

bind-key -T copy-mode-vi v send-keys -X begin-selection
bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel

set -g status-style "bg=colour235,fg=colour136"
set -g status-left  "[#S] "
set -g status-right " %H:%M %d-%b"
set -g window-status-current-style "bold,fg=colour166"

bind r source-file ~/.tmux.conf \; display "Reloaded!"
EOF
  ok "tmux installed and configured"
}

install_git_config() {
  log "Configuring git..."
  run git config --global user.name  "$GIT_NAME"
  run git config --global user.email "$GIT_EMAIL"
  run git config --global init.defaultBranch main
  run git config --global push.autoSetupRemote true
  run git config --global pull.rebase true
  run git config --global rerere.enabled true
  run git config --global core.excludesfile "$HOME/.gitignore_global"
  if ! $DRY_RUN; then
    cat > "$HOME/.gitignore_global" <<'EOF'
.DS_Store
*.swp
.direnv
.envrc
node_modules
.idea
.vscode
EOF
  fi
  ok "git configured"
}

install_shell() {
  log "Writing ~/.bashrc.d/devenv.sh..."
  $DRY_RUN && { echo "  [dry-run] would write ~/.bashrc.d/devenv.sh"; return; }
  mkdir -p "$HOME/.bashrc.d"
  cat > "$HOME/.bashrc.d/devenv.sh" <<'BASHRC'
export PATH="$HOME/.local/bin:$PATH"

alias ..='cd ..'
alias ...='cd ../..'
alias mkdir='mkdir -p'

if command -v eza &>/dev/null; then
  alias ls='eza --icons'
  alias ll='eza -la --icons --git'
  alias lt='eza --tree --icons --level=2'
else
  alias ls='ls --color=auto'
  alias ll='ls -lahF --color=auto'
  alias lt='tree -L 2 2>/dev/null || find . -maxdepth 2 | sort'
fi

if command -v bat &>/dev/null; then
  alias cat='bat --paging=never'
fi

alias g='git'
alias gs='git status'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate -20'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias ga='git add'

if command -v fzf &>/dev/null; then
  # Ctrl-R fuzzy history
  for _fzf_kb in \
      /usr/share/doc/fzf/examples/key-bindings.bash \
      /usr/share/fzf/key-bindings.bash; do
    [[ -f "$_fzf_kb" ]] && source "$_fzf_kb" && break
  done
  unset _fzf_kb
  alias tmux-pick='tmux attach -t $(tmux ls 2>/dev/null | fzf --prompt="Session › " | cut -d: -f1)'
fi

alias start-venv='source .venv/bin/activate'

if command -v zoxide &>/dev/null; then
  eval "$(zoxide init bash)"
fi

if command -v starship &>/dev/null; then
  eval "$(starship init bash)"
fi
BASHRC

  local marker="# remote-setup: devenv"
  if ! grep -qF "$marker" "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" <<EOF

$marker
for _f in "\$HOME/.bashrc.d/"*.sh; do [[ -r "\$_f" ]] && source "\$_f"; done
unset _f
EOF
    ok "~/.bashrc updated"
  else
    ok "~/.bashrc already set up"
  fi
}

install_fzf() {
  have fzf && { ok "fzf already installed"; return; }
  log "Installing fzf..."
  apt_get install -y --no-install-recommends fzf
  ok "fzf installed"
}

install_jq() {
  log "Installing jq..."
  apt_get install -y --no-install-recommends jq
  ok "jq installed"
}

install_htop() {
  log "Installing htop..."
  apt_get install -y --no-install-recommends htop
  ok "htop installed"
}

install_bat() {
  log "Installing bat..."
  apt_get install -y --no-install-recommends bat
  # Debian/Ubuntu ships it as batcat
  if have batcat && ! have bat; then
    mkdir -p "$HOME/.local/bin"
    run ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
    ok "bat → batcat shim created"
  fi
  ok "bat installed"
}

install_eza() {
  log "Installing eza..."
  # eza is in Ubuntu 24.04+ repos; fall back to GitHub release otherwise
  if apt_get install -y --no-install-recommends eza 2>/dev/null; then
    ok "eza installed (apt)"
    return
  fi
  warn "eza not in apt, installing from GitHub release..."
  local url
  case "$(arch)" in
    x86_64)  url="https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz" ;;
    aarch64) url="https://github.com/eza-community/eza/releases/latest/download/eza_aarch64-unknown-linux-gnu.tar.gz" ;;
    *)       warn "eza: unsupported arch $(arch), skipping"; return ;;
  esac
  local tmp; tmp=$(mktemp -d)
  run curl -fsSL "$url" | tar -xz -C "$tmp"
  run mkdir -p "$HOME/.local/bin"
  run mv "$tmp/eza" "$HOME/.local/bin/eza"
  rm -rf "$tmp"
  ok "eza installed (~/.local/bin/eza)"
}

install_ripgrep() {
  log "Installing ripgrep (rg)..."
  apt_get install -y --no-install-recommends ripgrep
  ok "ripgrep installed"
}

install_delta() {
  log "Installing delta (git diff pager)..."
  local url
  case "$(arch)" in
    x86_64)  url="https://github.com/dandavison/delta/releases/latest/download/git-delta_0.18.2_amd64.deb" ;;
    aarch64) url="https://github.com/dandavison/delta/releases/latest/download/git-delta_0.18.2_arm64.deb" ;;
    *)       warn "delta: unsupported arch $(arch), skipping"; return ;;
  esac
  local tmp; tmp=$(mktemp /tmp/delta.XXXXXX.deb)
  run curl -fsSL "$url" -o "$tmp"
  run sudo dpkg -i "$tmp"
  rm -f "$tmp"
  # Wire into git
  run git config --global core.pager delta
  run git config --global interactive.diffFilter "delta --color-only"
  run git config --global delta.navigate true
  run git config --global delta.side-by-side true
  run git config --global delta.line-numbers true
  ok "delta installed and wired into git"
}

install_zoxide() {
  log "Installing zoxide..."
  run bash -c "$(curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh)"
  ok "zoxide installed"
}

install_starship() {
  log "Installing starship..."
  run bash -c "$(curl -fsSL https://starship.rs/install.sh)" -- --yes
  local scfg="${XDG_CONFIG_HOME:-$HOME/.config}/starship/starship.toml"
  if [[ ! -f "$scfg" ]] && ! $DRY_RUN; then
    mkdir -p "$(dirname "$scfg")"
    cat > "$scfg" <<'EOF'
add_newline = true

[character]
success_symbol = "[➜](bold green)"
error_symbol   = "[✗](bold red)"

[directory]
truncation_length = 0
truncate_to_repo  = false
home_symbol       = "~"

[git_branch]
symbol = " "
EOF
    ok "starship config written"
  fi
  ok "starship installed"
}

install_lazygit() {
  log "Installing lazygit..."
  local url
  case "$(arch)" in
    x86_64)  url="https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_Linux_x86_64.tar.gz" ;;
    aarch64) url="https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_Linux_arm64.tar.gz" ;;
    *)       warn "lazygit: unsupported arch $(arch), skipping"; return ;;
  esac
  local tmp; tmp=$(mktemp -d)
  run curl -fsSL "$url" | tar -xz -C "$tmp"
  run mkdir -p "$HOME/.local/bin"
  run mv "$tmp/lazygit" "$HOME/.local/bin/lazygit"
  rm -rf "$tmp"
  ok "lazygit installed (~/.local/bin/lazygit)"
}

install_gh() {
  log "Installing GitHub CLI (gh)..."
  run curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | run sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  run sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | run sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  apt_get update -qq
  apt_get install -y --no-install-recommends gh
  ok "gh installed"
}

install_uv() {
  log "Installing uv (Python package manager)..."
  run bash -c "$(curl -fsSL https://astral.sh/uv/install.sh)"
  ok "uv installed"
}

install_docker() {
  log "Installing Docker Engine..."
  run sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
  apt_get install -y --no-install-recommends ca-certificates curl gnupg lsb-release
  run sudo mkdir -p /etc/apt/keyrings
  run curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | run sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | run sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt_get update -qq
  apt_get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  run sudo usermod -aG docker "$USER"
  ok "Docker installed (log out and back in for group to apply)"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
dispatch() {
  local key="$1"
  case "$key" in
    tmux)       install_tmux ;;
    git-config) install_git_config ;;
    shell)      install_shell ;;
    fzf)        install_fzf ;;
    jq)         install_jq ;;
    htop)       install_htop ;;
    bat)        install_bat ;;
    eza)        install_eza ;;
    ripgrep)    install_ripgrep ;;
    delta)      install_delta ;;
    zoxide)     install_zoxide ;;
    starship)   install_starship ;;
    lazygit)    install_lazygit ;;
    gh)         install_gh ;;
    uv)         install_uv ;;
    docker)     install_docker ;;
    *) warn "unknown component: $key" ;;
  esac
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "\033[1;32m── Done ─────────────────────────────────────────────────\033[0m"
  echo "  Installed: ${SELECTED_KEYS[*]+"${SELECTED_KEYS[*]}"}"
  echo ""
  echo "  Reload shell :  source ~/.bashrc"
  echo "  Start tmux   :  tmux new -s main"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  # Always need apt up-to-date and curl/wget available
  log "Updating apt cache..."
  apt_get update -qq
  apt_get install -y --no-install-recommends curl wget git > /dev/null

  if $YES; then
    default_selection
  else
    bootstrap_fzf
    run_selector
  fi

  if [[ ${#SELECTED_KEYS[@]+"${#SELECTED_KEYS[@]}"} -eq 0 ]]; then
    warn "Nothing selected, exiting."
    exit 0
  fi

  echo ""
  log "Installing: ${SELECTED_KEYS[*]}"
  echo ""

  for key in "${SELECTED_KEYS[@]}"; do
    dispatch "$key"
  done

  # If delta was installed, wire it into git even if git-config wasn't selected
  if selected delta && ! selected git-config; then
    run git config --global core.pager delta
  fi

  print_summary
}

main
