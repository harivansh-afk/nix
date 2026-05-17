{ inputs, ... }:
let
  models = ../../dots/pi/models.json;
in
{
  imports = [
    inputs.pi-mono.nixosModules.default
  ];

  programs.pi.coding-agent = {
    enable = true;
    users = [ "rathi" ];
    models = null;
    extraFlags = [
      "--provider"
      "step"
      "--model"
      "step-3.5-flash-reap-121b"
    ];
  };

  systemd.user.tmpfiles.users.rathi.rules = [
    "d %h/.pi 0700 - - -"
    "d %h/.pi/agent 0700 - - -"
    "L+ %h/.pi/agent/models.json - - - - ${models}"
  ];
}
