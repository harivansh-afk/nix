{
  config,
  lib,
  hostConfig,
  ...
}:
lib.mkIf hostConfig.isDarwin {
  activationLines = ''
    karabiner_link="${config.homeDirectory}/.config/karabiner"
    karabiner_src="${config.homeDirectory}/Documents/Git/nix/dots/karabiner"

    if [ -L "$karabiner_link" ]; then
      current_target="$(readlink "$karabiner_link")"
      if [ "$current_target" != "$karabiner_src" ]; then
        rm -f "$karabiner_link"
        ln -s "$karabiner_src" "$karabiner_link"
      fi
    elif [ -d "$karabiner_link" ]; then
      rm -rf "$karabiner_link"
      ln -s "$karabiner_src" "$karabiner_link"
    elif [ ! -e "$karabiner_link" ]; then
      ln -s "$karabiner_src" "$karabiner_link"
    fi
  '';
}
