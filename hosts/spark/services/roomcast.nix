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
    lanAddress = "10.41.1.145";
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
