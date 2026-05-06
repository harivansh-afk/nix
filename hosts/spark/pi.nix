{ inputs, ... }:
{
  imports = [
    inputs.pi-mono.nixosModules.default
  ];

  programs.pi.coding-agent = {
    enable = true;
    users = [ "rathi" ];
    models = ../../dots/pi/models.json;
    extraFlags = [
      "--provider"
      "local"
      "--model"
      "qwen3.6-27b"
    ];
  };
}
