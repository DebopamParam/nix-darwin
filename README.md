# nix-darwin

A fully declarative macOS configuration for an Apple Silicon MacBook. One `darwin-rebuild switch` reproduces the entire environment — system packages, GUI apps, shell, prompt, editor configs, git, tmux, Claude Code profiles, and macOS system settings — from this repo.

## Aim

Keep a Mac reproducible, version-controlled, and disposable.

- **Reproducible** — every package, cask, and macOS preference lives in a `.nix` file. New machine = `darwin-rebuild switch --flake ~/.config/nix-darwin` and you're back.
- **Version-controlled** — every change to the system goes through git. Roll back a bad upgrade with `darwin-rebuild --switch-generation`.
- **Disposable** — `homebrew.cleanup = "zap"` enforces "if it's not in the flake, it gets removed." No drift between what's installed and what's declared.
- **Multi-profile Claude Code** — split work and personal Claude accounts cleanly (different auth, shared plugins) so that conversations and credentials never bleed across contexts.

## Architecture

```
flake.nix                    Inputs + host wiring
│
├── nixpkgs (unstable)       Package set
├── nix-darwin               macOS system module system
├── home-manager             Per-user dotfiles & user packages
├── nix-homebrew             Declarative Homebrew (taps/brews/casks/MAS)
└── brew-src (pinned HEAD)   Workaround for brew 5.1.7 cask-JSON parser crash

modules/
├── system.nix               Aggregator → system/*
│   └── system/
│       ├── packages.nix     CLI tools available to all users (ripgrep, fd, jq, …)
│       ├── nix.nix          Nix daemon settings (Determinate-managed, so disabled here)
│       ├── users.nix        Primary user, Touch-ID-for-sudo
│       └── defaults.nix     macOS preferences (Dock, Finder, trackpad, key repeat, …)
│
├── homebrew.nix             Brews, casks, Mac App Store apps. cleanup = "zap"
│
└── home.nix                 Aggregator → home/*
    └── home/
        ├── packages.nix     User-only packages (currently empty)
        ├── shell.nix        Zsh + Starship + fzf + bat + zoxide + carapace + aliases
        ├── git.nix          git + delta (side-by-side diffs)
        ├── tmux.nix         vi-mode, mouse, custom split/resize keymap
        ├── direnv.nix       direnv + nix-direnv
        └── claude-profiles.nix
                             Builds ~/.claude-personal & ~/.claude-work that
                             symlink the shared plugins/settings, and installs
                             a `claude-personal` / `claude-work` shell wrapper
                             that blocks bare `claude`.

modules/claude/              Claude Code config tracked in this repo
├── settings.json            Shared settings
├── statusline.sh            Custom statusline
├── ccstatusline-settings.json
├── plugins/plugins.toml     Pinned plugins
├── personal/CLAUDE.md       Personal-profile instructions
└── work/CLAUDE.md           Work-profile instructions

scripts/                     Operational helpers (see "Scripts" section)
notes/                       Long-form docs (e.g. notes/homebrew.md)
```

### Layering, top to bottom

