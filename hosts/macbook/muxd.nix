{
  config,
  inputs,
  lib,
  pkgs,
  username,
  ...
}:
let
  tailnet = import ../../lib/tailnet.nix;
in
{
  imports = [ inputs.mux.darwinModules.muxd ];

  services.muxd = {
    enable = true;
    home = "/Users/${username}";
  };

  environment.systemPackages = [ config.services.muxd.package ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    sudo -H -u ${username} ${pkgs.bash}/bin/bash -c '
      set -eu
      hosts="$HOME/.config/mux/hosts.json"
      mkdir -p "''${hosts%/*}"
      [ -e "$hosts" ] || echo "{}" > "$hosts"
      tmp="$(mktemp "$hosts.XXXXXX")"
      ${pkgs.jq}/bin/jq ".spark.addr = \"spark.${tailnet.domain}:4433\"" "$hosts" > "$tmp"
      mv "$tmp" "$hosts"
    '
  '';
}
