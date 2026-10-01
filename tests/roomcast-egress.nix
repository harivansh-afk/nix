{
  pkgs,
  rules,
  ownerUid,
  mcpPort,
}:
pkgs.testers.runNixOSTest {
  name = "roomcast-egress";
  nodes.machine = {
    networking.firewall.enable = false;
    users.users.roomcast = {
      isSystemUser = true;
      group = "roomcast";
    };
    users.groups.roomcast = { };
    environment.systemPackages = [
      pkgs.nftables
      pkgs.iproute2
    ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("${pkgs.python3}/bin/python ${./roomcast-egress.py} --rules ${rules} --owner-uid ${toString ownerUid} --mcp-port ${toString mcpPort}")
  '';
}
