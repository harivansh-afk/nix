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
  modelDir = "/var/lib/llama-cpp/models/step-3.5-flash-reap-121b";
  modelFile = "Step-3.5-Flash-REAP-121B-A11B.Q4_K_M.gguf";
  modelPath = "${modelDir}/${modelFile}";
  downloadModel = pkgs.writeShellScript "download-step-3-5-flash-reap-121b-gguf" ''
    set -euo pipefail
    if [ ! -s "${modelPath}" ]; then
      ${huggingfaceCli}/bin/hf download mradermacher/Step-3.5-Flash-REAP-121B-A11B-GGUF --include "${modelFile}" --local-dir "${modelDir}"
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
      "step-3.5-flash-reap-121b"
      "-c"
      "32768"
      "-ngl"
      "99"
      "--sleep-idle-seconds"
      "600"
      "--temp"
      "0.7"
      "--top-p"
      "0.8"
      "--top-k"
      "20"
      "--presence-penalty"
      "1.5"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp 0755 root root -"
    "d /var/lib/llama-cpp/models 0755 root root -"
    "d ${modelDir} 0755 root root -"
    "d /var/lib/llama-cpp/huggingface 0755 root root -"
  ];

  systemd.services.llama-cpp-step-reap-download = {
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
    after = [ "llama-cpp-step-reap-download.service" ];
    requires = [ "llama-cpp-step-reap-download.service" ];
    serviceConfig = {
      OOMScoreAdjust = 1000;
    };
  };
}
