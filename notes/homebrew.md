# Homebrew / nix-homebrew notes

Context for future agents working on this nix-darwin config.

## Setup overview

This config uses [`nix-homebrew`](https://github.com/zhaofengli/nix-homebrew) to manage Homebrew declaratively. Key consequences:

- `/opt/homebrew/Library/Homebrew` is a symlink into the nix store (the `brew` source tree itself).
- `/opt/homebrew/Library/Taps` is a symlink into the nix store (`-taps-env`) and is **read-only**.
- Because Taps is read-only, `HOMEBREW_NO_INSTALL_FROM_API=1` will fail — brew cannot clone `homebrew/homebrew-core` or `homebrew/homebrew-cask` into the Taps directory. Don't suggest that workaround.
- To use git-tap definitions instead of the JSON API, taps must be declared as flake inputs and threaded through nix-homebrew. We do **not** do this currently — we rely on the JSON API.

## Brew version override

`flake.nix` overrides nix-homebrew's `brew-src` input:

```nix
nix-homebrew = {
  url = "github:zhaofengli/nix-homebrew";
  inputs.brew-src.follows = "brew-src";
};
brew-src = {
  url = "github:Homebrew/brew";   # tracks master
  flake = false;
};
```

### Why the override exists

In May 2026, nix-homebrew's pinned brew (5.1.7) crashed parsing the cask JSON API:

```
undefined method 'to_sym' for nil
.../api/cask/cask_struct_generator.rb:100:in 'process_depends_on'
```

Cause: brew's JSON API changed how it serializes bare `depends_on :macos` (no operator). The 5.1.7 parser called `value.keys.first.to_sym` on an empty hash. Fixed in brew commit `1c8cbf3` (May 6 2026), shipped in 5.1.10 (May 7).

Since nix-homebrew had not bumped its `brew-src` pin, the only fix without waiting on upstream was to override the input.

### Why master, not a tagged version

Tag pinning (e.g. `Homebrew/brew/5.1.10`) requires manual ref bumps to get future fixes. Tracking master gets fixes automatically; the lock file still pins an exact SHA so builds remain reproducible until `nix flake update brew-src` is run.

## Risks of tracking master

1. **nix-homebrew patches brew source** (note the `-patched` suffix on the brew nix-store path). If a master commit refactors a patched file, the next rebuild fails at the brew derivation with `patch: hunk failed`. This is the most likely failure mode.
   - Recovery: `git checkout flake.lock && rebuild` to roll back to the prior brew SHA.
   - If recurring: pin `brew-src` to a specific tag temporarily.

2. **Transient regressions on master** between releases — uncommon but possible.

3. **`nix flake update` (no args) bundles brew changes** with everything else. Prefer per-input updates when bisecting.

## Long-term exit ramp

The override is a workaround. When nix-homebrew bumps its own `brew-src` pin past the buggy version (currently 5.1.7), the override can be removed entirely.

Periodic check:

```bash
nix flake update nix-homebrew
git diff flake.lock
```

If `nix-homebrew/brew-src` advances past the version where the parser bug was fixed (5.1.10+), delete the `brew-src` input and the `inputs.brew-src.follows` line from `flake.nix`.

## Anti-patterns to avoid

- **Don't write to `/opt/homebrew/etc/homebrew/brew.env`** to set brew env vars. It works for direct shell invocations but conflicts with the read-only Taps when `HOMEBREW_NO_INSTALL_FROM_API=1` is set, and it's not declarative.
- **Don't suggest clearing `~/Library/Caches/Homebrew/api/`** as a fix for parser crashes. The bug is in the parser, not the cache; a fresh download produces the same JSON.
- **Don't bump the whole nixpkgs input** to chase a brew fix. The brew version comes from `nix-homebrew/brew-src`, not nixpkgs. Bumping nixpkgs is a much larger change with unrelated side effects.
- **Don't bisect casks** to find "the bad one" when every cask fails with the same parser error. The bug is in the shared parser path, not in any specific cask's JSON.

## Diagnostic commands

```bash
# What brew binary is actually running
brew --version
ls -la /opt/homebrew/Library/Homebrew

# Confirm Taps is read-only nix-managed
ls -la /opt/homebrew/Library/Taps

# What brew version nix-homebrew is pinning
grep -A 5 'brew-src' flake.lock

# Test a single cask fetch
brew fetch --cask rectangle
```
