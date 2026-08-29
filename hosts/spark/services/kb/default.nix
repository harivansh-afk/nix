# Personal knowledge base: Postgres + pgvector, a llama.cpp embeddings
# server, hourly connectors that write markdown into /var/lib/kb/staging,
# and the indexer that rebuilds the vector + full-text index from it. See
# README.md for the retrieval design.
{ lib, pkgs, ... }:
let
  user = "rathi";
  group = "users";
  stagingDir = "/var/lib/kb/staging";
  gws = "/run/current-system/sw/bin/gws";

  embedPort = 18200;
  embedRepo = "Qwen/Qwen3-Embedding-0.6B-GGUF";
  embedModelDir = "/var/lib/llama-cpp-embed/models/qwen3-embedding-0.6b";
  embedModelFile = "Qwen3-Embedding-0.6B-Q8_0.gguf";
  embedModelPath = "${embedModelDir}/${embedModelFile}";

  llamaCpp = pkgs.llama-cpp.override {
    cudaSupport = true;
    cudaPackages = pkgs.cudaPackages_13_1;
  };
  hf = pkgs.python3.withPackages (ps: [
    ps.huggingface-hub
    ps.hf-transfer
  ]);
  kbPython = pkgs.python3.withPackages (ps: [ ps.psycopg2 ]);
  downloadsPython = pkgs.python3.withPackages (ps: [
    ps.pymupdf
    ps.python-docx
    ps.openpyxl
  ]);

  pgUser = "cognee";
  pgDb = "cognee";
  pgPassword = "cognee";

  kbSearch = pkgs.writeShellScriptBin "kb-search" ''
    [ $# -gt 0 ] || { echo "Usage: kb-search <query>" >&2; exit 2; }
    exec ${kbPython}/bin/python ${./kb_vec.py} search "$@"
  '';

  # Connectors run as the user (gws credentials) on a timer.
  connector = name: onCalendar: exec: {
    services."kb-connector-${name}" = {
      description = "KB connector: ${name} -> staging";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.jq
        pkgs.coreutils
        pkgs.gnused
        pkgs.curl
      ];
      environment = {
        KB_STAGING_DIR = stagingDir;
        GWS = gws;
        GWS_ENV = ./connectors/gws-env.sh;
      };
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        ExecStart = exec;
      };
    };
    timers."kb-connector-${name}" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = onCalendar;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
  connectors = lib.zipAttrsWith (_: lib.mergeAttrsList) [
    (connector "gmail" "hourly" "${pkgs.bash}/bin/bash ${./connectors/gmail.sh}")
    (connector "calendar" "hourly" "${pkgs.bash}/bin/bash ${./connectors/calendar.sh}")
    (connector "forgejo" "hourly" "${pkgs.bash}/bin/bash ${./connectors/forgejo.sh}")
    (connector "downloads" "daily" "${downloadsPython}/bin/python ${./downloads_connector.py}")
  ];
in
{
  environment.systemPackages = [ kbSearch ];

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
    "d /var/lib/kb 0755 ${user} ${group} -"
    "d ${stagingDir} 0755 ${user} ${group} -"
    "d ${stagingDir}/gmail 0755 ${user} ${group} -"
    "d ${stagingDir}/calendar 0755 ${user} ${group} -"
    "d ${stagingDir}/forgejo 0755 ${user} ${group} -"
    "d ${stagingDir}/downloads 0755 ${user} ${group} -"
  ];

  systemd.services = connectors.services // {
    kb-pg-setup = {
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

    llama-cpp-embed-download = {
      before = [ "llama-cpp-embed.service" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        HF_HOME = "/var/lib/llama-cpp-embed/huggingface";
        HF_HUB_ENABLE_HF_TRANSFER = "1";
      };
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "1200";
        ExecStart = pkgs.writeShellScript "download-qwen3-embedding-gguf" ''
          set -euo pipefail
          [ -s "${embedModelPath}" ] || ${hf}/bin/hf download ${embedRepo} \
            --include "${embedModelFile}" --local-dir "${embedModelDir}"
        '';
      };
    };

    llama-cpp-embed = {
      description = "llama.cpp embeddings server (OpenAI-compatible)";
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
          "--host 127.0.0.1"
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

    kb-ingest = {
      description = "Personal KB vector index (embeddings -> pgvector)";
      after = [
        "network.target"
        "kb-pg-setup.service"
        "llama-cpp-embed.service"
      ];
      requires = [
        "kb-pg-setup.service"
        "llama-cpp-embed.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        ExecStart = "${kbPython}/bin/python ${./kb_vec.py} ingest";
        SyslogIdentifier = "kb-ingest";
      };
    };
  };

  systemd.timers = connectors.timers // {
    kb-ingest = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
}
