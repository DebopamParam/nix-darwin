{ ... }:

{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;       # Don't slow down every rebuild
      upgrade = false;
      # ⚠️  START WITH "none" — this prevents nuking your existing brew packages
      #     on the first run. Once you've added everything you need to this
      #     config, change to "zap" for full declarative control.
      cleanup = "none";
    };

    taps = [];

    brews = [
      # CLI tools better installed via brew than nix (if any)
      "rtk"
    ];

    # ── GUI Applications (Homebrew Casks) ───────────────────────

    casks = [
      # ── Browsers ──
      "arc"
      "firefox"
      "linearmouse"

      "claude-code@latest"

      "brave-browser"

      "orbstack"

      # ── Productivity / Launchers ──
      "raycast"                 # Spotlight replacement — try native Spotlight first if you want
      "obsidian"                # Markdown notes / second brain

      # ── Window Management & Alt-Tab ──
      "alt-tab"                 # Windows-style Alt+Tab with window previews
      "rectangle"               # Keyboard-driven window snapping

      # ── Menu Bar ──
      "jordanbaird-ice"         # Hide menu bar clutter (free, open source)
      "stats"                   # System monitor in menu bar

      "visual-studio-code"

      "ngrok"

      # ── Notch ──
      # "notchnook"               # Turn the notch into a utility hub
      # Alternative (free): install BoringNotch manually or via:

      # ── Terminals ──
      "ghostty"

      # -- mongodb --
      "mongodb-compass"

      # ── Utilities ──
      "the-unarchiver"          # RAR, 7z, etc.
      "appcleaner"              # Clean uninstall apps
      "monitorcontrol"          # External display brightness via keyboard

      # ── Communication ──
      "slack"
      "discord"

      # ── Media ──
      "iina"                    # Best video player for Mac
      "vlc"

      # ── Quick Look plugins ──
      "qlmarkdown"
      "syntax-highlight"

      # ── Add your existing brew casks below ──
      # Run `brew list --cask` to see what you currently have installed.
      # Add them here so they survive when you switch cleanup to "zap".
    ];

    # ── Mac App Store Apps ──────────────────────────────────────
    # You MUST be signed into the App Store.
    # Find IDs with: mas search "App Name"
    # Or from the App Store URL (the number after /id).

    masApps = {
      # ── Utilities ──
      # "Amphetamine"       = 937984704;    # Keep Mac awake
      # "Hidden Bar"        = 1452453066;   # Hide menu bar icons (alternative to Ice)
      # "Hand Mirror"       = 1502839586;   # Quick camera check from menu bar

      # ── Add your own below ──
      # "App Name"        = 123456789;
    };
  };
}
