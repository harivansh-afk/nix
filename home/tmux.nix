{
  config,
  lib,
  pkgs,
  ...
}:
let
  theme = import ../lib/theme.nix { inherit config; };
in
{
  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [
      resurrect
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '5'
        '';
      }
    ];
    extraConfig = ''
      # custom

      # Set prefix to C-b (default)
      set -g prefix C-b
      bind C-b send-prefix

      set -g mouse on

      # Enable extended keys so Shift+Enter and other modified keys work
      set -g default-terminal "tmux-256color"
      set -s extended-keys on
      set -as terminal-features 'xterm*:extkeys'
      set -as terminal-features 'xterm-ghostty:RGB'

      # Use Vim-style pane navigation (prefix + h/j/k/l)
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Switch sessions with prefix + H/J/K/L (capital)
      bind H switch-client -p
      bind J switch-client -n
      bind K switch-client -p
      bind L switch-client -n

      # fzf pane switcher
      bind f display-popup -w 80% -h 80% -E "\
        tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{session_name}/#{window_name} [#{pane_current_command}] #{pane_current_path}' \
        | fzf --reverse \
          --preview 'tmux capture-pane -ep -t {1}' \
          --preview-window right:60% \
        | awk '{print \$1}' \
        | xargs tmux switch-client -t"

      # Auto-rename windows to the current directory basename
      set -g automatic-rename on
      set -g automatic-rename-format '#{b:pane_current_path}'

      # Start all numbering at 1 instead of 0 for better key reachability
      set-option -g base-index 1
      set-option -g pane-base-index 1
      set-option -g renumber-windows on

      # Increase history limit, as we want an "almost" unlimited buffer.
      set-option -g history-limit 100000

      # Fix Terminal Title display, to not contain tmux specific information
      set-option -g set-titles on
      set-option -g set-titles-string "#{pane_title}"

      # Open new windows and panes in the current working directory of the active pane.
      bind c new-window -c "#{pane_current_path}"
      bind - split-window -c "#{pane_current_path}"
      bind "'" split-window -h -c "#{pane_current_path}"

      # Enable support for terminal focus and extended keys.
      set-option -s focus-events on
      set-option -s extended-keys on

      # Disable waiting time when pressing escape, for smoother Neovim usage.
      set-option -s escape-time 0

      set-option -g prompt-cursor-colour default
      set-option -g status-position bottom
      set-option -g status-justify left
      set-option -g status-left ""
      set-option -g status-right "#(~/.config/tmux/session-list.sh)"
      set-option -g status-left-length 100
      set-option -g status-right-length 100
      source-file "${theme.paths.tmuxCurrentFile}"
    '';
  };

  home.file.".config/tmux/session-list.sh" = {
    executable = true;
    text = ''
      #!/bin/sh
      current=$(tmux display-message -p '#S')
      accent=$(tmux show -gv @cozybox-accent 2>/dev/null || printf '#d3869b')
      tmux list-sessions -F '#S' | while IFS= read -r s; do
        if [ "$s" = "$current" ]; then
          printf ' #[fg=%s]*#[fg=default]%s ' "$accent" "$s"
        else
          printf ' %s ' "$s"
        fi
      done
    '';
  };
}
