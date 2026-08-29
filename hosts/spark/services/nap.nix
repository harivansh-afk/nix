# nap cast receiver (AGENTS.md "Casting"): napd plus the moonlight kiosk on
# tty1, bound to the tailnet address.
{ inputs, ... }:
{
  imports = [ inputs.nap.nixosModules.receiver ];

  services.nap.receiver = {
    enable = true;
    bind = "100.114.116.11:46270";
  };
}
