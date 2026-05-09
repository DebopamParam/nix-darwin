{ username, ... }:

{
  # ── Primary User (required by recent nix-darwin) ───────────────

  system.primaryUser = username;

  # ── Shell ─────────────────────────────────────────────────────

  programs.zsh.enable = true;

  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # ── User Account ───────────────────────────────────────────────

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };
}
