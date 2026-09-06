{
  config,
  inputs,
  lib,
  pkgs,
  username,
  ...
}:
let
  cfg = config.services.roomcast;
  mcpPort = 18796;
  mcpPython = pkgs.python3.withPackages (ps: [
    (ps.toPythonModule cfg.package)
    ps.uvicorn
  ]);
  egressRules = pkgs.writeText "roomcast-egress.nft" ''
    destroy table inet roomcast
    table inet roomcast {
      chain output {
        type filter hook output priority -5; policy accept;
        ip daddr 127.0.0.1 tcp dport ${toString mcpPort} meta skuid != { 0, ${
          toString config.users.users.${username}.uid
        } } reject
        meta skuid != "roomcast" return
        tcp sport ${toString cfg.port} return
        ip daddr 127.0.0.53 udp dport 53 return
        ip daddr 127.0.0.53 tcp dport 53 return
        oifname "${cfg.lanInterface}" ip daddr 239.255.255.250 udp dport 1900 return
        ${lib.concatMapStringsSep "\n" (network: ''
          oifname "${cfg.lanInterface}" ip daddr ${network} tcp dport 8060 return
        '') cfg.discoveryNetworks}
        ip daddr { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 198.18.0.0/15, 224.0.0.0/4, 240.0.0.0/4 } drop
        meta nfproto ipv4 tcp dport 443 return
        ip6 daddr 2000::/3 tcp dport 443 return
        drop
      }
    }
  '';
in
{
  imports = [ inputs.roomcast.nixosModules.default ];

  networking.firewall.extraCommands = ''
    ${pkgs.nftables}/bin/nft -f ${egressRules}
  '';
  networking.firewall.extraStopCommands = ''
    ${pkgs.nftables}/bin/nft destroy table inet roomcast
  '';
  systemd.services.roomcast = {
    requires = [ "firewall.service" ];
    after = [ "firewall.service" ];
  };

  systemd.services.roomcast-mcp = {
    description = "Shared Roomcast MCP endpoint";
    wantedBy = [ "multi-user.target" ];
    requires = [ "firewall.service" ];
    wants = [ "roomcast.service" ];
    after = [
      "firewall.service"
      "roomcast.service"
    ];
    environment.ROOMCAST_SOCKET = "/run/roomcast/control.sock";
    serviceConfig = {
      ExecStart = "${mcpPython}/bin/uvicorn roomcast.mcp:app.streamable_http_app --factory --host 127.0.0.1 --port ${toString mcpPort} --no-access-log";
      DynamicUser = true;
      SupplementaryGroups = [ "roomcast" ];
      Restart = "on-failure";
      RestartSec = 2;
      TimeoutStopSec = 15;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
      ];
      IPAddressDeny = "any";
      IPAddressAllow = "localhost";
    };
  };

  systemd.services.hermes-agent = {
    wants = [ "roomcast-mcp.service" ];
    after = [ "roomcast-mcp.service" ];
  };
  systemd.services.hermes-backend = {
    wants = [ "roomcast-mcp.service" ];
    after = [ "roomcast-mcp.service" ];
  };

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
    playerAppId = "dev";
    playerSupportsSeeking = true;
    playerSupportsSubtitles = true;
  };

  users.users.${username}.extraGroups = [ "roomcast" ];
  systemd.services.hermes-agent.serviceConfig.SupplementaryGroups = [ "roomcast" ];
  systemd.services.hermes-backend.serviceConfig.SupplementaryGroups = [ "roomcast" ];

  services.hermes-agent.settings.mcp_servers.roomcast = {
    url = "http://127.0.0.1:${toString mcpPort}/mcp";
    transport = "http";
    lazy = false;
  };
}
