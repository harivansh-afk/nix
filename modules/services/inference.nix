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

  qwenRepo = "unsloth/Qwen3.6-35B-A3B-GGUF";
  qwenDir = "/var/lib/llama-cpp/models/qwen3.6-35b-a3b";
  qwenFile = "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf";
  qwenPath = "${qwenDir}/${qwenFile}";

  huihuiRepo = "huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF";
  huihuiDir = "/var/lib/llama-cpp/models/huihui-qwen3.8-27b-abliterated";
  huihuiFile = "Huihui-Qwen3.8-27B-abliterated-Q4_K.gguf";
  huihuiPath = "${huihuiDir}/${huihuiFile}";

  modelPresets = pkgs.writeText "llama-cpp-models.ini" ''
    version = 1

    [qwen3.6-35b-a3b]
    model = ${qwenPath}
    reasoning = off
    reasoning-budget = 0

    [huihui-qwen3.8-27b-abliterated]
    model = ${huihuiPath}
  '';

  downloadModels = pkgs.writeShellScript "download-llama-cpp-models" ''
    set -euo pipefail
    if [ ! -s "${qwenPath}" ]; then
      ${huggingfaceCli}/bin/hf download ${qwenRepo} --include "${qwenFile}" --local-dir "${qwenDir}"
    fi
    if [ ! -s "${huihuiPath}" ]; then
      ${huggingfaceCli}/bin/hf download ${huihuiRepo} --include "${huihuiFile}" --local-dir "${huihuiDir}"
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
      "models-preset" = modelPresets;
      "models-max" = 2;
      "models-autoload" = true;
      "ctx-size" = 65536;
      parallel = 1;
      "n-gpu-layers" = 99;
      "no-mmap" = true;
      mlock = true;
      jinja = true;
      "flash-attn" = "on";
      "sleep-idle-seconds" = 300;
      temp = "0.7";
      "top-p" = "0.8";
      "top-k" = 20;
      "min-p" = "0.0";
      "presence-penalty" = "1.5";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp 0755 root root -"
    "d /var/lib/llama-cpp/models 0755 root root -"
    "d ${qwenDir} 0755 root root -"
    "d ${huihuiDir} 0755 root root -"
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
      ExecStart = downloadModels;
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
