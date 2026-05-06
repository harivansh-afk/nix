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
  modelDir = "/var/lib/llama-cpp/models/qwen3.6-27b";
  modelFile = "Qwen3.6-27B-UD-Q6_K_XL.gguf";
  modelPath = "${modelDir}/${modelFile}";
  downloadModel = pkgs.writeShellScript "download-qwen3-6-27b-gguf" ''
    set -euo pipefail
    if [ ! -s "${modelPath}" ]; then
      ${huggingfaceCli}/bin/hf download unsloth/Qwen3.6-27B-GGUF --include "${modelFile}" --local-dir "${modelDir}"
    fi
  '';
in
{
  services.ollama.enable = lib.mkForce false;

  services.llama-cpp = {
    enable = true;
    host = "127.0.0.1";
    port = 8080;
    package = llamaCpp;
    extraFlags = [
      "-m"
      modelPath
      "--alias"
      "qwen3.6-27b"
      "-c"
      "131072"
      "-ngl"
      "99"
      "--temp"
      "0.7"
      "--top-p"
      "0.8"
      "--top-k"
      "20"
      "--presence-penalty"
      "1.5"
      "--chat-template-kwargs"
      ''{"enable_thinking":false}''
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp 0755 root root -"
    "d /var/lib/llama-cpp/models 0755 root root -"
    "d ${modelDir} 0755 root root -"
    "d /var/lib/llama-cpp/huggingface 0755 root root -"
  ];

  systemd.services.llama-cpp-qwen36-download = {
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
    after = [ "llama-cpp-qwen36-download.service" ];
    requires = [ "llama-cpp-qwen36-download.service" ];
  };
}
