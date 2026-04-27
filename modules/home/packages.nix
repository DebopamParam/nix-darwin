{ pkgs, ... }:

{
  home.stateVersion = "24.11";
  home.username = "debopamchowdhury";
  home.homeDirectory = "/Users/debopamchowdhury";

  # ── User Packages ─────────────────────────────────────────────

  home.packages = with pkgs; [
    # Add user-specific packages here if needed
  ];
}
