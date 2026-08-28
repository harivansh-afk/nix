# muxd on the macbook: a launchd user agent from the mux flake's darwin
# module, the same ownership spark gives it under systemd
# (hosts/spark/services/muxd.nix). The daemon's environment is launchd's,
# never a shell's, so nothing a pane inherits depends on who last started
# it. A muxd bump is a switch: launchd has no MAINPID handoff, so the
# agent restarts and open panes go with it (the module header in mux's
# nix/darwin.nix explains the trade).
{ inputs, username, ... }:
{
  imports = [ inputs.mux.darwinModules.muxd ];

  services.muxd = {
    enable = true;
    home = "/Users/${username}";
  };
}
