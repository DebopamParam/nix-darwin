{ pkgs, lib, private, ... }:

{
  # ── Zsh ───────────────────────────────────────────────────────

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # Login-shell setup (generated into ~/.zprofile, managed by home-manager).
    # Migrated from the pre-existing ~/.zprofile created by the Homebrew
    # installer and OrbStack.
    profileExtra = ''
      # Homebrew (Apple Silicon) — puts /opt/homebrew/bin on PATH, sets MANPATH, etc.
      eval "$(/opt/homebrew/bin/brew shellenv)"

      # OrbStack: command-line tools and integration
      source ~/.orbstack/shell/init.zsh 2>/dev/null || :
    '';

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

      # Claude config sync
      sync-claude  = "bash ~/.config/nix-darwin/scripts/sync-claude-config.sh";
      apply-claude = "bash ~/.config/nix-darwin/scripts/sync-claude-config.sh --apply";

      # Sync obsidian
      sync-obsidian = "bash ~/Documents/turboml-docs/sync-to-obsidian.sh";

      llmctx = "bash ~/.config/nix-darwin/scripts/repo2md.sh";

      # Expose a local port via ngrok or Cloudflare (see scripts/tunnel-port.sh)
      tunnel-port = "bash ~/.config/nix-darwin/scripts/tunnel-port.sh";

      # Zip current dir into ./<dir>.zip, honoring .gitignore
      repo-to-zip = "bash ~/.config/nix-darwin/scripts/repo-to-zip.sh";

      start-venv = "source .venv/bin/activate";

      my-machine-clean = "bash ~/.config/nix-darwin/scripts/machine-clean.sh";

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

        # Tunnel helper config — values from private.nix, consumed by
        # scripts/tunnel-port.sh (aliased to `tunnel-port`).
        export TUNNEL_CF_DOMAIN="${private.cfDomain}"
        export TUNNEL_CF_NAME="${private.cfTunnel}"
        export TUNNEL_NGROK_DOMAIN="${private.ngrokDomain}"

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
}
