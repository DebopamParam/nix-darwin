{ pkgs, ... }:

{
  # ── CLI Tools (from nixpkgs) ──────────────────────────────────
  # Only add tools here that you want system-wide for all users.
  # Dev-specific tools you already know — add/remove as you see fit.

  environment.systemPackages = with pkgs; [
    # Core utilities
    git
    gh
    curl
    wget
    ripgrep
    fd
    bat
    eza
    python313
    uv
    fzf
    jq
    yq
    tree
    htop
    tldr
    zoxide
    starship
    direnv
    tmux

    nodejs

    # Git TUI & better diffs
    lazygit
    delta

    # Nix tooling
    nixfmt

    # GNU replacements (macOS ships BSD variants)
    coreutils
    gnused
    gawk

    # Misc
    ffmpeg
    imagemagick
    mas           # Mac App Store CLI — needed for masApps
  ];

  nixpkgs.config.allowUnfree = true;
}
