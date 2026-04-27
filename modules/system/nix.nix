{ ... }:

{
  # ── Nix Settings ──────────────────────────────────────────────
  # Determinate Systems installer manages the Nix daemon,
  # so we disable nix-darwin's Nix management.

  nix.enable = false;

  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";
}
