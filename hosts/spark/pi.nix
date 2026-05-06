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
      "spark-vllm"
      "--model"
      "Qwen/Qwen3-32B"
    ];
  };
}
