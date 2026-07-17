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
        └── ai-profiles.nix
                             Installs ~/.config/ai-profiles/{profile-sync.sh,
                             init.sh}: generic `claude-use` / `codex-use`
                             launchers (+ `*-ls`) that sync a profile home to
                             the canonical config before launch, and block bare
                             `claude` / `codex`.

modules/claude/              Canonical Claude config tracked in this repo
├── settings.json            Shared settings (model, rtk hook, statusline)
├── statusline.sh            Custom statusline
├── ccstatusline-settings.json
├── CLAUDE.md                Shared instructions
└── RTK.md

modules/codex/               Canonical Codex config tracked in this repo
└── config.toml

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
| `sync-ai` | dump live Claude + Codex config back into the repo |
| `apply-ai` | apply repo's Claude + Codex config to live `~/.claude` & `~/.codex` |
| `llmctx` | `repo2md.sh` — dump current repo as markdown for LLM context |
| `start-venv` | `source .venv/bin/activate` |
| `my-machine-clean` | `clean.sh` — unified cleanup menu: `apps` (remove apps + all their data), `orphans` (leftover data of deleted apps), `system` / `deep` (nix GC, brew, Docker, dev caches) |
| `my-nix-update` | `update-select.sh` — selective flake input updater |
| `sshp` | `ssh-pick` — fzf SSH host picker (parses `~/.ssh/config`) |
| `tmux-pick` | fzf tmux session picker |

### Shell functions

- `tunnel-port <port>` — bring up an ngrok HTTPS tunnel on the reserved free domain. `tunnel-port --cf <subdomain> <port>` instead exposes the port at `<subdomain>.<cfDomain>` via a per-subdomain Cloudflare Tunnel (created on first use, takes over on rerun); add `-v` for per-request debug logs
- `ssh-pick` — fuzzy-pick from `~/.ssh/config`, with a preview pane showing resolved `hostname/user/port/identityfile`
- `claude-use <profile>` / `codex-use <profile>` — launch Claude Code / Codex under `~/.claude-<profile>` / `~/.codex-<profile>`, syncing the profile to the canonical config first. `claude-ls` / `codex-ls` list existing profiles. Bare `claude` / `codex` are blocked by shell functions so you can't accidentally write to the wrong account.

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
| `clean.sh` | Unified entry point for all manual cleanup (the `my-machine-clean` alias). Interactive menu or direct: `apps` / `orphans` → `app-zap.sh`, `system` / `deep` → `machine-clean.sh`. |
| `machine-clean.sh` | Safe macOS cleanup across Nix store, Homebrew, Docker/OrbStack, npm, uv/pip, Xcode. Always prunes stopped containers + dangling images + unused networks; uses fzf to optionally also prune build cache, volumes, and unused images. `--deep` for aggressive mode. |
| `app-zap.sh` | Interactive app remover covering **all** apps (brew casks, Mac App Store, manual installs). fzf multi-select → full deletion manifest (app + every data path, with sizes) → double confirmation → moved to Trash (recoverable; `--permanent` to rm). Brew apps are zapped via `brew uninstall --zap` and the matching `homebrew.nix` line is offered for removal so the next rebuild doesn't reinstall. `--orphans` mode finds leftover `~/Library` data of apps that are already gone. `--dry-run` previews without touching anything. |
| `update-select.sh` | Interactive picker over flake inputs — update only the ones you choose, instead of `nix flake update`-everything. |
| `setup-ai-profiles.sh` | Bash mirror of `ai-profiles.nix` for non-nix machines (Linux containers): installs the `claude-use` / `codex-use` launchers into `~/.config/ai-profiles` and wires `~/.bashrc`. |
| `sync-ai-config.sh` | Two-way sync of the canonical `~/.claude` & `~/.codex` config into the repo (default) or out to live (`--apply`). |
| `setup-bash.sh` | Bash environment bootstrap (parity with the zsh setup, for systems that won't run zsh). |
| `repo2md.sh` | Dump the current repo as a single markdown file you can paste into an LLM. Used via the `llmctx` alias. |

## Claude & Codex profiles

The non-obvious bit — a unified profile model for both tools.

Each tool has **one canonical home** holding *all* non-auth config:

- `~/.claude` (settings, `CLAUDE.md`, agents, commands, hooks, plugins, session state…)
- `~/.codex` (`config.toml`, …)

A **profile home** (`~/.claude-<profile>`, `~/.codex-<profile>`) only selects an
account. In it, **every non-auth entry is a symlink back to canonical**; only the
auth files stay real — that's what keeps accounts separate:

- Claude: `.claude.json`, `.credentials.json`
- Codex: `auth.json`

`modules/home/ai-profiles.nix` installs two files under `~/.config/ai-profiles/`:

1. `profile-sync.sh` — the sync engine: on each launch it promotes any genuinely
   new non-auth profile entry up into canonical, then relinks everything (existing
   non-auth entries are discarded and replaced with fresh symlinks — no backups).
2. `init.sh` (sourced by zsh) — defines `claude-use <profile>` / `codex-use <profile>`
   (which sync, then launch with `CLAUDE_CONFIG_DIR` / `CODEX_HOME` set),
   `claude-ls` / `codex-ls`, and shell functions that block bare `claude` / `codex`.

Add a new account by just launching a new profile and logging in once:
`claude-use <anything>`. There are no hardcoded profile names.

## Caveats

- **`mac-app-util` is disabled** (`flake.nix` lines 18–23) due to an SBCL/fare-quasiquote build failure on nixpkgs-unstable. Re-enable when upstream is fixed; until then Spotlight may not index Nix-installed `.app` bundles.
- **`brew-src` is pinned to upstream HEAD** to work around a parser crash in the version (5.1.7) bundled with `nix-homebrew`. Drop the override once nix-homebrew bumps the pin.
- **`homebrew.cleanup = "zap"`** is unforgiving — anything not declared in `modules/homebrew.nix` will be removed on the next rebuild. If you're migrating an existing Mac, run with `cleanup = "none"` first, audit `brew list` and `brew list --cask`, add everything you want to keep, *then* flip to `"zap"`.
- **Determinate Nix manages the daemon** (`nix.enable = false`). If you switch to the upstream installer, flip that back to `true`.
