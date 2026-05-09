{ private, ... }:

{
  # ── Git ───────────────────────────────────────────────────────

  programs.git = {
    enable = true;

    settings = {
      user.name = private.git.name;
      user.email = private.git.email;
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
}
