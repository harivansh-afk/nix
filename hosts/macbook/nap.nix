# The nap cast sender (see AGENTS.md "Casting"): supervisor + sunshine
# launchd agents, /etc/nap/config.toml, DeskPad built from pinned source.
# Control rides the tailnet to napd on spark; video stays on the LAN.
{ inputs, ... }:
{
  imports = [ inputs.nap.darwinModules.sender ];

  services.nap.sender = {
    enable = true;
    receiver = "http://100.114.116.11:46270";
  };
}
