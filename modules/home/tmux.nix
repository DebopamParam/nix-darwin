{ ... }:

{
  # ── Tmux ─────────────────────────────────────

  programs.tmux = {
    enable = true;
    mouse = true;
    keyMode = "vi";
    escapeTime = 0;
    extraConfig = ''
      set -s set-clipboard on
      set -g assume-paste-time 50

      # Unbind old shift-arrow bindings
      unbind S-Right
      unbind S-Down
      unbind S-Up

      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel
      bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel

      # Ctrl+b Ctrl+Shift+Right → vertical split
      bind-key C-S-Right split-window -h -c "#{pane_current_path}"
      # Ctrl+b Ctrl+Shift+Down → horizontal split
      bind-key C-S-Down split-window -v -c "#{pane_current_path}"
      # Ctrl+b Ctrl+Shift+Up → new window
      bind-key C-S-Up new-window -c "#{pane_current_path}"

      # Ctrl+b Shift+Left/Right → move window left/right
      bind-key S-Left swap-window -t -1 \; select-window -t -1
      bind-key S-Right swap-window -t +1 \; select-window -t +1

      # Ctrl+b Alt+Arrows → resize pane
      bind-key -r M-Up resize-pane -U 5
      bind-key -r M-Down resize-pane -D 5
      bind-key -r M-Left resize-pane -L 5
      bind-key -r M-Right resize-pane -R 5
    '';
  };
}
