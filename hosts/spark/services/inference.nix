{ lib, pkgs, ... }:
let
  modelRevision = "7b719225242aacd3dbd3f9407468c2ee9a9d2594";
  modelDirectory = "/var/lib/vllm/models/${modelRevision}";
  huggingfaceCli = pkgs.python3.withPackages (p: [ p.huggingface-hub ]);
  settings = (pkgs.formats.json { }).generate "vllm-config.yaml" {
    model = "/model";
    served-model-name = "qwen3.8-flash-next";
    host = "127.0.0.1";
    port = 18080;
    load-format = "safetensors";
    max-model-len = 65536;
    max-num-seqs = 1;
    max-num-batched-tokens = 2048;
    gpu-memory-utilization = 0.80;
    kv-cache-dtype = "auto";
    enable-prefix-caching = true;
    enable-chunked-prefill = true;
    enable-flashinfer-autotune = false;
    enable-auto-tool-choice = true;
    tool-call-parser = "qwen3_coder";
    reasoning-parser = "qwen3";
    speculative-config = {
      method = "mtp";
      num_speculative_tokens = 2;
    };
    compilation-config = {
      cudagraph_mode = "PIECEWISE";
      splitting_ops = [
        "vllm::unified_attention_with_output"
        "vllm::unified_mla_attention_with_output"
        "vllm::mamba_mixer2"
        "vllm::mamba_mixer"
        "vllm::short_conv"
        "vllm::qwen3_8_flash_next_ple_short_conv"
        "vllm::qwen3_8_flash_next_qsa_with_output"
        "vllm::linear_attention"
        "vllm::qwen_gdn_attention_core"
        "vllm::qwen_gdn_attention_core_fused_norm_packed"
        "vllm::sparse_attn_indexer"
        "vllm::ple_mmap_lookup"
      ];
    };
  };
in
{
  services.llama-cpp.enable = lib.mkForce false;
  services.ollama.enable = lib.mkForce false;

  environment.etc."vllm/config.yaml".source = settings;
  systemd.tmpfiles.rules = [ "d /var/lib/vllm/cache 0755 root root -" ];

  systemd.services.vllm-model-download = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment.HF_HOME = "/var/lib/vllm/huggingface";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "vllm";
      ExecStart = "${huggingfaceCli}/bin/hf download RadixArk/Qwen3.8-Flash-Next-NVFP4 --revision ${modelRevision} --local-dir ${modelDirectory} --max-workers 4";
      TimeoutStartSec = "2h";
      MemoryMax = "8G";
    };
  };

  virtualisation.oci-containers.containers.vllm = {
    image = "ghcr.io/lancelind/qwen38-flash-dgx@sha256:c949df1ba87e1ecda351ef2cf8e58b9d7e7e973dda7998b476eec446fd6d0872";
    pull = "missing";
    devices = [ "nvidia.com/gpu=all" ];
    networks = [ "host" ];
    volumes = [
      "${settings}:/etc/vllm/config.yaml:ro"
      "${modelDirectory}:/model:ro"
      "/var/lib/vllm/cache:/root/.cache"
    ];
    environment = {
      HF_HUB_OFFLINE = "1";
      VLLM_PLE_MMAP = "1";
      VLLM_PLE_MMAP_WORKERS = "32";
      VLLM_PLE_MMAP_PREWARM = "0";
      VLLM_QSA_EXACT_TOPK = "1";
      VLLM_USE_FLASHINFER_SAMPLER = "1";
    };
    cmd = [
      "--config"
      "/etc/vllm/config.yaml"
    ];
    extraOptions = [
      "--shm-size=2g"
      "--memory=100g"
      "--memory-swap=100g"
      "--ulimit=memlock=-1:-1"
      "--ulimit=stack=67108864:67108864"
      "--stop-timeout=60"
    ];
  };

  systemd.services.podman-vllm = {
    requires = [ "vllm-model-download.service" ];
    after = [
      "vllm-model-download.service"
      "llama-cpp.service"
    ];
    conflicts = [ "llama-cpp.service" ];
    serviceConfig = {
      Restart = lib.mkForce "no";
      TimeoutStartSec = lib.mkForce "30min";
      LimitMEMLOCK = "infinity";
      OOMScoreAdjust = 1000;
    };
  };
}
