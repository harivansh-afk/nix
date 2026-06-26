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
  # Qwen3.6-35B-A3B (MoE, 35B total / ~3B active per token). Swapped in from the
  # Nemotron 3 Super 120B-A12B: that 120B at 12B-active ran ~19 tok/s and pinned
  # the 128 GB box, so large-context sessions were painful. Qwen3.6-35B-A3B is
  # the community/Unsloth pick for local Hermes agents (consistently strong,
  # low-overhead tool calling); 3B-active and a ~22 GB Q4 weight set make
  # generation far faster and leave huge headroom for context. The old Nemotron
  # GGUFs are left on disk for a manual A/B if ever wanted.
  #
  # Unsloth dynamic UD-Q4_K_XL: a single ~22 GB GGUF at the repo root (no shards).
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
    # nixpkgs replaced `extraFlags` with a freeform `settings` attrset rendered
    # via lib.cli.toCommandLine (multi-char key -> --key value, bool -> bare
    # flag). Keep loopback-only, off well-known ports.
    settings = {
      host = "127.0.0.1";
      port = 18080;
      model = modelPath;
      alias = "qwen3.6-35b-a3b";
      # Hermes Agent requires >= 64k context. Single slot at 64k keeps KV cache
      # modest. Single-user backend, one slot. With only ~22 GB of weights there
      # is ample headroom to raise ctx-size later if needed.
      "ctx-size" = 65536;
      parallel = 1;
      "n-gpu-layers" = 99;
      # GB10 unified memory: --no-mmap avoids the lazy page-fault load + page
      # cache duplication; --mlock pins weights resident. (Far less critical at
      # 22 GB than it was at 76 GB, but still the correct GB10 default.)
      "no-mmap" = true;
      mlock = true;
      # Tool calling: --jinja is enabled by default in this llama.cpp, but pin it
      # explicitly since reliable structured tool calls are load-bearing for the
      # Hermes agent loop. Flash attention speeds prefill.
      jinja = true;
      "flash-attn" = "on";
      # Run the hybrid-thinking model in NON-thinking mode: the agent loop does
      # not need long internal reasoning chains, and skipping them is the single
      # biggest latency win (the 120B's slowness was mostly reasoning tokens).
      # `--reasoning off` is the first-class llama.cpp toggle (env LLAMA_ARG_
      # REASONING); we avoid `--chat-template-kwargs '{"enable_thinking":false}'`
      # because the embedded quotes get mangled by systemd ExecStart parsing.
      # `--reasoning-budget 0` hard-caps any residual thinking to immediate end.
      reasoning = "off";
      "reasoning-budget" = 0;
      # Sampling follows Unsloth's non-thinking recipe for Qwen3.6.
      temp = "0.7";
      "top-p" = "0.8";
      "top-k" = 20;
      "presence-penalty" = "1.5";
      "min-p" = "0.0";
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
      # --mlock pins the ~22GB weights resident; raise memlock so it is allowed.
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
