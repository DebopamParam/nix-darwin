{ pkgs, username, ... }:

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

  # ── Nix Settings ──────────────────────────────────────────────
  # Determinate Systems installer manages the Nix daemon,
  # so we disable nix-darwin's Nix management.

  nix.enable = false;

  nixpkgs.config.allowUnfree = true;

  # ── Primary User (required by recent nix-darwin) ───────────────

  system.primaryUser = "debopamchowdhury";

  # ── Shell ─────────────────────────────────────────────────────

  programs.zsh.enable = true;

  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # ── macOS System Settings ─────────────────────────────────────
  # These are applied on every `darwin-rebuild switch`.
  # Equivalent to changing things in System Settings, but declarative.

  system.defaults = {

    dock = {
      autohide = false;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.4;
      orientation = "bottom";
      tilesize = 48;
      show-recents = false;
      mru-spaces = false;
      minimize-to-application = true;
    };

    finder = {
      AppleShowAllFiles = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXPreferredViewStyle = "clmv";  # Column view (like the video creator!)
      FXDefaultSearchScope = "SCcf";  # Search current folder
      _FXShowPosixPathInTitle = true;
    };

    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      AppleInterfaceStyle = "Dark";
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      InitialKeyRepeat = 68;
      KeyRepeat = 6;
      "com.apple.swipescrolldirection" = true;
    };

    trackpad = {
      Clicking = true;                # Tap to click
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };

    loginwindow.GuestEnabled = false;

    screencapture = {
      location = "~/Pictures/Screenshots";
      type = "png";
    };

    menuExtraClock.Show24Hour = true;
  };

  # ── User Account ───────────────────────────────────────────────

  users.users.debopamchowdhury = {
    name = "debopamchowdhury";
    home = "/Users/debopamchowdhury";
  };

  # ── System Metadata ───────────────────────────────────────────

  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";
}