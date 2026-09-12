{ lib, pkgs, ... }:
let
  stateDir = "/var/lib/vllm";
  modelId = "Mia-AiLab/Qwen3.8-Flash-Next-NVFP4";
  modelRevision = "925d7be6c14c6c9442ef83e8f05b5a3c39304f69";
  baseImage = "docker.io/vllm/vllm-openai@sha256:3b0e188ffceb3d07e09c3cb5215433a0020eacf02d7f882ed3a8bfd15454477e";
  recipe = pkgs.fetchFromGitHub {
    owner = "MiaAI-Lab";
    repo = "Qwen3.8-Flash-Next-Single-DGX-Spark";
    rev = "d03809008834124e80223c3482f2ddb59577a48f";
    hash = "sha256-ObY98FYR1iSF8HbDaU80do6s12wXDvgXV20Ak/YcDjU=";
  };
  imageContext = pkgs.runCommand "vllm-flash-next-image-context" { } ''
    mkdir -p $out/recipe
    cp -r ${recipe}/files $out/recipe/files
    cp ${recipe}/LICENSE $out/recipe/LICENSE
    cp ${./inference/Containerfile} $out/Containerfile
    cp ${./inference/apply-patches.py} $out/apply-patches.py
  '';
  image = "localhost/qwen-flash-next:${
    builtins.substring 0 20 (builtins.hashString "sha256" "${baseImage}:${imageContext}")
  }";
  preparation = pkgs.writeText "vllm-preparation.json" (
    builtins.toJSON {
      inherit
        stateDir
        modelId
        modelRevision
        baseImage
        imageContext
        image
        ;
      manifest = ./inference/model-files.json;
    }
  );
  python = pkgs.python3.withPackages (p: [ p.huggingface-hub ]);
  guard = "${pkgs.python3}/bin/python3 ${./inference/memory-guard.py}";
in
{
  services.ollama.enable = lib.mkForce false;
  services.llama-cpp.enable = lib.mkForce false;

  system.build.vllmImageContext = imageContext;
  system.build.vllmPreparation = preparation;

  systemd.services.vllm-prepare = {
    description = "Prepare pinned Qwen Flash Next runtime and weights";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.podman ];
    environment.HF_HUB_DISABLE_IMPLICIT_TOKEN = "1";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "vllm";
      StateDirectoryMode = "0750";
      ExecStart = "${python}/bin/python3 ${./inference/prepare.py} ${preparation}";
      TimeoutStartSec = "2h";
      OOMScoreAdjust = 750;
      MemoryMax = "8G";
    };
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers.vllm = {
      inherit image;
      pull = "never";
      devices = [ "nvidia.com/gpu=all" ];
      networks = [ "host" ];
      capabilities = {
        SYS_NICE = true;
        SYS_PTRACE = true;
      };
      volumes = [
        "${stateDir}/models/${modelRevision}:/model:ro"
        "${stateDir}/ple/${modelRevision}:/packed:ro"
        "${stateDir}/cache:/root/.cache/vllm"
      ];
      environment = {
        HF_HUB_OFFLINE = "1";
        TRANSFORMERS_OFFLINE = "1";
        VLLM_USE_V2_MODEL_RUNNER = "1";
        VLLM_PLE_CPU_OFFLOAD = "1";
        VLLM_PLE_PACKED_TABLE_DIR = "/packed";
        VLLM_PLE_OFFLOAD_STEP_TIMEOUT = "300";
        VLLM_MTP_DRAFT_VOCAB = "/opt/spark-recipe/files/draft_vocab_en_code_47k.txt";
      };
      extraOptions = [
        "--shm-size=2g"
        "--ulimit=memlock=-1:-1"
        "--ulimit=stack=67108864:67108864"
        "--memory=94g"
        "--memory-swap=94g"
        "--stop-timeout=60"
      ];
      cmd = [
        "/model"
        "--served-model-name"
        "qwen3.8-flash-next"
        "--host"
        "127.0.0.1"
        "--port"
        "18080"
        "--tensor-parallel-size"
        "1"
        "--gpu-memory-utilization"
        "0.70"
        "--max-model-len"
        "65536"
        "--max-num-seqs"
        "1"
        "--max-num-batched-tokens"
        "2048"
        "--kv-cache-dtype"
        "fp8"
        "--mamba-ssm-cache-dtype"
        "bfloat16"
        "--load-format"
        "safetensors"
        "--safetensors-load-strategy"
        "lazy"
        "--enable-chunked-prefill"
        "--reasoning-parser"
        "qwen3"
        "--enable-auto-tool-choice"
        "--tool-call-parser"
        "qwen3_coder"
        "--distributed-executor-backend"
        "mp"
        "--speculative-config"
        (builtins.toJSON {
          method = "mtp";
          num_speculative_tokens = 3;
          use_local_argmax_reduction = true;
        })
        "--compilation-config"
        (builtins.toJSON {
          mode = 0;
          cudagraph_mode = "FULL_DECODE_ONLY";
          cudagraph_capture_sizes = [ 4 ];
        })
      ];
    };
  };

  systemd.services.podman-vllm = {
    requires = [ "vllm-prepare.service" ];
    after = [
      "vllm-prepare.service"
      "llama-cpp.service"
    ];
    conflicts = [ "llama-cpp.service" ];
    wants = [ "vllm-memory-watch.service" ];
    serviceConfig = {
      ExecStartPre = [ "${guard} preflight" ];
      Restart = lib.mkForce "no";
      OOMScoreAdjust = 1000;
      LimitMEMLOCK = "infinity";
    };
  };

  systemd.services.vllm-memory-watch = {
    description = "Stop vLLM when Spark host memory loses its reserve";
    after = [ "podman-vllm.service" ];
    bindsTo = [ "podman-vllm.service" ];
    partOf = [ "podman-vllm.service" ];
    path = [ pkgs.systemd ];
    serviceConfig = {
      ExecStart = "${guard} watch";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };
}
