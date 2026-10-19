{ inputs, ... }:
{
  imports = [ inputs.mux.nixosModules.muxd ];

  services.muxd = {
    enable = true;
    audio.enable = true;

    user = "rathi";
    listen = "0.0.0.0:4433";
    openFirewall = true;
  };
}
