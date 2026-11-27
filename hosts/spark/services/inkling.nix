{ lib, pkgs, ... }:
let
  modelRevision = "c9d028302cd0f035fdf8e7e91f089a4ce94d2195";
  modelDirectory = "/var/lib/inkling/models/${modelRevision}";
  huggingfaceCli = pkgs.python3.withPackages (p: [ p.huggingface-hub ]);
  settings = (pkgs.formats.json { }).generate "inkling-config.yaml" {
    model = "/model";
    served-model-name = [
      "inkling"
      "inkling-2-mini"
    ];
    host = "127.0.0.1";
    port = 18081;
    max-model-len = 131072;
    max-num-seqs = 4;
    gpu-memory-utilization = 0.45;
    enable-prefix-caching = true;
    enable-auto-tool-choice = true;
    tool-call-parser = "inkling";
    reasoning-parser = "inkling";
    enable-lora = true;
    max-lora-rank = 64;
    speculative-config = {
      method = "dspark";
      num_speculative_tokens = 7;
      draft_sample_method = "probabilistic";
    };
  };
in
{
  environment.etc."inkling/config.yaml".source = settings;
  systemd.tmpfiles.rules = [
    "d /var/lib/inkling/cache 0755 root root -"
    "d /var/lib/inkling/adapters 0755 root root -"
  ];

  systemd.services.inkling-model-download = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment.HF_HOME = "/var/lib/inkling/huggingface";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "inkling";
      ExecStart = "${huggingfaceCli}/bin/hf download thinkingmachines/Inkling-2-Mini --revision ${modelRevision} --local-dir ${modelDirectory} --max-workers 4";
      TimeoutStartSec = "2h";
      MemoryMax = "8G";
    };
  };

  virtualisation.oci-containers.containers.inkling = {
    autoStart = true;
    image = "docker.io/vllm/vllm-openai@sha256:62a04f232f8b72cbf38ff02e0fe389b9a48c678c5febeef0d8c5f33ebf515c9c";
    pull = "missing";
    devices = [ "nvidia.com/gpu=all" ];
    networks = [ "host" ];
    volumes = [
      "${settings}:/etc/vllm/config.yaml:ro"
      "${modelDirectory}:/model:ro"
      "/var/lib/inkling/adapters:/adapters:ro"
      "/var/lib/inkling/cache:/root/.cache"
    ];
    environment = {
      HF_HUB_OFFLINE = "1";
      VLLM_ALLOW_RUNTIME_LORA_UPDATING = "1";
    };
    cmd = [
      "--config"
      "/etc/vllm/config.yaml"
    ];
    extraOptions = [
      "--ipc=host"
      "--memory=64g"
      "--memory-swap=64g"
      "--ulimit=memlock=-1:-1"
      "--ulimit=stack=67108864:67108864"
      "--stop-timeout=60"
    ];
  };

  systemd.services.podman-inkling = {
    aliases = [ "inkling.service" ];
    requires = [ "inkling-model-download.service" ];
    after = [ "inkling-model-download.service" ];
    serviceConfig = {
      TimeoutStartSec = lib.mkForce "30min";
      LimitMEMLOCK = "infinity";
    };
  };
}
