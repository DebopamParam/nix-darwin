{ ... }:

# Unified profile model for Claude Code and Codex.
#
#   ~/.claude / ~/.codex        canonical home — holds ALL non-auth config
#   ~/.claude-<p> / ~/.codex-<p> profile home — selects an account; every
#                               non-auth entry is a symlink back to canonical,
#                               only auth files stay real.
#
# Launching a profile syncs it first (promote genuinely-new profile-local
# entries into canonical, then relink everything). Bare `claude`/`codex` are
# blocked so the account choice is always explicit.

{
  # Sync engine — bash so `shopt` globbing works identically on macOS, Linux,
  # and inside dev containers regardless of the interactive shell.
  home.file.".config/ai-profiles/profile-sync.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Usage: profile-sync.sh <canonical-dir> <profile-home> <auth-basename...>
      set -euo pipefail

      canon="$1"; home="$2"; shift 2
      auth=" $* "
      mkdir -p "$canon" "$home"

      shopt -s dotglob nullglob

      is_auth() { case "$auth" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

      # Promote genuinely-new non-auth profile-local entries into canonical.
      for e in "$home"/*; do
        n="$(basename "$e")"
        is_auth "$n" && continue
        case "$n" in *.pre-unify.bak) continue ;; esac
        [ -L "$e" ] && continue
        if [ ! -e "$canon/$n" ] && [ ! -L "$canon/$n" ]; then
          mv "$e" "$canon/$n"
        fi
      done

      # Link every canonical non-auth entry into the profile home.
      for e in "$canon"/*; do
        n="$(basename "$e")"
        is_auth "$n" && continue
        l="$home/$n"
        if [ -L "$l" ] && [ "$(readlink "$l")" = "$e" ]; then
          continue
        fi
        # discard-and-relink: drop any existing real entry (no backup)
        if [ -e "$l" ] || [ -L "$l" ]; then
          rm -rf "$l"
        fi
        ln -s "$e" "$l"
      done
    '';
  };

  # Launchers + blockers — sourced by the interactive shell (see shell.nix).
  home.file.".config/ai-profiles/init.sh" = {
    executable = true;
    text = ''
      _AI_SYNC="$HOME/.config/ai-profiles/profile-sync.sh"

      # ── Claude ──────────────────────────────────────────────────
      claude-use() {
        if [ -z "''${1:-}" ]; then echo "usage: claude-use <profile>  (list: claude-ls)" >&2; return 1; fi
        local p="$1"; shift
        local h="$HOME/.claude-$p"
        bash "$_AI_SYNC" "$HOME/.claude" "$h" .claude.json .credentials.json
        CLAUDE_CONFIG_DIR="$h" command claude "$@"
      }
      claude-ls() { ls -d "$HOME"/.claude-*/ 2>/dev/null | sed 's#.*/\.claude-##; s#/##'; }
      claude() {
        echo "❌  Don't run 'claude' directly. Use: claude-use <profile>" >&2
        echo "    profiles: $(claude-ls | paste -sd' ' -)" >&2
        return 1
      }

      # ── Codex ───────────────────────────────────────────────────
      codex-use() {
        if [ -z "''${1:-}" ]; then echo "usage: codex-use <profile>  (list: codex-ls)" >&2; return 1; fi
        local p="$1"; shift
        local h="$HOME/.codex-$p"
        bash "$_AI_SYNC" "$HOME/.codex" "$h" auth.json
        CODEX_HOME="$h" command codex "$@"
      }
      codex-ls() { ls -d "$HOME"/.codex-*/ 2>/dev/null | sed 's#.*/\.codex-##; s#/##'; }
      codex() {
        echo "❌  Don't run 'codex' directly. Use: codex-use <profile>" >&2
        echo "    profiles: $(codex-ls | paste -sd' ' -)" >&2
        return 1
      }
    '';
  };
}
