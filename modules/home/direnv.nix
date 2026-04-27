{ ... }:

{
  # ── Direnv (per-project environments) ─────────────────────────

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
