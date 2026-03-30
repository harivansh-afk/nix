{ lib, ... }:
{
  # Transitional cleanup for files previously owned by ~/dots. Keeping this
  # separate from steady-state modules makes it obvious what can be deleted
  # once every managed path has been fully handed over to Home Manager.
  home.activation.removeLegacyZshLinks = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    for path in "$HOME/.zshenv" "$HOME/.zshrc"; do
      if [ -L "$path" ]; then
        target="$(readlink "$path")"
        case "$target" in
          dots/zsh/*|"$HOME"/dots/zsh/*)
            rm -f "$path"
            ;;
        esac
      fi
    done
  '';

  home.activation.removeLegacyTmuxLink = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    path="$HOME/.config/tmux/tmux.conf"
    if [ -L "$path" ]; then
      target="$(readlink "$path")"
      case "$target" in
        ../../dots/tmux/*|dots/tmux/*|"$HOME"/dots/tmux/*)
          rm -f "$path"
          ;;
      esac
    fi
  '';
}
