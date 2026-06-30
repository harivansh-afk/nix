{ lib, pkgs, ... }:
let
  llamaCpp = pkgs.llama-cpp.override {
    cudaSupport = true;
    cudaPackages = pkgs.cudaPackages_13_1;
  };
  huggingfaceCli = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.huggingface-hub
    pythonPackages.hf-transfer
  ]);

  hfRepo = "unsloth/Qwen3.6-35B-A3B-GGUF";
  quant = "UD-Q4_K_XL";
  modelDir = "/var/lib/llama-cpp/models/qwen3.6-35b-a3b";
  modelFile = "Qwen3.6-35B-A3B-${quant}.gguf";
  modelPath = "${modelDir}/${modelFile}";
  downloadModel = pkgs.writeShellScript "download-qwen3.6-35b-a3b-gguf" ''
    set -euo pipefail
    if [ ! -s "${modelPath}" ]; then
      ${huggingfaceCli}/bin/hf download ${hfRepo} --include "${modelFile}" --local-dir "${modelDir}"
    fi
  '';
in
{
  services.ollama.enable = lib.mkForce false;

  services.llama-cpp = {
    enable = true;
    package = llamaCpp;
    
    settings = {
      host = "127.0.0.1";
      port = 18080;
      model = modelPath;
      alias = "qwen3.6-35b-a3b";
      "ctx-size" = 65536;
      parallel = 1;
      "n-gpu-layers" = 99;
      "no-mmap" = true;
      mlock = true;
      jinja = true;
      "flash-attn" = "on";
      reasoning = "off";
      "reasoning-budget" = 0;
      temp = "0.7";
      "top-p" = "0.8";
      "top-k" = 20;
      "presence-penalty" = "1.5";
      "min-p" = "0.0";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp 0755 root root -"
    "d /var/lib/llama-cpp/models 0755 root root -"
    "d ${modelDir} 0755 root root -"
    "d /var/lib/llama-cpp/huggingface 0755 root root -"
    "w /sys/block/nvme0n1/queue/read_ahead_kb - - - - 8192"
  ];

  systemd.services.llama-cpp-model-download = {
    before = [ "llama-cpp.service" ];
    environment = {
      HF_HOME = "/var/lib/llama-cpp/huggingface";
      HF_HUB_ENABLE_HF_TRANSFER = "1";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = downloadModel;
    };
  };

  systemd.services.llama-cpp = {
    after = [ "llama-cpp-model-download.service" ];
    requires = [ "llama-cpp-model-download.service" ];
    serviceConfig = {
      OOMScoreAdjust = 1000;
      LimitMEMLOCK = "infinity";
      ProcSubset = lib.mkForce "all";
      ProtectProc = lib.mkForce "default";
    };
  };
}
