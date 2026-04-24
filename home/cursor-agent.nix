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
    pkgs.gzip
  ];
in
{
  # The upstream installer is an impure curl|bash. Keep it best-effort so a
  # transient network blip during activation doesn't break `nixos-rebuild
  # switch` / `darwin-rebuild switch`; cursor-agent will just retry on the
  # next switch.
  home.activation.installCursorAgent = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH="${installPath}:$PATH"

    if [ ! -x "${cursorAgentBin}" ]; then
      if ! "${pkgs.curl}/bin/curl" -fsS ${lib.escapeShellArg installUrl} | "${pkgs.bash}/bin/bash"; then
        echo "warning: cursor-agent install failed; will retry on next switch" >&2
      fi
    fi
  '';
}
