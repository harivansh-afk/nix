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

  qwenModel = "unsloth/Qwen3.8-27B-NVFP4";
  qwenAlias = "qwen3.8-27b-nvfp4";
  # vLLM main is required for Qwen3.8 NVFP4. Pin the multi-arch image digest;
  # Podman selects its linux/arm64 manifest on spark.
  vllmImage = "vllm/vllm-openai@sha256:c96082d33456ceeae7ec0d4faf2b5e47fb806a103decf94f9fbc9b35fd7d6b25";

  unchainedRepo = "huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF";
  unchainedDir = "/var/lib/llama-cpp/models/huihui-qwen3.8-27b-abliterated";
  unchainedFile = "Huihui-Qwen3.8-27B-abliterated-Q4_K.gguf";
  unchainedPath = "${unchainedDir}/${unchainedFile}";

  modelPresets = pkgs.writeText "llama-cpp-models.ini" ''
    version = 1

    [huihui-qwen3.8-27b-abliterated]
    model = ${unchainedPath}
  '';

  downloadUnchained = pkgs.writeShellScript "download-llama-cpp-model" ''
    set -euo pipefail
    if [ ! -s "${unchainedPath}" ]; then
      ${huggingfaceCli}/bin/hf download ${unchainedRepo} --include "${unchainedFile}" --local-dir "${unchainedDir}"
    fi
  '';

  qwenMarker = "/var/lib/vllm/huggingface/.${qwenAlias}-complete";
  downloadQwen = pkgs.writeShellScript "download-vllm-model" ''
    set -euo pipefail
    if [ ! -e "${qwenMarker}" ]; then
      ${huggingfaceCli}/bin/hf download ${qwenModel}
      touch "${qwenMarker}"
    fi
  '';

  waitForQwen = pkgs.writeShellScript "wait-for-vllm" ''
    for _ in $(seq 570); do
      if ${pkgs.curl}/bin/curl -fsS -m 2 http://127.0.0.1:18080/v1/models >/dev/null 2>&1; then
        exit 0
      fi
      sleep 1
    done
    echo "qwen API never became ready; failing the unit instead of lying" >&2
    exit 1
  '';
in
{
  services.ollama.enable = lib.mkForce false;

  # The main model uses its native NVFP4 weights. llama.cpp cannot load this
  # format, so keep the unchained GGUF on a separate loopback-only server.
  virtualisation.oci-containers = {
    backend = "podman";
    containers.qwen3-8-nvfp4 = {
      image = vllmImage;
      ports = [ "127.0.0.1:18080:8000" ];
      volumes = [ "/var/lib/vllm/huggingface:/root/.cache/huggingface" ];
      environment.HF_HUB_OFFLINE = "1";
      extraOptions = [
        "--device=nvidia.com/gpu=all"
        "--ipc=host"
      ];
      cmd = [
        qwenModel
        "--served-model-name"
        qwenAlias
        "--trust-remote-code"
        "--gpu-memory-utilization"
        "0.4"
        "--max-model-len"
        "65536"
        "--max-num-seqs"
        "2"
        "--language-model-only"
        "--enforce-eager"
        "--enable-prefix-caching"
        "--enable-auto-tool-choice"
        "--tool-call-parser"
        "qwen3_coder"
        "--reasoning-parser"
        "qwen3"
      ];
    };
  };

  services.llama-cpp = {
    enable = true;
    package = llamaCpp;
    settings = {
      host = "127.0.0.1";
      port = 18081;
      "models-preset" = modelPresets;
      "models-max" = 1;
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
    "d ${unchainedDir} 0755 root root -"
    "d /var/lib/llama-cpp/huggingface 0755 root root -"
    "d /var/lib/vllm 0755 root root -"
    "d /var/lib/vllm/huggingface 0755 root root -"
    # The old main model is no longer managed or served.
    "R /var/lib/llama-cpp/models/qwen3.6-35b-a3b - - - -"
    "w /sys/block/nvme0n1/queue/read_ahead_kb - - - - 8192"
  ];

  systemd.services.vllm-model-download = {
    before = [ "podman-qwen3-8-nvfp4.service" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      HF_HOME = "/var/lib/vllm/huggingface";
      HF_HUB_ENABLE_HF_TRANSFER = "1";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = downloadQwen;
    };
  };

  systemd.services."podman-qwen3-8-nvfp4" = {
    after = [ "vllm-model-download.service" ];
    requires = [ "vllm-model-download.service" ];
    serviceConfig.ExecStartPost = waitForQwen;
  };

  systemd.services.llama-cpp-model-download = {
    before = [ "llama-cpp.service" ];
    environment = {
      HF_HOME = "/var/lib/llama-cpp/huggingface";
      HF_HUB_ENABLE_HF_TRANSFER = "1";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = downloadUnchained;
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
