{ config, inputs, ... }:
{
  imports = [ inputs.airplay-at-the-crib.nixosModules.default ];

  services.airplay-beacon = {
    enable = true;
    address = config.services.roomcast.rokuAddress;
    serial = config.services.roomcast.rokuSerial;
    mac = config.services.roomcast.rokuMac;
    lanInterface = config.services.roomcast.lanInterface;
    discoveryNetworks = config.services.roomcast.discoveryNetworks;
  };
}
