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
    package = llamaCpp;
    # nixpkgs replaced `extraFlags` with a freeform `settings` attrset rendered
    # via lib.cli.toCommandLine (multi-char key -> --key value, bool -> bare
    # flag). Keep loopback-only, off well-known ports.
    settings = {
      host = "127.0.0.1";
      port = 18080;
      model = modelPath;
      alias = "nemotron-3-super-120b";
      # Hermes Agent requires >= 64k context. Single slot at 64k keeps KV cache
      # modest (32k was below Hermes's floor). Single-user backend, one slot.
      "ctx-size" = 65536;
      parallel = 1;
      "n-gpu-layers" = 99;
      # DGX Spark / GB10: default mmap loads the 76GB model lazily one page fault
      # at a time (~5-8 min) AND duplicates ~60GB into the page cache, feeding
      # OOM. NVIDIA staff and the llama.cpp maintainer run --no-mmap on GB10:
      # load drops to ~20-90s and memory pressure drops. --mlock pins it resident.
      "no-mmap" = true;
      mlock = true;
      # NVIDIA's recommendation for Nemotron 3 Super: temp 1.0, top-p 0.95.
      temp = "1.0";
      "top-p" = "0.95";
      # NOTE: deliberately NO `special`. It renders control tokens (e.g. the
      # <|im_end|> turn terminator) as literal text; reasoning is already split
      # into reasoning_content by the reasoning parser.
      # NOTE: deliberately NO idle sleep - this is an always-on resident brain.
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp 0755 root root -"
    "d /var/lib/llama-cpp/models 0755 root root -"
    "d ${modelDir} 0755 root root -"
    "d /var/lib/llama-cpp/huggingface 0755 root root -"
    # NVMe read-ahead 8192 KiB: cuts large-model load time materially on the
    # DGX Spark's kernel 6.17 (NVIDIA forum guidance). Harmless if the device
    # name differs (tmpfiles just warns).
    "w /sys/block/nvme0n1/queue/read_ahead_kb - - - - 8192"
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
      # --mlock pins ~76GB resident; raise the memlock rlimit so it is allowed.
      LimitMEMLOCK = "infinity";
      # CRITICAL on DGX Spark / GB10 unified memory: llama.cpp reads
      # /proc/meminfo to size its unified-memory (UMA) allocations. The
      # upstream services.llama-cpp module sets ProcSubset=pid, which hides
      # /proc/meminfo, so llama.cpp falls back to cudaMemGetInfo (wrong on
      # GB10) and mis-manages memory -> OOM and stalled/slow model loads.
      # Allow the full /proc so UMA detection works.
      ProcSubset = lib.mkForce "all";
      ProtectProc = lib.mkForce "default";
    };
  };
}
