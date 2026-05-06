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
      "qwen2.5-coder:14b-instruct-q4_K_M"
    ];
  };
}
