{
  lib,
  pkgs,
  theme,
  ...
}:
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
          set -g status-right ""
        '';
      }
    ];
    extraConfig = ''
      set -g prefix C-b
      bind C-b send-prefix

      set -g mouse on

      # Selection bindings run tmux-clip-relay after copy-selection. tmux's
      # set-clipboard=on re-emits OSC 52 only when an inner pane app originates
      # the sequence; it does not re-emit when tmux's own copy-selection fills
      # a buffer. Without this explicit relay, mouse drag / double-click /
      # triple-click would fill the tmux buffer but never reach the local
      # system clipboard. The helper reads the top buffer and writes
      # `\e]52;c;<base64>\a` straight to the connected client's TTY.
      bind -n DoubleClick1Pane select-pane \; copy-mode -M \; send-keys -X select-word \; run-shell -d 0.3 \; send-keys -X copy-selection \; run-shell "$HOME/.local/bin/tmux-clip-relay" \; send-keys -X clear-selection
      bind -n TripleClick1Pane select-pane \; copy-mode -M \; send-keys -X select-line \; run-shell -d 0.3 \; send-keys -X copy-selection \; run-shell "$HOME/.local/bin/tmux-clip-relay" \; send-keys -X clear-selection
      bind -T copy-mode DoubleClick1Pane select-pane \; send-keys -X select-word \; run-shell -d 0.3 \; send-keys -X copy-selection \; run-shell "$HOME/.local/bin/tmux-clip-relay" \; send-keys -X clear-selection
      bind -T copy-mode TripleClick1Pane select-pane \; send-keys -X select-line \; run-shell -d 0.3 \; send-keys -X copy-selection \; run-shell "$HOME/.local/bin/tmux-clip-relay" \; send-keys -X clear-selection
      bind -T copy-mode MouseDragEnd1Pane send-keys -X copy-selection \; run-shell "$HOME/.local/bin/tmux-clip-relay" \; send-keys -X clear-selection

      bind -T copy-mode    WheelDownPane send-keys -X scroll-down-and-cancel
      bind -T copy-mode-vi WheelDownPane send-keys -X scroll-down-and-cancel
      bind -T copy-mode    Down send-keys -X cursor-down \; if -F '#{==:#{scroll_position},0}' 'send-keys -X cancel'
      bind -T copy-mode-vi Down send-keys -X cursor-down \; if -F '#{==:#{scroll_position},0}' 'send-keys -X cancel'
      bind -T copy-mode-vi j    send-keys -X cursor-down \; if -F '#{==:#{scroll_position},0}' 'send-keys -X cancel'

      set -g default-terminal "tmux-256color"
      set -s extended-keys on
      set -s extended-keys-format csi-u
      set -as terminal-features 'xterm*:extkeys'
      set -as terminal-features 'xterm*:RGB'
      # Mosh rewrites TERM to xterm-256color (sometimes screen) because the
      # mosh-server build does not know Ghostty's terminfo. The xterm* glob
      # above covers the mosh case; this line covers the screen fallback so
      # true-color theme accents do not get quantised to the 256-palette.
      set -as terminal-features 'screen*:RGB'

      # OSC 52 clipboard through mosh. mosh-server 1.4 only accepts the
      # `c` (CLIPBOARD) selector; every other selector (PRIMARY, s0, empty)
      # is silently dropped by mosh-server. Force tmux's Ms capability to
      # always emit `\e]52;c;<base64>\a` so copy-mode and inner-app OSC 52
      # both survive the stack (local terminal -> mosh -> tmux -> shell).
      # set-clipboard on makes tmux relay via Ms instead of only buffering.
      # Refs:
      #   tmux/tmux#3423 (tmux interferes with OSC 52 when running in mosh)
      #   mobile-shell/mosh#1054 (broaden accepted OSC 52 forms)
      #   mobile-shell/mosh#1104 (additional clipboard selectors)
      set -g set-clipboard on
      set -ag terminal-overrides ',*:Ms=\E]52;c;%p2%s\7'

      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      bind H switch-client -p \; refresh-client -S
      bind J switch-client -n \; refresh-client -S
      bind K switch-client -p \; refresh-client -S
      bind L switch-client -n \; refresh-client -S

      bind f display-popup -w 80% -h 80% -E "\
        tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{session_name}/#{window_name} [#{pane_current_command}] #{pane_current_path}' \
        | fzf --reverse \
          --preview 'tmux capture-pane -ep -t {1}' \
          --preview-window right:60% \
        | awk '{print \$1}' \
        | xargs tmux switch-client -t"

      set -g automatic-rename on
      set -g automatic-rename-format '#{b:pane_current_path}'

      set-option -g base-index 1
      set-option -g pane-base-index 1
      set-option -g renumber-windows on

      set-option -g history-limit 100000

      set-option -g set-titles on
      set-option -g set-titles-string "#{pane_title}"

      bind c new-window -c "#{pane_current_path}"
      bind - split-window -c "#{pane_current_path}"
      bind "'" split-window -h -c "#{pane_current_path}"
      bind M command-prompt -p "move pane to window:" "join-pane -t '%%'"
      bind < join-pane -t :-
      bind > join-pane -t :+

      set-option -s focus-events on
      set-option -s extended-keys on

      set-option -s escape-time 0

      set-option -g prompt-cursor-colour default
      set-option -g pane-border-lines single
      set-option -g pane-border-status bottom
      set-option -g pane-border-format ""
      set-option -g status-position bottom
      set-option -g status-justify left
      set-option -g status-left ""
      set-option -ga status-right "#(~/.config/tmux/session-list.sh)"
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
          printf ' #[bold,fg=%s]*#[nobold,fg=default]%s ' "$accent" "$s"
        else
          printf ' %s ' "$s"
        fi
      done
    '';
  };

  # OSC 52 relay invoked by the copy-mode bindings above. Reads the current
  # tmux paste buffer and writes `\e]52;c;<base64>\a` directly to the
  # connected client's TTY. This is the path that makes mouse-drag and
  # double/triple-click selections land on the local system clipboard when
  # connected over mosh.
  home.file.".local/bin/tmux-clip-relay" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      client_tty="$(tmux display-message -p '#{client_tty}')"
      [ -n "$client_tty" ] || exit 0
      data="$(tmux save-buffer - | base64 -w0)"
      printf '\033]52;c;%s\a' "$data" > "$client_tty"
    '';
  };
}
