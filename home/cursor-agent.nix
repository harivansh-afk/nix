{
  config,
  lib,
  pkgs,
  ...
}:
let
  installUrl = "https://cursor.com/install";
  cursorAgentBin = "${config.home.homeDirectory}/.local/bin/cursor-agent";
  installPath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.curl
    pkgs.gnutar
  ];
in
{
  home.activation.installCursorAgent = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${installPath}:$PATH"

    if [ ! -x "${cursorAgentBin}" ]; then
      "${pkgs.curl}/bin/curl" -fsS ${lib.escapeShellArg installUrl} | "${pkgs.bash}/bin/bash"
    fi
  '';
}
