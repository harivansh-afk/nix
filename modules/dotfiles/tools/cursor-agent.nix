{
  config,
  lib,
  pkgs,
  ...
}:
let
  installUrl = "https://cursor.com/install";
  cursorAgentBin = "${config.homeDirectory}/.local/bin/cursor-agent";
  installPath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.curl
    pkgs.gnutar
    pkgs.gzip
  ];
in
{
  activationLines = ''
    export HOME=${lib.escapeShellArg config.homeDirectory}
    export PATH="${installPath}:$PATH"

    if [ ! -x ${lib.escapeShellArg cursorAgentBin} ]; then
      if ! "${pkgs.curl}/bin/curl" -fsS ${lib.escapeShellArg installUrl} | "${pkgs.bash}/bin/bash"; then
        echo "warning: cursor-agent install failed; will retry on next switch" >&2
      fi
    fi
  '';
}
