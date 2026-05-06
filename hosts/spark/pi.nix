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
      "ollama"
      "--model"
      "qwen3-coder-next"
    ];
  };
}
