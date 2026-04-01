{ pkgs, ... }:

{
  home.stateVersion = "24.11";
  home.username = "debopamchowdhury";
  home.homeDirectory = "/Users/debopamchowdhury";

  # ── User Packages ─────────────────────────────────────────────

  home.packages = with pkgs; [
    # Add user-specific packages here if needed
  ];

  # ── Zsh ───────────────────────────────────────────────────────

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

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

      start-venv = "source .venv/bin/activate";
    };

    # initExtra renamed to initContent in newer home-manager
    initContent = ''
      # Starship prompt
      eval "$(starship init zsh)"

      # Zoxide (smarter cd)
      eval "$(zoxide init zsh)"

      # direnv
      eval "$(direnv hook zsh)"

      # fzf keybindings
      source <(fzf --zsh)

      # microsandbox
      export PATH="$HOME/.local/bin:$PATH"

      # Tunnel helper
      tunnel-port() { ngrok http --domain=nonreducibly-unretrograded-danna.ngrok-free.dev "$1"; }

      # llmctx — generate context.md from current directory
      llmctx() {
        local out="context.md"
        echo -e "# File Tree\n\`\`\`\n$(find . -type f ! -name "$out" ! -path "./.git/*" | sort)\n\`\`\`\n" > "$out"
        find . -type f ! -name "$out" ! -path "./.git/*" | sort | while read -r file; do
          file "$file" | grep -qv "text" && continue
          echo -e "## \`$file\`\n\`\`\`\n$(cat "$file")\n\`\`\`\n" >> "$out"
        done
        echo "Done! $out created with $(wc -l < "$out") lines"
      }
    '';
  };

  # ── Git ───────────────────────────────────────────────────────
  # Options have been renamed in newer home-manager:
  #   userName/userEmail → settings.user.name/email
  #   extraConfig        → settings
  #   delta.*            → programs.delta.*

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
      directory.truncation_length = 3;
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

  # ── Direnv (per-project environments) ─────────────────────────

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}