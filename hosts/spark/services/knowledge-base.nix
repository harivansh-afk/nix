{ lib, pkgs, ... }:
let
  embedHost = "127.0.0.1";
  embedPort = 18200;
  embedRepo = "Qwen/Qwen3-Embedding-0.6B-GGUF";
  embedModelDir = "/var/lib/llama-cpp-embed/models/qwen3-embedding-0.6b";
  embedModelFile = "Qwen3-Embedding-0.6B-Q8_0.gguf";
  embedModelPath = "${embedModelDir}/${embedModelFile}";

  llamaCpp = pkgs.llama-cpp.override {
    cudaSupport = true;
    cudaPackages = pkgs.cudaPackages_13_1;
  };

  huggingfaceCli = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.huggingface-hub
    pythonPackages.hf-transfer
  ]);

  downloadEmbedModel = pkgs.writeShellScript "download-qwen3-embedding-gguf" ''
    set -euo pipefail
    if [ ! -s "${embedModelPath}" ]; then
      ${huggingfaceCli}/bin/hf download ${embedRepo} \
        --include "${embedModelFile}" --local-dir "${embedModelDir}"
    fi
  '';

  pgUser = "cognee";
  pgDb = "cognee";
  pgPassword = "cognee";
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    extensions = ps: [ ps.pgvector ];
    enableTCPIP = true;
    settings.listen_addresses = lib.mkForce "127.0.0.1";

    ensureDatabases = [ pgDb ];
    ensureUsers = [
      {
        name = pgUser;
        ensureDBOwnership = true;
      }
    ];

    authentication = lib.mkForce ''
      local   all       all                  peer
      host    all       all   127.0.0.1/32   scram-sha-256
      host    all       all   ::1/128        scram-sha-256
    '';
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp-embed 0755 root root -"
    "d /var/lib/llama-cpp-embed/models 0755 root root -"
    "d ${embedModelDir} 0755 root root -"
    "d /var/lib/llama-cpp-embed/huggingface 0755 root root -"
  ];

  systemd.services.llama-cpp-embed-download = {
    description = "Download Qwen3 embedding GGUF for the embeddings server";
    before = [ "llama-cpp-embed.service" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      HF_HOME = "/var/lib/llama-cpp-embed/huggingface";
      HF_HUB_ENABLE_HF_TRANSFER = "1";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = downloadEmbedModel;
      TimeoutStartSec = "1200";
    };
  };

  systemd.services.llama-cpp-embed = {
    description = "llama.cpp embeddings server (OpenAI-compatible), GB10 GPU";
    after = [
      "network-online.target"
      "llama-cpp-embed-download.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "llama-cpp-embed-download.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = lib.concatStringsSep " " [
        "${llamaCpp}/bin/llama-server"
        "--host ${embedHost}"
        "--port ${toString embedPort}"
        "-m ${embedModelPath}"
        "--alias qwen3-embedding-0.6b"
        "--embedding"
        "--pooling last"
        "-ngl 99"
        "-c 8192"
        "-b 8192"
        "-ub 8192"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = "1200";
      OOMScoreAdjust = 500;
    };
  };

  systemd.services.kb-pg-setup = {
    description = "Set the KB Postgres role password and ensure pgvector";
    after = [ "postgresql-setup.service" ];
    requires = [ "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
      ExecStart = pkgs.writeShellScript "kb-pg-setup" ''
        set -euo pipefail
        ${pkgs.postgresql_17}/bin/psql -v ON_ERROR_STOP=1 -d ${pgDb} <<'SQL'
        ALTER ROLE ${pgUser} WITH LOGIN PASSWORD '${pgPassword}';
        CREATE EXTENSION IF NOT EXISTS vector;
        SQL
      '';
    };
  };
}
