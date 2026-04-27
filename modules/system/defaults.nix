{ ... }:

{
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
}
