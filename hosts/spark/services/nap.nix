# The nap cast receiver (see AGENTS.md "Casting"): napd session control
# plus the moonlight kiosk on tty1. Bound to the tailnet address; tailnet
# traffic bypasses the NixOS firewall via tailscaled's own netfilter
# rules, the same trust boundary mosh relies on.
{ inputs, ... }:
{
  imports = [ inputs.nap.nixosModules.receiver ];

  services.nap.receiver = {
    enable = true;
    bind = "100.114.116.11:46270";
  };
}
