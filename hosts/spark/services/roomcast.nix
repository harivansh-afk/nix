{
  config,
  inputs,
  username,
  ...
}:
{
  imports = [ inputs.roomcast.nixosModules.default ];

  services.roomcast = {
    enable = true;
    lanInterface = "wlP9s9";
    rokuMac = "ec:9b:75:c0:3f:40";
    discoveryNetworks = [
      "10.41.1.0/24"
      "10.41.2.0/24"
    ];
    rokuAddress = "10.41.1.210";
    rokuSerial = "X04000ALK1SW";
  };

  users.users.${username}.extraGroups = [ "roomcast" ];
  systemd.services.hermes-agent.serviceConfig.SupplementaryGroups = [ "roomcast" ];
  systemd.services.hermes-backend.serviceConfig.SupplementaryGroups = [ "roomcast" ];

  services.hermes-agent.settings.mcp_servers.roomcast = {
    command = "${config.services.roomcast.package}/bin/roomcast-mcp";
  };
}
