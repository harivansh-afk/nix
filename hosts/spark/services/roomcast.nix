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
  egressRules = pkgs.writeText "roomcast-egress.nft" ''
    destroy table inet roomcast
    table inet roomcast {
      chain output {
        type filter hook output priority -5; policy accept;
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