1. **Determinate Nix** owns the daemon (`nix.enable = false` in `system/nix.nix`).
2. **nix-darwin** owns system packages, services, and macOS defaults.
3. **nix-homebrew** owns GUI apps (Nix can't fully manage `.app` bundles on macOS) and a few brew-only CLIs (`rtk`, `opencode`).
4. **home-manager** owns the per-user shell, prompt, git, tmux, and editor config.

The split exists because each layer is good at one thing: nix-darwin handles `launchd` and system prefs, Homebrew handles signed `.app` bundles, home-manager handles dotfiles without sudo.

## Host configuration

All per-machine values (username, hostname, git identity, ngrok domain) live in **`private.nix`** at the repo root. Every module reads from there via `specialArgs`, so you only edit one file per machine:

```nix
{
  username = "yourusername";
  hostname = "Your-MacBook-Pro";
  system   = "aarch64-darwin";
  git = { name = "Your Name"; email = "you@example.com"; };
  ngrokDomain = "";
}
```

### Setting up a new machine

`private.nix.example` is the canonical template — it lists every field with comments. On a fresh clone:

```bash
cp private.nix.example private.nix
git update-index --skip-worktree private.nix
$EDITOR private.nix              # fill in real values
rebuild
```

### Privacy & local edits (important if forking)

`private.nix` *has* to be tracked by git — Nix flakes refuse to read untracked files. To keep your real values out of the public history, the file is committed with **placeholder values** and marked `skip-worktree` after you copy from the example.

`skip-worktree` makes git pretend the file is unmodified — your edits won't show up in `git status`, won't be picked up by `git add -A`, and won't be pushed. Nix still reads the working-tree version, so `darwin-rebuild` sees your real values.

To temporarily un-skip (e.g. to update the placeholder template that ships in the repo):

```bash
git update-index --no-skip-worktree private.nix
# edit, commit, push
git update-index --skip-worktree private.nix
```

## Common commands

```bash
# Apply config (the `rebuild` alias defined in shell.nix)
rebuild
# = sudo darwin-rebuild switch --flake ~/.config/nix-darwin

# Update flake inputs (all)
nix flake update

# Update only one input — interactive picker
my-nix-update         # → scripts/update-select.sh

# Roll back to the previous generation
darwin-rebuild --rollback

# List generations
darwin-rebuild --list-generations
```

## Terminal shortcuts

### Shell aliases (`modules/home/shell.nix`)

| Alias | Expands to |
|---|---|
| `..` / `...` | `cd ..` / `cd ../..` |
| `ls` / `ll` / `lt` | `eza` (icons) / `eza -la --git` / `eza --tree --level=2` |
| `cat` | `bat` (syntax-highlighted) |
| `g` `gs` `gc` `gp` `gd` `gl` | `git` / `status` / `commit` / `push` / `diff` / `log --oneline --graph --decorate -20` |
| `lg` | `lazygit` |
| `rebuild` | `sudo darwin-rebuild switch --flake ~/.config/nix-darwin` |
| `sync-claude` | dump live Claude config back into the repo |
| `apply-claude` | apply repo's Claude config to live `~/.claude` |
| `llmctx` | `repo2md.sh` — dump current repo as markdown for LLM context |
| `start-venv` | `source .venv/bin/activate` |
| `my-machine-clean` | `machine-clean.sh` — disk cleanup |
| `my-nix-update` | `update-select.sh` — selective flake input updater |
| `sshp` | `ssh-pick` — fzf SSH host picker (parses `~/.ssh/config`) |
| `tmux-pick` | fzf tmux session picker |

### Shell functions

- `tunnel-port <port>` — bring up an ngrok HTTPS tunnel on the reserved free domain
- `ssh-pick` — fuzzy-pick from `~/.ssh/config`, with a preview pane showing resolved `hostname/user/port/identityfile`
- `claude-personal` / `claude-work` — launch Claude Code with the right `CLAUDE_CONFIG_DIR`. Bare `claude` is blocked by a shell function so you can't accidentally write to the wrong profile.

### Tmux (`modules/home/tmux.nix`)

Prefix is the default `C-b`. Mouse + vi-mode are on.

| Binding | Action |
|---|---|
| `C-b C-S-Right` | Split pane vertically (in current pane's path) |
| `C-b C-S-Down` | Split pane horizontally |
| `C-b C-S-Up` | New window (in current pane's path) |
| `C-b S-Left` / `S-Right` | Move current window left / right |
| `C-b M-Up/Down/Left/Right` | Resize pane by 5 cells (repeatable, no prefix re-press) |
| copy-mode `v` | Begin selection (vi style) |
| copy-mode `y` | Copy + cancel (uses macOS clipboard via `set-clipboard on`) |

### Starship prompt highlights

- Full path, never truncated, even inside git repos
- ❄️ symbol when inside a `nix shell` / `nix develop`
- Green `➜` on success, red `✗` on failure

### macOS system defaults (`modules/system/defaults.nix`)

Applied on every rebuild. Key ones worth knowing:

- Dock: bottom, no auto-hide, 48 px tiles, no recents, no MRU spaces, minimize-to-app
- Finder: hidden files visible, path bar + status bar shown, **column view** by default, search current folder
- Global: dark mode, `InitialKeyRepeat = 68` and `KeyRepeat = 6` (very fast), no auto-capitalize / auto-correct / auto-period
- Trackpad: tap-to-click, two-finger right-click, three-finger drag
- Screenshots saved to `~/Pictures/Screenshots` as PNG
- 24-hour menu-bar clock

### Touch ID for sudo

Enabled in `modules/system/users.nix` via `security.pam.services.sudo_local.touchIdAuth = true`. Survives macOS upgrades because nix-darwin re-applies it on every rebuild.

## Scripts (`scripts/`)

| Script | What it does |
|---|---|
| `machine-clean.sh` | Safe macOS cleanup across Nix store, Homebrew, Docker/OrbStack, npm, uv/pip, Xcode. Always prunes stopped containers + dangling images + unused networks; uses fzf to optionally also prune build cache, volumes, and unused images. `--deep` for aggressive mode. |
| `update-select.sh` | Interactive picker over flake inputs — update only the ones you choose, instead of `nix flake update`-everything. |
| `bootstrap-claude-plugins.sh` | Installs Claude Code plugins listed in `modules/claude/plugins/plugins.toml`. |
| `setup-claude-profiles.sh` | Idempotent setup for the `personal` / `work` profile dirs. |
| `sync-claude-config.sh` | Two-way sync: pulls live `~/.claude` config into the repo (default) or applies the repo's config to live (`--apply`). |
| `setup-bash.sh` | Bash environment bootstrap (parity with the zsh setup, for systems that won't run zsh). |
| `repo2md.sh` | Dump the current repo as a single markdown file you can paste into an LLM. Used via the `llmctx` alias. |

## Claude Code profiles

The non-obvious bit. `modules/home/claude-profiles.nix` does three things on every rebuild:

1. Creates `~/.claude/plugins`, `~/.claude-personal/`, `~/.claude-work/` if missing.
2. Symlinks `~/.claude/plugins`, `~/.claude/settings.json`, `~/.claude/CLAUDE.md` into each profile dir, so plugins and shared settings stay in sync.
3. Writes `~/.config/claude-profiles/init.sh`, sourced by zsh, that:
   - Defines `claude-personal` / `claude-work` aliases that set `CLAUDE_CONFIG_DIR` before launching `claude`.
   - Replaces bare `claude` with a shell function that prints an error so you can't accidentally use the wrong account.

Auth tokens and session history live under `~/.claude-{personal,work}/` and are intentionally **not** symlinked — that's what keeps the accounts separate.

## Caveats

- **`mac-app-util` is disabled** (`flake.nix` lines 18–23) due to an SBCL/fare-quasiquote build failure on nixpkgs-unstable. Re-enable when upstream is fixed; until then Spotlight may not index Nix-installed `.app` bundles.
- **`brew-src` is pinned to upstream HEAD** to work around a parser crash in the version (5.1.7) bundled with `nix-homebrew`. Drop the override once nix-homebrew bumps the pin.
- **`homebrew.cleanup = "zap"`** is unforgiving — anything not declared in `modules/homebrew.nix` will be removed on the next rebuild. If you're migrating an existing Mac, run with `cleanup = "none"` first, audit `brew list` and `brew list --cask`, add everything you want to keep, *then* flip to `"zap"`.
- **Determinate Nix manages the daemon** (`nix.enable = false`). If you switch to the upstream installer, flip that back to `true`.
