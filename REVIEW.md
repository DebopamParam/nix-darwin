# Repo Review — nix-darwin config

**Scope:** full strict review of this repo against its stated purpose:
*everything declared here exists on the laptop; everything else is removed —
including its data — so the machine stays deterministic and free of orphaned
cruft.*

**Verdict:** the core promise is genuinely delivered for **Homebrew casks and
formulae** (`onActivation.cleanup = "zap"` is active), and system settings /
shell / dotfiles are solidly declarative. But the "everything else is deleted"
claim was only true for one layer of the stack. Several other layers escape
the guarantee entirely, and there were a handful of real bugs and dead
references. Findings below are ranked by severity; items marked **[FIXED]**
were corrected as part of this review, the rest are recommendations.

---

## 1. Determinism gaps (the purpose of the repo)

### 1.1 The zap guarantee only covers Homebrew — severity: high
`brew bundle cleanup --zap` removes undeclared casks/brews **and their data
(per each cask's zap stanza)** on rebuild. Nothing else on the machine gets
that treatment:

| Layer | Covered? | Notes |
|---|---|---|
| Brew casks/brews | ✅ zap | Only as complete as each cask's zap stanza; stanza-less casks leave `~/Library` data behind |
| Mac App Store apps | ❌ | `brew bundle cleanup` never uninstalls MAS apps; `masApps = {}` means any MAS install persists silently and invisibly |
| Manually installed apps | ❌ | Drag-and-drop `.app`s and curl installers are invisible to both nix and brew |
| Global npm packages | ❌ | `sync-ai-config.sh` itself does `sudo npm install -g ccstatusline` — an imperative install this repo can't see or remove |
| Nix store | ❌ | GC is manual-only (see 1.2) |
| Orphaned `~/Library` data | ❌ | Data from apps deleted before zap was enabled, or from stanza-less casks, lingers forever |

**[FIXED — new tool]** `scripts/app-zap.sh` (via the unified `my-machine-clean` alias: `my-machine-clean apps`) closes the
removal side of these gaps *manually and selectively*, per explicit user
preference (no automatic deletion):

- enumerates **all** apps in `/Applications` + `~/Applications`, tagged by
  origin (`[brew]` / `[mas]` / `[manual]`)
- fzf multi-select → full deletion manifest (app bundle + every associated
  data path across 11 `~/Library` locations, matched conservatively by exact
  bundle-id and exact app name, with per-path sizes)
- double confirmation (y/N, then a typed `yes`); `--dry-run` to preview
- deletion goes to the **Trash** (recoverable) unless `--permanent`
- every path passes a hard allowlist/denylist (`is_safe_path`) — the script
  physically refuses to touch `$HOME`, `~/Documents`, this repo, or anything
  outside app bundles and the known `~/Library` data dirs
- brew apps: uses `brew uninstall --zap` (the maintained stanza) first, sweeps
  residue after, then offers to delete the cask's line from
  `modules/homebrew.nix` so the next rebuild doesn't resurrect it
- root-owned `/Library` paths are listed in the manifest but never deleted
  (shown with a "remove manually with sudo" note)
- `my-machine-clean orphans`: scans `~/Library` for bundle-id data whose app no
  longer exists anywhere on disk (excludes `com.apple.*`; helper ids are
  matched to their parent app by 3-component bundle-id prefix) — same
  manifest/confirm/Trash pipeline

**Still recommended (not done):** declare your MAS apps in
`homebrew.masApps` so at least the *install* side of MAS is deterministic,
and move `ccstatusline` into nix (e.g. `home.packages` via
`pkgs.nodePackages` or a wrapper) instead of `sudo npm -g`.

### 1.2 Nix store garbage collection is manual-only — severity: medium
`modules/system/nix.nix` sets `nix.enable = false` (Determinate Systems
manages the daemon), which makes nix-darwin's `nix.gc.automatic` unavailable.
The only GC path is remembering to run `my-machine-clean system`
(`nix-collect-garbage --delete-older-than 15d`). Old system generations and
store paths accumulate unboundedly between runs.

Per user preference this stays **manual** — but be aware it is the one "space
occupancy" leak with no declarative backstop. If that ever changes, the
options are Determinate's own GC settings or a `launchd.user.agents` entry
declared in nix-darwin.

### 1.3 Non-deterministic activation inputs — severity: low
- `homebrew.onActivation.autoUpdate = true` refreshes brew metadata on every
  `rebuild`, so two rebuilds of the same commit can install different cask
  versions (and rebuilds are slower). For strict reproducibility set it to
  `false` and update deliberately via `my-nix-update`. **[FIXED: the comment
  that claimed the opposite ("don't slow down every rebuild") now describes
  the real trade-off; the value was intentionally left `true`.]**
- `nix-homebrew.autoMigrate = true` in `flake.nix` is a one-time migration
  escape hatch. Harmless once migrated; consider removing to make the flake
  self-describing.

### 1.4 AI config is synced, not applied — severity: medium
`modules/claude/*` and `modules/codex/*` are **passive copies**, kept in sync
only when you remember to run `sync-ai` / `apply-ai` (`sync-ai-config.sh`).
A rebuild does not apply them, so live `~/.claude` / `~/.codex` can silently
drift from the repo — the opposite of the repo's philosophy.

**Recommendation:** render them through home-manager. For files you also edit
via the tools' own UIs, use
`home.file.".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink …`
so the live file *is* the repo file — drift becomes impossible and `git diff`
shows every change. (The existing `ai-profiles.nix` already demonstrates the
`home.file` pattern.)

Related: `sync-ai-config.sh` lists `modules/claude/{agents,commands,hooks}`
and `modules/codex/AGENTS.md`, none of which exist in the repo — `--apply`
for those is a silent no-op today, and a pull will create untracked dirs.
Either create them or trim the lists.

---

## 2. Bugs and dead code — all fixed

| # | Finding | Fix |
|---|---|---|
| 2.1 | **Duplicate cask** `appcleaner` declared twice in `modules/homebrew.nix` | **[FIXED]** single entry under Utilities |
| 2.2 | **Misleading comments** in `modules/homebrew.nix`: `autoUpdate = true # Don't slow down every rebuild` said the opposite of the truth; the "⚠ START WITH none" onboarding warning contradicted the committed `"zap"` | **[FIXED]** comments now describe actual behavior of both options |
| 2.3 | **Dead code for a non-existent flake input**: `scripts/update-select.sh` special-cased a `homebrew-cask` input (staleness warning + a 40-line post-rebuild rescan block) that isn't in `flake.lock` — casks come from brew's API, so the branch could never fire and its comments misdescribed the setup | **[FIXED]** removed; script is ~55 lines shorter and honest |
| 2.4 | **Personal email hardcoded** as a default in `scripts/setup-bash.sh` (`GIT_EMAIL="debopamwork@gmail.com"`), in a repo whose README positions it as public/forkable | **[FIXED]** no personal defaults; identity comes from `--user`/`--email` or an interactive prompt |
| 2.5 | **Dangling references to `notes/temp.md`** (deleted file) in `modules/home/ai-profiles.nix`, `scripts/setup-ai-profiles.sh`, and `README.md` | **[FIXED]** references removed |
| 2.6 | **Miscategorized casks**: `linearmouse`, `claude-code@latest`, `orbstack`, `pgadmin4`, etc. all sat under the "Browsers" header; stale "add your existing casks before switching to zap" onboarding note | **[FIXED]** casks regrouped into honest categories (Browsers / AI / Editors / Dev / …); zero adds or removes — verify with `git diff` |

**Verified intact:** the `private.nix` privacy scheme works as documented —
the *committed* file contains only placeholders, real values live in the
working tree under `git update-index --skip-worktree`. (Initial suspicion
that real PII was committed was wrong; checked via `git show HEAD:private.nix`.)

---

## 3. Design & code-quality recommendations (not applied)

### 3.1 Triplicated profile scripts — severity: medium (maintenance)
The `profile-sync.sh` + `init.sh` bodies exist verbatim in **three** places:
`modules/home/ai-profiles.nix` (heredoc), `scripts/setup-ai-profiles.sh`
(heredoc), and partially in `scripts/setup-bash.sh`. Any behavior change must
be replicated by hand in all three, and they *will* drift.

**Fix:** keep one real file per script (e.g. `scripts/lib/profile-sync.sh`)
and reference it everywhere:
- nix: `home.file.".config/ai-profiles/profile-sync.sh".source = ../../scripts/lib/profile-sync.sh;`
- bash installers: `cp` from the same path (or `curl` the raw file for
  remote machines).

### 3.2 Environment-coupled aliases — severity: low
`sync-obsidian = "bash ~/Documents/turboml-docs/sync-to-obsidian.sh"` points
outside the repo and will be a broken alias on any fresh machine. Guard it
(`[[ -f … ]] && bash …`) or move the script into the repo. Same class of
issue: `/opt/homebrew/bin/brew`, `~/.orbstack/...` hardcoded in `shell.nix` —
acceptable on aarch64-darwin-only config, just know they're assumptions.

### 3.3 `brew-src` tracks HEAD — severity: low (documented)
The `brew-src` flake input follows `Homebrew/brew` HEAD, so `nix flake update
brew-src` can pull an unreleased brew. `notes/homebrew.md` already documents
the recovery path; pinning to a release tag would remove the risk entirely.

### 3.4 README honesty — severity: low
The README should state plainly which layers are declarative-with-removal
(brew), declarative-install-only (nix packages, macOS defaults, dotfiles),
and manual (MAS, AI config, caches, nix GC — now with the unified `my-machine-clean` command
(`my-machine-clean apps` / `orphans` / `system`) as the manual tool). One table saves the next reader an
afternoon of wrong assumptions.

---

## 4. Suggested next steps, in order

1. **Adopt `my-machine-clean`** (`rebuild`, then use `my-machine-clean apps --dry-run` first;
   `my-machine-clean orphans` once to purge historical leftovers — it already found
   real orphans, e.g. ChatGPT-app and Warp data, during testing).
2. **Declare MAS apps** in `homebrew.masApps` (run `mas list`) so the App
   Store layer is at least install-deterministic.
3. **Dedupe the profile scripts** (3.1) — highest-leverage maintenance fix.
4. **Move AI config into home-manager** with out-of-store symlinks (1.4),
   retiring most of `sync-ai-config.sh`.
5. **Move `ccstatusline` into nix**, removing the `sudo npm -g` from
   `sync-ai-config.sh`.
6. Decide on `autoUpdate` (reproducibility vs freshness) and drop
   `autoMigrate` now that migration is done.
7. Optional: pin `brew-src` to a release tag; add the README layer table.

---

## 5. How the fixes were verified

- `bash -n` (and `/bin/bash -n` for macOS bash 3.2 compatibility) on every
  touched script.
- `app-zap.sh`: safety guard unit-tested (refuses `$HOME`, `~/Library`,
  `~/Documents`, the repo, bare data-dir roots; allows app bundles and
  data paths); full `--dry-run` exercised end-to-end with a stubbed fzf —
  correct manifest for a brew app (Slack: bundle, container, group
  container, sizes, running-app warning); `--orphans --dry-run` exercised
  and found genuine orphans. No deletion paths were executed.
- `grep` confirms: no `temp.md` references, no personal email in scripts,
  `appcleaner` declared exactly once.
- Nix evaluation checked with a dry-run build of the darwin configuration.
