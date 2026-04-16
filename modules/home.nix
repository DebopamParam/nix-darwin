{ pkgs, lib, ... }:

{
  home.stateVersion = "24.11";
  home.username = "debopamchowdhury";
  home.homeDirectory = "/Users/debopamchowdhury";

  # ── User Packages ─────────────────────────────────────────────

  home.packages = with pkgs; [
    # Add user-specific packages here if needed
  ];

  home.activation.claudeProfiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Shared dir — plugins and global config
    mkdir -p $HOME/.claude-shared/plugins

    # Per-profile dirs — auth + session history, never shared
    mkdir -p $HOME/.claude-personal
    mkdir -p $HOME/.claude-work

    # Symlink shared assets into each profile.
    # -s = symbolic  -f = overwrite if exists  -n = don't descend into dir target
    # Installing a plugin with either alias updates ~/.claude-shared/plugins/
    # and is immediately visible in both profiles.
    for profile in personal work; do
      ln -sfn $HOME/.claude-shared/plugins   $HOME/.claude-$profile/plugins
      if [ -f $HOME/.claude-shared/settings.json ]; then
        ln -sfn $HOME/.claude-shared/settings.json $HOME/.claude-$profile/settings.json
      fi

      # CLAUDE.md — only symlink if the shared one exists, so Claude Code can
      # create it fresh on first run if you haven't written one yet.
      if [ -f $HOME/.claude-shared/CLAUDE.md ]; then
        ln -sfn $HOME/.claude-shared/CLAUDE.md $HOME/.claude-$profile/CLAUDE.md
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

  # ── Zsh ───────────────────────────────────────────────────────

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    plugins = [
      {
        name = "fzf-tab";
        src = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
      }
    ];

    shellAliases = {
      ".."  = "cd ..";
      "..." = "cd ../..";
      ll    = "eza -la --icons --git";
      ls    = "eza --icons";
      lt    = "eza --tree --icons --level=2";
      cat   = "bat";

      # Git
      g     = "git";
      gs    = "git status";
      gc    = "git commit";
      gp    = "git push";
      gl    = "git log --oneline --graph --decorate -20";
      gd    = "git diff";
      lg    = "lazygit";

      # Nix rebuild
      rebuild = "sudo darwin-rebuild switch --flake ~/.config/nix-darwin";

      llmctx = "bash ~/.config/nix-darwin/scripts/repo2md.sh";

      start-venv = "source .venv/bin/activate";

      my-nix-clean = "sudo nix-collect-garbage --delete-older-than 15d";

      # In shellAliases:
      my-nix-update = "bash ~/.config/nix-darwin/scripts/update-select.sh";

      # SSH host picker (fzf-powered)
      sshp = "ssh-pick";

      tmux-pick = "tmux attach -t $(tmux ls | fzf --prompt=\"Session › \" | cut -d: -f1)";

    };

    initContent = lib.mkMerge [
      (lib.mkOrder 550 ''
        fpath+=/opt/homebrew/share/zsh/site-functions
      '')
      ''

        # microsandbox
        export PATH="$HOME/.local/bin:$PATH"

        # Tunnel helper
        tunnel-port() { ngrok http --domain=nonreducibly-unretrograded-danna.ngrok-free.dev "$1"; }

        # SSH host picker — parses ~/.ssh/config and fuzzy-selects a host
        ssh-pick() {
          local host
          host=$(
            grep -E "^Host " ~/.ssh/config 2>/dev/null \
              | grep -v '[*?]' \
              | awk '{print $2}' \
              | fzf --prompt="SSH › " \
                    --height=40% \
                    --border=rounded \
                    --preview='ssh -G {} 2>/dev/null | grep -E "^(hostname|user|port|identityfile) " | column -t' \
                    --preview-window=right:50%
          )
          [[ -n "$host" ]] && ssh "$host"
        }

        # Claude Code profiles — source the shared script so host shell
        # behaves identically to dev containers
        source $HOME/.config/claude-profiles/init.sh
      ''
    ];
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.carapace = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── Git ───────────────────────────────────────────────────────

  programs.git = {
    enable = true;

    settings = {
      user.name = "DebopamChowdhury";
      user.email = "debopamwork@gmail.com";
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      rerere.enabled = true;
      core.editor = "code --wait";
    };

    signing.format = null;  # Silence the signing format warning

    ignores = [
      ".DS_Store"
      "*.swp"
      ".direnv"
      ".envrc"
      "node_modules"
      ".idea"
      ".vscode"
    ];
  };

  # Delta (git diff pager) — now a separate program in home-manager
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
    };
  };

  # ── Starship Prompt ───────────────────────────────────────────

  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
      };
      directory = {
        truncation_length = 0;     # Show full path, never truncate
        truncate_to_repo  = false; # Don't collapse inside git repos either
        home_symbol       = "~";   # Keep ~ prefix for home subtree
      };
      git_branch.symbol = " ";
      nix_shell = {
        disabled = false;
        symbol = "❄️ ";
      };
    };
  };

  # ── Tmux ─────────────────────────────────────

  programs.tmux = {
    enable = true;
    mouse = true;
    keyMode = "vi";
    escapeTime = 0;
    extraConfig = ''
      set -s set-clipboard on
      set -g assume-paste-time 50

      # Unbind old shift-arrow bindings
      unbind S-Right
      unbind S-Down
      unbind S-Up

      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel
      bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel

      # Ctrl+b Ctrl+Shift+Right → vertical split
      bind-key C-S-Right split-window -h -c "#{pane_current_path}"
      # Ctrl+b Ctrl+Shift+Down → horizontal split
      bind-key C-S-Down split-window -v -c "#{pane_current_path}"
      # Ctrl+b Ctrl+Shift+Up → new window
      bind-key C-S-Up new-window -c "#{pane_current_path}"

      # Ctrl+b Shift+Left/Right → move window left/right
      bind-key S-Left swap-window -t -1 \; select-window -t -1
      bind-key S-Right swap-window -t +1 \; select-window -t +1

      # Ctrl+b Alt+Arrows → resize pane
      bind-key -r M-Up resize-pane -U 5
      bind-key -r M-Down resize-pane -D 5
      bind-key -r M-Left resize-pane -L 5
      bind-key -r M-Right resize-pane -R 5
    '';
  };

  # ── Bat (cat replacement) ─────────────────────────────────────

  programs.bat = {
    enable = true;
    config.theme = "TwoDark";
  };

  # ── Fzf ───────────────────────────────────────────────────────

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [ "--height 40%" "--border" ];
  };

  # ── Direnv (per-project environments) ─────────────────────────

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}