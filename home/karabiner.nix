{
  config,
  lib,
  ...
}: {
  # Karabiner-Elements destroys symlinks (unlink + rewrite), so we cannot use
  # xdg.configFile.  Instead, copy the file on every activation so Karabiner
  # sees a real mutable file whose contents match our nix-managed source.
  home.activation.karabinerConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    karabiner_dir="${config.home.homeDirectory}/.config/karabiner"
    mkdir -p "$karabiner_dir"
    cp -f "${../config/karabiner/karabiner.json}" "$karabiner_dir/karabiner.json"
    chmod 600 "$karabiner_dir/karabiner.json"
  '';
}
