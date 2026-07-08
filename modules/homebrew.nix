{ ... }:

{
  homebrew = {
    enable = true;

    onActivation = {
      # true = refresh brew metadata on every activation. Keeps installs
      # current but makes rebuilds slower and less reproducible; set to
      # false to update only deliberately (via `my-nix-update`).
      autoUpdate = true;
      upgrade = false;
      # "zap" = full declarative control: anything NOT declared below is
      # uninstalled on rebuild AND its app data removed (per the cask's
      # zap stanza). Add a cask here before installing it, never ad-hoc.
      cleanup = "zap";
    };

    taps = [];

    brews = [
      # CLI tools better installed via brew than nix (if any)
      "rtk"
      "opencode"
    ];

    # ── GUI Applications (Homebrew Casks) ───────────────────────

    casks = [
      # ── Browsers ──
      "arc"
      "brave-browser"

      # ── AI Tools ──
      "claude"                   # Claude desktop app
      "claude-code@latest"       # Claude Code CLI
      "codex-app"                # Codex desktop GUI app
      "codex"                    # Codex terminal CLI (provides `codex` on PATH)
      "ollama-app"

      # ── Editors ──
      "visual-studio-code"
      "cursor"

      # ── Dev: Containers / Databases / Networking ──
      "orbstack"
      "redis-insight"
      "pgadmin4"
      "mongodb-compass"
      "dbeaver-community"
      "ngrok"

      # ── Terminals ──
      "ghostty"

      # ── Productivity / Launchers ──
      "raycast"                 # Spotlight replacement — try native Spotlight first if you want
      "obsidian"                # Markdown notes / second brain

      # ── Window Management & Alt-Tab ──
      "alt-tab"                 # Windows-style Alt+Tab with window previews
      "rectangle"               # Keyboard-driven window snapping

      # ── Menu Bar ──
      "jordanbaird-ice"         # Hide menu bar clutter (free, open source)
      "stats"                   # System monitor in menu bar

      # ── Remote Access / File Transfer ──
      "rustdesk"
      "cyberduck"

      # ── Utilities ──
      "the-unarchiver"          # RAR, 7z, etc.
      "appcleaner"              # Clean uninstall apps
      "monitorcontrol"          # External display brightness via keyboard
      "linearmouse"             # Per-device mouse/trackpad settings

      # ── Communication ──
      "slack"
      "discord"

      # ── Media ──
      "iina"                    # Best video player for Mac
      "vlc"

      # ── Quick Look plugins ──
      "qlmarkdown"
      "syntax-highlight"

      # ── Notch (candidates, not installed) ──
      # "notchnook"             # Turn the notch into a utility hub
      # Alternative (free): install BoringNotch manually
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
