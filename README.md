# nix-darwin

A reproducible macOS configuration for an Apple Silicon MacBook using
[Determinate Nix](https://determinate.systems/), nix-darwin, Home Manager, and
nix-homebrew.

The entire machine — system packages, GUI apps, shell, prompt, editor configs,
Git, tmux, Claude Code / Codex profiles, and macOS system preferences — is
described in `.nix` files in this repository. A single `darwin-rebuild switch`
evaluates that description and makes the running system match it.

A successful rebuild configures:

- system and command-line packages
- Homebrew applications
- Zsh, Starship, fzf, bat, zoxide, direnv, Git, and tmux
- Claude Code and Codex profiles
- macOS Dock, Finder, trackpad, keyboard, screenshot, and clock preferences

> [!WARNING]
> `homebrew.onActivation.cleanup = "zap"` is enabled. Homebrew packages and
> casks that are not declared in `modules/homebrew.nix` may be removed during a
> rebuild. Review that file before running this configuration on an existing Mac.

## Contents

- [How it works](#how-it-works)
  - [The core idea](#the-core-idea)
  - [Nix, flakes, and the store](#nix-flakes-and-the-store)
  - [The flake: one function that returns a system](#the-flake-one-function-that-returns-a-system)
  - [The four layers and how they compose](#the-four-layers-and-how-they-compose)
  - [`private.nix`: one file parameterizes everything](#privatenix-one-file-parameterizes-everything)
  - [The module system](#the-module-system)
  - [What `darwin-rebuild switch` actually does](#what-darwin-rebuild-switch-actually-does)
  - [Generations and rollback](#generations-and-rollback)
  - [Determinate Nix and `nix.enable = false`](#determinate-nix-and-nixenable--false)
  - [Home Manager: how dotfiles are generated](#home-manager-how-dotfiles-are-generated)
  - [nix-homebrew: declarative control over an imperative tool](#nix-homebrew-declarative-control-over-an-imperative-tool)
  - [The `brew-src` override](#the-brew-src-override)
  - [macOS defaults](#macos-defaults)
  - [The Claude Code / Codex profile model](#the-claude-code--codex-profile-model)
  - [Cleanup: deliberately imperative](#cleanup-deliberately-imperative)
  - [Tunnels](#tunnels)
- [What manages what?](#what-manages-what)
- [Fresh Mac installation](#fresh-mac-installation)
- [Quick installation checklist](#quick-installation-checklist)
- [Architecture](#architecture)
- [Host configuration and privacy](#host-configuration-and-privacy)
- [Common commands](#common-commands)
- [Useful shell commands](#useful-shell-commands)
- [Cleanup](#cleanup)
- [Tmux](#tmux)
- [macOS defaults](#macos-defaults-1)
- [Caveats](#caveats)

## How it works

This section explains the mechanics — the "how" and "why" behind the setup — so
that the rest of the document (installation steps, command reference) makes
sense as a whole rather than as a list of incantations.

### The core idea

The state of the machine is a **pure function of the files in this repository**.
You never install software by running `brew install` or clicking through a
`.dmg` and hoping you remember it later; you *declare* what should exist in a
`.nix` file and run one command. Three properties fall out of that:

- **Reproducible** — a new machine is `git clone` + one rebuild away from the
  same environment. There is no hidden state that only lives in your head or in
  a shell history.
- **Version-controlled** — every change to the system is a Git commit. You can
  diff, review, and revert system changes the same way you would application
  code.
- **Convergent, not additive** — a rebuild makes the system *match* the
  declaration, including removing things that are no longer declared
  (`homebrew.cleanup = "zap"` is the sharpest expression of this). There is no
  slow drift between "what I installed once" and "what is declared."

Everything below is machinery in service of that one idea.

### Nix, flakes, and the store

Nix is a build system and package manager built around a few concepts:

- **The Nix store (`/nix/store`)** holds every package, at an immutable path
  whose name includes a hash of *all* of its build inputs — for example
  `/nix/store/<hash>-ripgrep-14.1.0`. Because the hash covers inputs, two builds
  with identical inputs produce the identical store path, and different versions
  never collide. Nothing is installed "into the system" in the traditional
  sense; packages sit in the store and are made available through symlinks.
- **Derivations** are the pure build recipes that produce store paths. Nix
  evaluates your configuration into derivations, then *realises* (builds or
  downloads) them. Identical derivations are cached, which is why a second
  rebuild that changes nothing is nearly instant.
- **Flakes** are the packaging format this repo uses. A flake is a directory
  with a `flake.nix` that declares **inputs** (external dependencies, pinned by
  commit) and **outputs** (what it produces — here, a macOS system
  configuration). Flakes are *hermetic*: evaluation may only read files tracked
  by Git and the pinned inputs, never arbitrary ambient state.
- **`flake.lock`** pins every input to an exact commit hash. This is what makes
  "reproducible" literally true: the same repo at the same lock file evaluates
  to the same system, today or in a year. Inputs only move when you run
  `nix flake update` (or the selective `my-nix-update`), which rewrites the lock.

> Note: because flakes only see Git-tracked files, even machine-local files like
> `private.nix` must be tracked (see [Host configuration and
> privacy](#host-configuration-and-privacy)).

### The flake: one function that returns a system

`flake.nix` is the entry point. Conceptually it does three things:

1. **Declares inputs** — `nixpkgs` (the package set, tracking
   `nixpkgs-unstable`), `nix-darwin`, `home-manager`, `nix-homebrew`, and
   `brew-src`. The first four `follows = "nixpkgs"` so the whole tree evaluates
   against a single nixpkgs, avoiding duplicate package sets.

2. **Loads machine-specific values** — `private = import ./private.nix` reads
   your username, hostname, platform, Git identity, and tunnel domains into a
   plain attribute set.

3. **Builds the system** by calling `nix-darwin.lib.darwinSystem`:

   ```nix
   darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
     inherit system;
     specialArgs = { inherit inputs username hostname private; };
     modules = [
       ./modules/system.nix
       ./modules/homebrew.nix
       nix-homebrew.darwinModules.nix-homebrew
       { nix-homebrew = { enable = true; enableRosetta = true; user = username; autoMigrate = true; }; }
       home-manager.darwinModules.home-manager
       { home-manager = { useGlobalPkgs = true; useUserPackages = true; /* ... */ }; }
     ];
   };
   ```

`darwinSystem` is a function that takes a list of **modules** and merges them
into one big configuration, then produces a buildable system derivation as its
output. The output is named after your `hostname` — that is how
`darwin-rebuild` knows which configuration to build on this machine.

### The four layers and how they compose

The configuration is not one monolithic thing; it is four cooperating layers,
each responsible for a different slice of the system. They are all merged
together by `darwinSystem`:

| Layer | What it owns | How it applies |
|---|---|---|
| **Determinate Nix** | The Nix daemon, the store, the installer | Installed once, out of band; owns `/nix` and the daemon lifecycle |
| **nix-darwin** | System packages, macOS `defaults`, users, Touch ID, services | Merged as modules; activated system-wide |
| **nix-homebrew** | Homebrew itself, plus casks / brews / App Store apps | A nix-darwin module that drives `brew` declaratively |
| **Home Manager** | Per-user dotfiles: shell, prompt, Git, tmux, direnv, AI profiles | Runs as a nix-darwin module scoped to your user |

The important architectural point is that **Home Manager and nix-homebrew are
themselves nix-darwin modules**. `home-manager.darwinModules.home-manager` and
`nix-homebrew.darwinModules.nix-homebrew` plug the two subsystems into the same
module list, so a single `darwin-rebuild switch` activates all of them
atomically. There is no separate `home-manager switch` step.

Two nix-homebrew options are worth calling out:

- `autoMigrate = true` — on first activation, adopts an existing `/opt/homebrew`
  install rather than fighting it.
- `enableRosetta = true` — also manages the Intel Homebrew prefix under
  `/usr/local`, which is why [Rosetta](#6-install-rosetta) must be present before
  the first rebuild.

### `private.nix`: one file parameterizes everything

The whole configuration is generic; the only machine-specific inputs live in
`private.nix`. That set is passed to every module two ways:

- to nix-darwin modules via `specialArgs = { inherit inputs username hostname private; }`
- to Home Manager modules via `extraSpecialArgs = { inherit inputs private; }`

`specialArgs` injects values into the module system *before* evaluation, so any
module can accept `{ private, ... }` in its argument list and read
`private.git.email`, `private.cfDomain`, and so on. This is why porting the
config to a new machine means editing exactly one file — nothing else contains a
username, hostname, email, or domain.

### The module system

nix-darwin (like NixOS) uses a **module system**: each `.nix` file is a module
that contributes options and values, and the framework recursively merges them.
Two idioms in this repo:

- **Aggregators.** `modules/system.nix` and `modules/home.nix` contain almost no
  configuration; they just `imports = [ ./system/packages.nix ./system/nix.nix … ]`.
  This keeps each concern (packages, defaults, users, shell, git…) in its own
  small file while presenting a single import to the flake.
- **Merging.** When two modules set the same option, the module system merges
  them according to the option's type — lists concatenate, attribute sets deep-
  merge, and scalar values must not conflict. That is why `programs.zsh.enable`
  can appear in both `system/users.nix` and `home/shell.nix` without error.

Each module is a function `{ pkgs, lib, private, ... }: { … }`. The arguments it
names are supplied by the framework (from `pkgs`, `lib`) or by `specialArgs`
(like `private`); the trailing `...` ignores the rest.

### What `darwin-rebuild switch` actually does

A rebuild is four distinct phases:

1. **Evaluate.** Nix reads `flake.nix`, resolves inputs from `flake.lock`,
   evaluates all modules into a single attribute set, and reduces the whole
   thing to a **system derivation** — a build recipe for the entire system.
2. **Build / realise.** Nix builds or downloads every store path the derivation
   references. Already-built paths (unchanged since last time) are reused from
   the store or a binary cache, so only what actually changed is rebuilt.
3. **Create a generation.** The result is a new *system generation* — a complete
   snapshot of the system, added alongside previous ones rather than
   overwriting them.
4. **Activate.** nix-darwin switches the current-system symlink to the new
   generation and runs **activation scripts**: it writes macOS `defaults`,
   updates the launchd/user setup, reconciles Homebrew (installing declared
   casks, and *zapping* undeclared ones), and runs the Home Manager activation
   that materializes your dotfiles.

Because build happens before activation, a failed build never touches the
running system — activation only runs against something that built cleanly.

### Generations and rollback

Every successful switch produces a numbered, immutable generation. This gives
you time-travel over the whole system:

```bash
darwin-rebuild --list-generations      # see the history
darwin-rebuild --rollback              # step back to the previous generation
darwin-rebuild --switch-generation N   # jump to a specific one
```

A rollback is not a re-download or a reinstall — the old generation's store
paths still exist, so switching back is just repointing symlinks and re-running
that generation's activation. This is what makes a bad upgrade cheap to undo.
(Old generations are eventually reclaimed by the garbage collector; see
[Cleanup](#cleanup).)

### Determinate Nix and `nix.enable = false`

This config expects **Determinate Nix** to own the Nix installation — the
daemon, the store volume, and upgrades. To avoid two systems fighting over the
same daemon, `modules/system/nix.nix` sets:

```nix
nix.enable = false;
```

This tells nix-darwin *not* to manage `nix.conf` or the daemon; Determinate does
that instead. This line is intentional and must stay. `nix.nix` also sets
`system.stateVersion` (the nix-darwin state baseline) and
`nixpkgs.hostPlatform` (the target platform, `aarch64-darwin`).

### Home Manager: how dotfiles are generated

Home Manager manages your user environment. It has two complementary
mechanisms:

- **`programs.<tool>`** — high-level modules that *generate* a tool's config
  from Nix options. For example `programs.git.settings`, `programs.starship.settings`,
  and `programs.tmux.extraConfig` are rendered into real config files by Home
  Manager; you never hand-edit `~/.gitconfig` or `~/.tmux.conf`. `programs.zsh`
  even assembles `~/.zshrc` / `~/.zprofile` from `shellAliases`,
  `initContent`, `profileExtra`, and plugin definitions.
- **`home.file."<path>"`** — for anything without a dedicated module, you write
  the file content (or point at a source) directly. This repo uses it for
  Ghostty's `~/.config/ghostty/config` and for the AI-profile scripts under
  `~/.config/ai-profiles/`.

In both cases the generated file lands in the Nix store and Home Manager places
a **symlink** from your home directory into that store path. Your dotfiles are
therefore read-only pointers into an immutable, versioned artifact — editing
them means editing the `.nix` source and rebuilding, not editing in place. When
a pre-existing real file would be overwritten, `backupFileExtension = "backup"`
moves it aside to `<name>.backup` instead of failing the activation, which is
what makes adopting an already-configured machine safe.

### nix-homebrew: declarative control over an imperative tool

macOS GUI apps and a few CLIs are distributed as Homebrew casks/formulae, not as
nixpkgs packages. Homebrew is fundamentally imperative, so `nix-homebrew` wraps
it to make it behave declaratively:

- `modules/homebrew.nix` lists the desired `brews`, `casks`, and `masApps`.
- On activation, nix-homebrew reconciles reality against that list.
- `onActivation.cleanup = "zap"` makes the reconciliation **subtractive**:
  anything installed but *not* declared is uninstalled, and its data removed per
  the cask's zap stanza. This is the Homebrew equivalent of the "convergent, not
  additive" principle — the file is the single source of truth, so you add a
  cask *before* installing it, never ad-hoc.
- `onActivation.autoUpdate = true` refreshes brew metadata each activation
  (current, but slower / less reproducible); `upgrade = false` means declared
  packages are not force-upgraded on every rebuild.

Under the hood nix-homebrew symlinks Homebrew's own source tree and its `Taps`
directory into the Nix store, so `/opt/homebrew/Library/Taps` is **read-only**.
A consequence: this config relies on Homebrew's JSON API for cask/formula
definitions rather than cloning tap repos, because it cannot write into a
store-managed Taps directory. See `notes/homebrew.md` for the full details and
anti-patterns.

### The `brew-src` override

`flake.nix` overrides the Homebrew version that nix-homebrew ships with:

```nix
nix-homebrew.inputs.brew-src.follows = "brew-src";
brew-src = { url = "github:Homebrew/brew"; flake = false; };
```

The reason (documented in `notes/homebrew.md`): nix-homebrew's pinned brew
(5.1.7) had a parser crash on the current cask JSON API. Pointing `brew-src` at
Homebrew's `master` picks up the fix while `flake.lock` still pins an exact SHA,
so builds stay reproducible until you deliberately run `nix flake update brew-src`.
This override is a temporary workaround; when nix-homebrew bumps its own pin past
the fixed version, the `brew-src` input and the `follows` line can be deleted.
This is also why an "invalid cask definition" error is usually fixed by updating
`brew-src` — see the [installation troubleshooting](#invalid-cask-definition-errors).

### macOS defaults

`modules/system/defaults.nix` declares system preferences under
`system.defaults`. Each option corresponds to a macOS user-defaults key that
would otherwise be set by clicking through **System Settings** or running
`defaults write`. On every activation nix-darwin writes these keys, so the Dock
layout, Finder behaviour, key-repeat speed, trackpad gestures, screenshot
location, dark mode, and 24-hour clock are all reproducible. Some of these are
read by macOS only at login or after a restart, and a handful of settings simply
cannot be expressed declaratively — those must still be granted by hand in
System Settings (see [Caveats](#caveats)).

### The Claude Code / Codex profile model

Claude Code and Codex each keep a single config directory, which mixes shared
configuration with account-specific authentication. To run multiple accounts
(e.g. work and personal) cleanly, `modules/home/ai-profiles.nix` installs a
small system built on symlinks and an environment-variable redirect. The model:

- **Canonical home** — `~/.claude` / `~/.codex` holds *all non-auth config*
  (settings, agents, commands, hooks, `CLAUDE.md`, …). This is the single source
  of truth for shared configuration.
- **Profile home** — `~/.claude-<profile>` / `~/.codex-<profile>` represents one
  account. Every non-auth entry inside it is a **symlink back to canonical**;
  only the authentication files are *real* files that live per-profile
  (`.claude.json` + `.credentials.json` for Claude; `auth.json` for Codex).

Launching a profile redirects the tool at its profile home via an environment
variable (`CLAUDE_CONFIG_DIR` / `CODEX_HOME`) rather than by moving files
around:

```bash
claude-use work      # CLAUDE_CONFIG_DIR=~/.claude-work claude
codex-use personal   # CODEX_HOME=~/.codex-personal codex
```

Before launch, a **sync engine** (`profile-sync.sh`) runs two passes:

1. **Promote** — any genuinely new, non-auth file created inside a profile home
   is moved *into* canonical (so new shared config written by one account
   becomes shared).
2. **Relink** — every canonical non-auth entry is (re)symlinked into the profile
   home.

The net effect: config is shared across all accounts automatically, while
credentials stay strictly isolated — conversations and tokens never bleed
between contexts. Bare `claude` / `codex` are shadowed by shell functions that
refuse to run and print the available profiles, so the account choice is always
explicit. The scripts are plain bash sourced by the interactive shell (from
`home/shell.nix`), so the exact same behaviour works on the Mac and inside dev
containers; `scripts/setup-ai-profiles.sh` installs the identical mechanism on
non-Nix (e.g. Linux) machines by wiring it into `~/.bashrc`.

### Cleanup: deliberately imperative

Removing software and reclaiming disk space is *not* done on rebuild. It is
handled by interactive scripts under `scripts/`, dispatched through
`my-machine-clean` (see [Cleanup](#cleanup)). This is a deliberate choice:
deletion is destructive and hard to reverse, so it asks before acting, shows a
full manifest, and defaults to moving items to the Trash rather than `rm`-ing
them. The app remover is origin-aware (it knows whether an app came from brew,
the App Store, or was installed manually) and, for brew casks, offers to remove
the corresponding line from `modules/homebrew.nix` so a zapped app is not simply
reinstalled on the next rebuild.

### Tunnels

`tunnel-port` (`scripts/tunnel-port.sh`) exposes a local port publicly through
either ngrok or a Cloudflare named tunnel. The Cloudflare and ngrok domains come
from `private.nix`, are exported into the shell as environment variables by
`home/shell.nix`, and are read by the script at runtime. In Cloudflare mode it
creates (or reuses) a named tunnel per subdomain, points DNS at it, writes an
ingress config, kills any previous instance of the same tunnel, and runs
`cloudflared`. This keeps the public-facing domain values in your machine-local
`private.nix` rather than hard-coded in a tracked script.

## What manages what?

| Layer | Responsibility | Removal behavior |
|---|---|---|
| Determinate Nix | Nix daemon, store, installer, and daemon lifecycle | Store cleanup is managed separately from Homebrew |
| nix-darwin | System packages, services, users, and macOS defaults | Declarative installation and configuration |
| nix-homebrew | Homebrew, casks, formulae, and optional App Store apps | Undeclared brews/casks are removed because cleanup is `zap` |
| Home Manager | Shell, prompt, Git, tmux, direnv, dotfiles, and user config | Declarative installation and configuration |
| Cleanup scripts | App data, orphaned files, caches, Docker data, and old Nix paths | Manual and interactive |

## Fresh Mac installation

The following instructions assume:

- an Apple Silicon Mac
- a new or recently reset macOS installation
- an administrator account
- an internet connection

Commands are intended to be run in Terminal.

### 1. Install Apple command-line tools

```bash
xcode-select --install
```

Wait for the installation to finish, then verify:

```bash
git --version
xcode-select -p
```

### 2. Clone the repository into its expected location

The shell aliases and scripts in this repository expect the repo at:

```text
~/.config/nix-darwin
```

Clone directly there:

```bash
mkdir -p ~/.config
git clone <REPOSITORY_URL> ~/.config/nix-darwin
cd ~/.config/nix-darwin
```

If the repository has already been cloned somewhere else, move it. Quote paths
that contain spaces:

```bash
mkdir -p ~/.config
mv "/path/containing spaces/nix-darwin" ~/.config/nix-darwin
cd ~/.config/nix-darwin
```

Verify:

```bash
pwd
```

Expected result:

```text
/Users/<your-username>/.config/nix-darwin
```

### 3. Create the machine-specific configuration

Copy the template:

```bash
cp private.nix.example private.nix
git update-index --skip-worktree private.nix
```

Collect the values required by the file:

```bash
whoami
scutil --get LocalHostName
uname -m
```

Edit it:

```bash
nano private.nix
```

Example for an Apple Silicon Mac:

```nix
{
  username = "yourusername";
  hostname = "Your-MacBook-Pro";
  system = "aarch64-darwin";

  git = {
    name = "Your Name";
    email = "you@example.com";
  };

  ngrokDomain = "";

  # Safe placeholders when Cloudflare Tunnel is not configured yet.
  cfDomain = "example.com";
  cfTunnel = "your-mac";
}
```

Notes:

- `username` must exactly match `whoami`.
- `hostname` must exactly match `scutil --get LocalHostName`.
- Apple Silicon uses `aarch64-darwin` even though `uname -m` prints `arm64`.
- A GitHub noreply email can be used to keep a personal email out of commits.
- `private.nix` must remain tracked because flakes cannot read untracked files.
  `skip-worktree` prevents local values from appearing in normal Git changes.

Verify that local secrets are hidden from Git:

```bash
git status
```

`private.nix` should not appear as modified.

### 4. Review the applications before installation

Open the Homebrew module:

```bash
nano modules/homebrew.nix
```

Review the `brews`, `casks`, and `masApps` sections. Remove applications you do
not want and add anything that must be retained.

This step matters because the configuration uses:

```nix
homebrew.onActivation.cleanup = "zap";
```

On a Mac that already contains Homebrew software, consider temporarily changing
it to:

```nix
homebrew.onActivation.cleanup = "none";
```

Complete the first rebuild, audit the installed software, declare what should be
kept, and only then restore `"zap"`.

### 5. Install Determinate Nix

This configuration expects Determinate Nix to manage the Nix daemon. Therefore:

```nix
nix.enable = false;
```

is intentional and should remain unchanged.

Install Determinate Nix using the official macOS package or installer. For the
command-line installer:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix \
  | sh -s -- install
```

When prompted, approve the installation.

After installation, completely close Terminal and open it again. Then verify:

```bash
nix --version
which nix
ls -ld /nix
```

A working installation should show a Determinate Nix version and a binary under:

```text
/nix/var/nix/profiles/default/bin/nix
```

#### If `/nix` exists but `nix` is not found

Load the Nix shell integration manually:

```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix --version
```

Then close and reopen Terminal.

#### If the installer cannot mount `Nix Store`

An error similar to the following means the encrypted APFS volume was created
but could not be mounted:

```text
Volume on diskXsY failed to mount
Error saving receipt: Read-only file system
```

At the installer's rollback prompt, choose `Y` and let it remove the partial
installation. Restart the Mac and check that cleanup succeeded:

```bash
ls -ld /nix 2>/dev/null
diskutil apfs list | grep -A 8 -B 3 "Nix Store"
grep -n nix /etc/fstab 2>/dev/null
profiles status -type enrollment
```

If no stale volume or `/etc/fstab` entry remains, retry with Determinate's macOS
package installer. If a stale `Nix Store` volume remains, remove only that APFS
volume using Disk Utility before retrying.

### 6. Install Rosetta

The flake enables Intel Homebrew under `/usr/local` in addition to native Apple
Silicon Homebrew. Install Rosetta before the first rebuild:

```bash
sudo softwareupdate --install-rosetta --agree-to-license
```

Verify:

```bash
/usr/bin/pgrep oahd >/dev/null && echo "Rosetta installed"
```

### 7. Run the first nix-darwin activation

From the repository root:

```bash
cd ~/.config/nix-darwin
```

Run the bootstrap command:

```bash
sudo nix run github:LnL7/nix-darwin#darwin-rebuild -- \
  switch --flake ~/.config/nix-darwin
```

The first rebuild may take a while because it installs Nix packages, Homebrew,
GUI applications, shell configuration, and macOS defaults.

During this process macOS may request:

- the administrator password
- Rosetta installation if it was skipped
- permission to open downloaded applications
- accessibility, notification, screen-recording, or automation permissions for
  individual applications

#### Homebrew `--cleanup` deprecation warning

The following warning is currently non-fatal:

```text
Warning: Calling the `--cleanup` switch is deprecated! There is no replacement.
```

If the rebuild continues without an `Error:` line, no action is required.

#### Invalid cask definition errors

If Homebrew reports an error such as:

```text
Cask 'ngrok' definition is invalid: undefined method ...
```

update the Homebrew source pinned by the flake:

```bash
cd ~/.config/nix-darwin
nix flake update brew-src
git diff -- flake.lock
```

Retry the rebuild:

```bash
sudo nix run github:LnL7/nix-darwin#darwin-rebuild -- \
  switch --flake ~/.config/nix-darwin
```

If necessary, update `nix-homebrew` and `brew-src` together:

```bash
nix flake update nix-homebrew brew-src
```

See [The `brew-src` override](#the-brew-src-override) and `notes/homebrew.md`
for why this happens.

### 8. Start the managed shell

After the first successful rebuild:

```bash
exec zsh
```

Or close Terminal and open it again.

Verify the setup:

```bash
darwin-rebuild --list-generations
brew --version
tmux -V
git config --global user.name
git config --global user.email
which rg
which fzf
which code
```

### 9. Use the normal rebuild command

After the initial activation, the shell provides:

```bash
rebuild
```

It expands to:

```bash
sudo darwin-rebuild switch --flake ~/.config/nix-darwin
```

Use it whenever a `.nix` file changes:

```bash
cd ~/.config/nix-darwin
rebuild
```

### 10. Configure Claude Code and Codex profiles

Bare `claude` and `codex` commands are deliberately blocked so that the account
profile is always explicit (see [The Claude Code / Codex profile
model](#the-claude-code--codex-profile-model)).

Create or launch profiles with any names you prefer:

```bash
claude-use personal
claude-use work
codex-use personal
codex-use work
```

Log in once for each profile. List existing profiles with:

```bash
claude-ls
codex-ls
```

The canonical config is shared, while authentication remains isolated per
profile.

## Quick installation checklist

```bash
# 1. Apple tools
xcode-select --install

# 2. Repository
git clone <REPOSITORY_URL> ~/.config/nix-darwin
cd ~/.config/nix-darwin

# 3. Host settings
cp private.nix.example private.nix
git update-index --skip-worktree private.nix
nano private.nix
nano modules/homebrew.nix

# 4. Determinate Nix
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix \
  | sh -s -- install

# Close and reopen Terminal here.

# 5. Rosetta
sudo softwareupdate --install-rosetta --agree-to-license

# 6. Bootstrap nix-darwin
cd ~/.config/nix-darwin
sudo nix run github:LnL7/nix-darwin#darwin-rebuild -- \
  switch --flake ~/.config/nix-darwin

# 7. Reload and verify
exec zsh
darwin-rebuild --list-generations
brew --version
```

## Architecture

```text
flake.nix                    Inputs and host wiring
│
├── nixpkgs                  Package set (tracks nixpkgs-unstable)
├── nix-darwin               macOS system module system
├── home-manager             Per-user dotfiles and packages
├── nix-homebrew             Declarative Homebrew management
└── brew-src                 Explicit Homebrew source pin (see notes/homebrew.md)

modules/
├── system.nix               Aggregator for system modules
│   └── system/
│       ├── packages.nix     System-wide CLI tools (ripgrep, fd, jq, gh, …)
│       ├── nix.nix          nix.enable = false, stateVersion, hostPlatform
│       ├── users.nix        Primary user and Touch ID for sudo
│       └── defaults.nix     macOS preferences (system.defaults.*)
│
├── homebrew.nix             Brews, casks, and Mac App Store apps; cleanup = zap
│
└── home.nix                 Aggregator for Home Manager modules
    └── home/
        ├── packages.nix     User packages
        ├── shell.nix        Zsh, Starship, fzf, bat, zoxide, aliases, functions
        ├── git.nix          Git and Delta (side-by-side diffs)
        ├── tmux.nix         tmux configuration (vi copy mode, custom keymap)
        ├── direnv.nix       direnv and nix-direnv
        └── ai-profiles.nix  Claude Code and Codex profile scripts

modules/claude/              Canonical Claude Code configuration (synced via apply-ai/sync-ai)
modules/codex/               Canonical Codex configuration
scripts/                     Operational and cleanup helpers
notes/                       Longer implementation notes (e.g. homebrew.md)
```

## Host configuration and privacy

All machine-specific values live in `private.nix`. Every module receives these
values through `specialArgs` / `extraSpecialArgs`, so only one file needs to be
edited per machine.

The file is tracked because flakes ignore untracked files, but local edits are
hidden with:

```bash
git update-index --skip-worktree private.nix
```

To temporarily make changes visible to Git:

```bash
git update-index --no-skip-worktree private.nix
# Edit, commit, and push placeholder or template changes.
git update-index --skip-worktree private.nix
```

Never commit real credentials, private domains, or personal identity values.

## Common commands

```bash
# Apply the configuration
rebuild

# Update every flake input
nix flake update

# Selectively update inputs
my-nix-update

# Roll back to the previous generation
darwin-rebuild --rollback

# List generations
darwin-rebuild --list-generations

# Apply repo copies of Claude/Codex config to live config
apply-ai

# Copy live Claude/Codex config back into the repo
sync-ai
```

## Useful shell commands

| Command | Purpose |
|---|---|
| `ll`, `ls`, `lt` | Enhanced file listings using eza |
| `cat` | Syntax-highlighted output using bat |
| `g`, `gs`, `gc`, `gp`, `gd`, `gl` | Git shortcuts |
| `lg` | Open lazygit |
| `rebuild` | Apply the nix-darwin configuration |
| `my-nix-update` | Selectively update flake inputs |
| `my-machine-clean` | Open the cleanup selector |
| `sshp` | Select an SSH host using fzf |
| `tmux-pick` | Select and attach to a tmux session |
| `llmctx` | Flatten the current repository into Markdown |
| `repo-to-zip` | Zip a repository while honoring `.gitignore` |
| `tunnel-port` | Expose a local port through ngrok or Cloudflare |

## Cleanup

Cleanup is deliberately manual and interactive (see [Cleanup: deliberately
imperative](#cleanup-deliberately-imperative)).

```bash
# Interactive menu
my-machine-clean

# Preview app and app-data removal
my-machine-clean apps --dry-run

# Find leftover data from removed applications
my-machine-clean orphans

# Nix, Homebrew, Docker, npm, Python, Playwright, and Xcode cleanup
my-machine-clean system

# More aggressive cleanup
my-machine-clean deep
```

App removal displays a complete manifest before touching anything. By default,
items are moved to Trash rather than permanently deleted. When a removed cask is
still declared in `modules/homebrew.nix`, the script offers to delete that line
so it is not reinstalled on the next rebuild.

## Tmux

The prefix remains the default `Ctrl-b`. Mouse mode and vi copy mode are enabled.

| Binding | Action |
|---|---|
| `Ctrl-b`, `Ctrl-Shift-Right` | Split vertically |
| `Ctrl-b`, `Ctrl-Shift-Down` | Split horizontally |
| `Ctrl-b`, `Ctrl-Shift-Up` | Create a new window |
| `Ctrl-b`, `Shift-Left/Right` | Move the current window |
| `Ctrl-b`, `Alt-Arrow` | Resize the pane |
| Copy mode `v` | Begin selection |
| Copy mode `y` | Copy and exit copy mode |

## macOS defaults

The configuration applies macOS preferences on every rebuild (see [macOS
defaults](#macos-defaults) under How it works), including:

- Dock placement, size, autohide, and recent-app behavior
- Finder hidden files, path bar, status bar, and column view
- dark appearance
- faster key repeat
- disabled automatic capitalization, correction, and period substitution
- tap-to-click, right-click, and three-finger drag
- screenshots saved under `~/Pictures/Screenshots`
- 24-hour menu bar clock
- Touch ID authentication for `sudo`

## Caveats

- This repository is designed primarily for Apple Silicon. Intel Macs require
  `system = "x86_64-darwin"` and may require additional module changes.
- `homebrew.cleanup = "zap"` is intentionally strict.
- Homebrew cask definitions can evolve faster than an older `brew-src` lock;
  update `brew-src` when cask DSL compatibility errors occur.
- Some macOS permissions cannot be granted declaratively and must be approved in
  System Settings.
- Mac App Store applications must be declared under `masApps` if they should be
  installed reproducibly.
- Manual applications and historical `~/Library` leftovers are handled through
  the cleanup scripts, not automatically on every rebuild.
</content>
</invoke>
