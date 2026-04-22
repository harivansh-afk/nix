{
  config,
  lib,
  ...
}:
{
  # Karabiner-Elements destroys file-level symlinks (unlink + rewrite), but
  # directory-level symlinks survive.  Point ~/.config/karabiner at the repo
  # directory so changes are tracked in git and Karabiner can write freely.
  home.activation.karabinerConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    karabiner_link="${config.home.homeDirectory}/.config/karabiner"
    karabiner_src="${config.home.homeDirectory}/Documents/GitHub/nix/dots/karabiner"

    if [ -L "$karabiner_link" ]; then
      current_target="$(readlink "$karabiner_link")"
      if [ "$current_target" != "$karabiner_src" ]; then
        rm -f "$karabiner_link"
        ln -s "$karabiner_src" "$karabiner_link"
      fi
    elif [ -d "$karabiner_link" ]; then
      rm -rf "$karabiner_link"
      ln -s "$karabiner_src" "$karabiner_link"
    else
      ln -s "$karabiner_src" "$karabiner_link"
    fi
  '';
}
