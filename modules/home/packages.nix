{ pkgs, private, ... }:

{
  home.stateVersion = "24.11";
  home.username = private.username;
  home.homeDirectory = "/Users/${private.username}";

  # ── User Packages ─────────────────────────────────────────────

  home.packages = with pkgs; [
    # Add user-specific packages here if needed
  ];
}
