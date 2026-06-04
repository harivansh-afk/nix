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
  # Nemotron 3 Super (120B-A12B MoE). Ultra (550B) does not fit this box's
  # 128 GB of unified memory; Super is the largest Nemotron 3 that does and is
  # the variant NVIDIA officially ships a DGX Spark deployment guide for.
  #
  # Unsloth dynamic Q4_K_M: ~82 GB of weights split into three GGUF parts.
  # llama.cpp loads the whole set from the first ("00001-of-00003") shard.
  hfRepo = "unsloth/NVIDIA-Nemotron-3-Super-120B-A12B-GGUF";
  quant = "UD-Q4_K_M";
  modelDir = "/var/lib/llama-cpp/models/nemotron-3-super-120b";
  modelFile = "${quant}/NVIDIA-Nemotron-3-Super-120B-A12B-${quant}-00001-of-00003.gguf";
  modelPath = "${modelDir}/${modelFile}";
  downloadModel = pkgs.writeShellScript "download-nemotron-3-super-120b-gguf" ''
    set -euo pipefail
    if [ ! -s "${modelPath}" ]; then
      ${huggingfaceCli}/bin/hf download ${hfRepo} --include "${quant}/*" --local-dir "${modelDir}"
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
      "nemotron-3-super-120b"
      "-c"
      "32768"
      "-ngl"
      "99"
      "--sleep-idle-seconds"
      "600"
      # NVIDIA's universal recommendation for Nemotron 3 Super across reasoning,
      # tool calling and chat: temperature 1.0, top-p 0.95.
      "--temp"
      "1.0"
      "--top-p"
      "0.95"
      # <think>/</think> are distinct tokens; keep them in the stream.
      "--special"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp 0755 root root -"
    "d /var/lib/llama-cpp/models 0755 root root -"
    "d ${modelDir} 0755 root root -"
    "d /var/lib/llama-cpp/huggingface 0755 root root -"
  ];

  systemd.services.llama-cpp-nemotron-download = {
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
    after = [ "llama-cpp-nemotron-download.service" ];
    requires = [ "llama-cpp-nemotron-download.service" ];
    serviceConfig = {
      OOMScoreAdjust = 1000;
    };
  };
}
