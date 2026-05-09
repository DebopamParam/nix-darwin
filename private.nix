{
  # ─────────────────────────────────────────────────────────────
  #  Per-machine values. Edit locally — DO NOT COMMIT real values.
  #
  #  This file is tracked by git (because Nix flakes only see
  #  tracked files), but is marked `skip-worktree` so local edits
  #  stay out of `git status`. See README → "Privacy & local edits".
  # ─────────────────────────────────────────────────────────────

  username = "yourusername";              # whoami
  hostname = "Your-MacBook-Pro";          # scutil --get LocalHostName
  system   = "aarch64-darwin";            # or "x86_64-darwin" for Intel

  git = {
    name  = "Your Name";
    # Recommended: GitHub's noreply alias to keep your real email private:
    #   <id>+<username>@users.noreply.github.com
    email = "you@example.com";
  };

  # Optional: reserved ngrok free domain used by `tunnel-port`.
  # Leave as "" to let ngrok assign a random domain on each tunnel.
  ngrokDomain = "";
}
