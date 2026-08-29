# muxd as a launchd user agent from the mux flake's darwin module (spark
# runs it under systemd). A muxd bump restarts the agent and open panes go
# with it; launchd has no MAINPID handoff.
{ inputs, username, ... }:
{
  imports = [ inputs.mux.darwinModules.muxd ];

  services.muxd = {
    enable = true;
    home = "/Users/${username}";
  };
}
