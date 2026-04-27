{ lib, ... }:

{
  home.activation.claudeProfiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # ~/.claude is the shared dir — Claude Code's default config location
    mkdir -p $HOME/.claude/plugins

    # Per-profile dirs — auth + session history, never shared
    mkdir -p $HOME/.claude-personal
    mkdir -p $HOME/.claude-work

    # Symlink shared assets into each profile
    for profile in personal work; do
      ln -sfn $HOME/.claude/plugins       $HOME/.claude-$profile/plugins
      if [ -f $HOME/.claude/settings.json ]; then
        ln -sfn $HOME/.claude/settings.json $HOME/.claude-$profile/settings.json
      fi
      if [ -f $HOME/.claude/CLAUDE.md ]; then
        ln -sfn $HOME/.claude/CLAUDE.md     $HOME/.claude-$profile/CLAUDE.md
      fi
    done
  '';

  home.file.".config/claude-profiles/init.sh" = {
    executable = true;
    text = ''
      # Claude Code profile switcher
      # ~ is intentionally evaluated at shell-startup time inside the container,
      # so it resolves correctly whether the container user is root, vscode, etc.
      _CLAUDE_BASE="$(eval echo ~)"
      alias claude-personal="CLAUDE_CONFIG_DIR=''${_CLAUDE_BASE}/.claude-personal command claude"
      alias claude-work="CLAUDE_CONFIG_DIR=''${_CLAUDE_BASE}/.claude-work command claude"

      # Block bare `claude` — a function shadows the binary and can't be bypassed
      claude() {
        echo "❌  Don't use 'claude' directly. Use:" >&2
        echo "     claude-work      → work account" >&2
        echo "     claude-personal  → personal account" >&2
        return 1
      }

      unset _CLAUDE_BASE
    '';
  };
}
