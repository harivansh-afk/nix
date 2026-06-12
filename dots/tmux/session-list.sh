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
