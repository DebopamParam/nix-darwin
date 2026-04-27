{ username, ... }:

{
  # ── Primary User (required by recent nix-darwin) ───────────────

  system.primaryUser = "debopamchowdhury";

  # ── Shell ─────────────────────────────────────────────────────

  programs.zsh.enable = true;

  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # ── User Account ───────────────────────────────────────────────

  users.users.debopamchowdhury = {
    name = "debopamchowdhury";
    home = "/Users/debopamchowdhury";
  };
}
