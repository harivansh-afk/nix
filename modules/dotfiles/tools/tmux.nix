{
  pkgs,
  lib,
  theme,
  ...
}:
let
  resurrectPlugin = pkgs.tmuxPlugins.resurrect;
  continuumPlugin = pkgs.tmuxPlugins.continuum;

  pluginsSection = ''
    # plugin: resurrect
    run-shell ${resurrectPlugin}/share/tmux-plugins/resurrect/resurrect.tmux

    # plugin: continuum (with extraConfig set before run-shell)
    set -g @continuum-restore 'on'
    set -g @continuum-save-interval '5'
    set -g status-right ""
    run-shell ${continuumPlugin}/share/tmux-plugins/continuum/continuum.tmux
  '';

  extraConfig = ''
    set -g prefix C-b
    bind C-b send-prefix

    set -g mouse on

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
    set -as terminal-features 'screen*:RGB'

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

  tmuxConf = pluginsSection + "\n" + extraConfig;

  sessionListSh = pkgs.writeShellScript "session-list" ''
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

  tmuxClipRelay = pkgs.writeShellScript "tmux-clip-relay" ''
    set -euo pipefail
    client_tty="$(tmux display-message -p '#{client_tty}')"
    [ -n "$client_tty" ] || exit 0
    data="$(tmux save-buffer - | base64 -w0)"
    printf '\033]52;c;%s\a' "$data" > "$client_tty"
  '';
in
{
  packages = [ pkgs.tmux ];

  files.".config/tmux/tmux.conf".text = tmuxConf;
  files.".config/tmux/session-list.sh".source = sessionListSh;
  files.".local/bin/tmux-clip-relay".source = tmuxClipRelay;
}
