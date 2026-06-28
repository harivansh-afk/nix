{ lib, pkgs, ... }:
let
  ############################################################################
  # Personal knowledge-base backend (GraphRAG).
  #
  # Three pieces, all loopback-only:
  #   1. Postgres 17 + pgvector  -> relational + vector store for Cognee
  #   2. llama.cpp --embedding   -> OpenAI-compatible /v1/embeddings on 18200
  #   3. Cognee (uv venv)        -> GraphRAG, configured FULLY LOCAL
  #
  # The brain LLM is already served by inference.nix at 127.0.0.1:18080/v1
  # (alias "nemotron-3-super-120b"); this module never starts another LLM.
  #
  # Ports (all 127.0.0.1, off well-known ports per CLAUDE.md):
  #   embeddings = 18200, (reranker reserved 18210), cognee-api reserved 18300,
  #   postgres   = 5432 (loopback).
  ############################################################################

  embedHost = "127.0.0.1";
  embedPort = 18200;

  # --- Embedding model -------------------------------------------------------
  # Qwen3-Embedding-0.6B: 1024-dim, 32k ctx, 100+ languages, strong on MTEB.
  # Official GGUF repo from the Qwen team (tracks current llama.cpp).
  # Q8_0 (~639 MB) keeps embedding quality essentially lossless on this box.
  embedRepo = "Qwen/Qwen3-Embedding-0.6B-GGUF";
  embedModelDir = "/var/lib/llama-cpp-embed/models/qwen3-embedding-0.6b";
  embedModelFile = "Qwen3-Embedding-0.6B-Q8_0.gguf";
  embedModelPath = "${embedModelDir}/${embedModelFile}";
  # Output dimension of Qwen3-Embedding-0.6B. Must match Cognee's
  # EMBEDDING_DIMENSIONS or the pgvector column will be sized wrong.
  embedDimensions = 1024;

  # CUDA 13.1 llama.cpp, identical build approach to inference.nix.
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

  # --- Cognee (uv venv, parakeet bootstrap pattern) --------------------------
  cogneeStateDir = "/var/lib/cognee";
  cogneeVenv = "${cogneeStateDir}/venv";
  python = pkgs.python312;

  # Bump to force a venv reinstall after changing deps.
  cogneeReqVersion = "2";
  # Pinned to the latest stable on PyPI at authoring time. Bump deliberately.
  cogneePkgVersion = "1.1.3";

  cogneeRuntimeBins = lib.makeBinPath [
    pkgs.uv
    pkgs.coreutils
    pkgs.gcc
    pkgs.binutils
  ];
  cogneeRuntimeLibs = lib.makeLibraryPath [
    # libstdc++.so.6 / libgcc for the manylinux wheels (tokenizers, etc.).
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];

  # Local Postgres connection used by Cognee for BOTH the relational store and
  # the pgvector vector store. Password is a low-value local secret; access is
  # loopback-only and gated by the hba rule below.
  pgUser = "cognee";
  pgDb = "cognee";
  pgPassword = "cognee";
  pgHost = "127.0.0.1";
  pgPort = 5432;

  # Cognee fully-local environment. CRITICAL: if LLM_PROVIDER or
  # EMBEDDING_PROVIDER is unset, Cognee silently falls back to OpenAI cloud, so
  # BOTH blocks are set explicitly. Var names sourced from cognee .env.template
  # and docs.cognee.ai (see notes at bottom of file). LiteLLM routes LLM and
  # embedding calls, so model names carry an "openai/" provider prefix.
  cogneeEnv = {
    # LLM -> the local brain at inference.nix (Qwen3.6) over OpenAI-compatible.
    LLM_PROVIDER = "custom";
    LLM_MODEL = "openai/qwen3.6-35b-a3b";
    LLM_ENDPOINT = "http://127.0.0.1:18080/v1";
    LLM_API_KEY = ".";

    # Embeddings -> the local llama.cpp embedding server above.
    EMBEDDING_PROVIDER = "custom";
    EMBEDDING_MODEL = "openai/qwen3-embedding-0.6b";
    EMBEDDING_ENDPOINT = "http://${embedHost}:${toString embedPort}/v1";
    EMBEDDING_API_KEY = ".";
    EMBEDDING_DIMENSIONS = toString embedDimensions;
    EMBEDDING_MAX_TOKENS = "8192";
    # litellm rejects the `dimensions` param for openai/-prefixed embedding
    # models (it assumes text-embedding-3+) and 422s. Tell it to drop unsupported
    # params instead; llama.cpp returns its native 1024-dim vectors regardless.
    LITELLM_DROP_PARAMS = "True";

    # Relational store = local Postgres (pgvector reuses this connection).
    DB_PROVIDER = "postgres";
    DB_HOST = pgHost;
    DB_PORT = toString pgPort;
    DB_NAME = pgDb;
    DB_USERNAME = pgUser;
    DB_PASSWORD = pgPassword;

    # Vector store = pgvector. Cognee 1.x defaults multi-user access control ON,
    # and that code path REQUIRES explicit VECTOR_DB_* creds (it will not fall
    # back to DB_*). This is a single-user personal KB, so turn access control
    # off and set the pgvector creds explicitly (works either way).
    ENABLE_BACKEND_ACCESS_CONTROL = "false";
    VECTOR_DB_PROVIDER = "pgvector";
    VECTOR_DB_HOST = pgHost;
    VECTOR_DB_PORT = toString pgPort;
    VECTOR_DB_NAME = pgDb;
    VECTOR_DB_USERNAME = pgUser;
    VECTOR_DB_PASSWORD = pgPassword;

    # Graph store = kuzu (file-based, fully local, no extra service).
    GRAPH_DATABASE_PROVIDER = "kuzu";

    # Local data/system roots + HF cache.
    DATA_ROOT_DIRECTORY = "${cogneeStateDir}/.cognee_data/";
    SYSTEM_ROOT_DIRECTORY = "${cogneeStateDir}/.cognee_system/";
    HF_HOME = "${cogneeStateDir}/hf";
    ENV = "local";
    # Skip Cognee's 30s embedding/LLM pre-flight test: the endpoints are local
    # and verified, and the test loses a race under GB10 GPU contention (the
    # 120B and the embed server share one GPU), which cancels the cognify task
    # group. Real calls during cognify still run normally.
    COGNEE_SKIP_CONNECTION_TEST = "true";
    # Driver libcuda + manylinux libs for any native deps pulled in by cognee.
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:${cogneeRuntimeLibs}";
  };

  # Render cogneeEnv into `export K=V` lines for the wrapper script.
  cogneeEnvExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") cogneeEnv
  );

  cogneeSetup = pkgs.writeShellScript "cognee-setup" ''
    set -euo pipefail
    export PATH=${cogneeRuntimeBins}:$PATH

    if [ "$(cat ${cogneeStateDir}/.req-version 2>/dev/null || true)" != "${cogneeReqVersion}" ] || [ ! -x ${cogneeVenv}/bin/python ]; then
      uv venv --clear --python ${python}/bin/python3.12 ${cogneeVenv}
      # Install cognee plus the Postgres drivers as prebuilt BINARY wheels:
      # cognee[postgres] would pull source-only psycopg2 (needs pg_config + a
      # C build); psycopg2-binary/asyncpg/pgvector ship aarch64 wheels and give
      # the same import names, so no compiler/pg_config is needed.
      uv pip install --python ${cogneeVenv}/bin/python \
        "cognee==${cogneePkgVersion}" psycopg2-binary asyncpg pgvector
      printf '%s' "${cogneeReqVersion}" > ${cogneeStateDir}/.req-version
    fi
  '';

  # `cognee-env <args>`: exec the venv python with the full local env set, so
  # the (separately owned) ingestion script can reuse this exact configuration
  # without duplicating it. Falls through to the venv python if no args given.
  cogneeEnvWrapper = pkgs.writeShellScriptBin "cognee-env" ''
    set -euo pipefail
    ${cogneeEnvExports}
    exec ${cogneeVenv}/bin/python "$@"
  '';
in
{
  ##########################################################################
  # 1. Postgres + pgvector (loopback only)
  ##########################################################################
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    # pgvector extension built against postgresql_17.
    extensions = ps: [ ps.pgvector ];
    # Loopback TCP so the cognee venv (and its asyncpg client) can connect by
    # host/port; never expose beyond localhost.
    enableTCPIP = true;
    settings.listen_addresses = lib.mkForce "127.0.0.1";

    ensureDatabases = [ pgDb ];
    ensureUsers = [
      {
        name = pgUser;
        ensureDBOwnership = true;
      }
    ];

    # Peer auth for local socket; password (scram) auth for the loopback TCP
    # connection cognee uses. Restrict TCP to 127.0.0.1/::1 only.
    authentication = lib.mkForce ''
      # TYPE  DATABASE  USER  ADDRESS        METHOD
      local   all       all                  peer
      host    all       all   127.0.0.1/32   scram-sha-256
      host    all       all   ::1/128        scram-sha-256
    '';
  };

  ##########################################################################
  # 2. Embeddings server: llama.cpp --embedding, OpenAI-compatible (18200)
  ##########################################################################
  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp-embed 0755 root root -"
    "d /var/lib/llama-cpp-embed/models 0755 root root -"
    "d ${embedModelDir} 0755 root root -"
    "d /var/lib/llama-cpp-embed/huggingface 0755 root root -"
    "d ${cogneeStateDir} 0750 root root -"
    "d ${cogneeStateDir}/hf 0750 root root -"
    "d ${cogneeStateDir}/.cognee_data 0750 root root -"
    "d ${cogneeStateDir}/.cognee_system 0750 root root -"
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
      # First run downloads ~639 MB.
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
        # Embedding mode: serve /v1/embeddings, no chat completion.
        "--embedding"
        # Qwen3-Embedding requires last-token pooling.
        "--pooling last"
        # Full model offload to the GB10 GPU.
        "-ngl 99"
        "-c 8192"
        # Allow batching long inputs up to the context window.
        "-b 8192"
        "-ub 8192"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = "1200";
      OOMScoreAdjust = 500;
    };
  };

  ##########################################################################
  # 3. Cognee venv bootstrap + role-password setup
  #
  # Cognee runs in LIBRARY mode here: a separate agent owns the ingestion /
  # search script, which invokes it via the `cognee-env` wrapper binary so it
  # inherits this exact fully-local configuration. (The REST server on 18300
  # is intentionally reserved but not started; flip Type/ExecStart below to
  # `uvicorn cognee.api.client:app` if a server is ever wanted.)
  ##########################################################################

  # Expose the wrapper so the ingestion script (and the user) can run it.
  environment.systemPackages = [ cogneeEnvWrapper ];

  # Set the cognee role password so the loopback scram TCP login works.
  # Runs after postgresql has ensured the role/db exist.
  systemd.services.cognee-pg-setup = {
    description = "Set Cognee Postgres role password and ensure vector ext";
    # postgresql-setup.service is the unit that runs ensureDatabases/ensureUsers
    # (creates the cognee db + role); ordering after postgresql.service alone
    # races it. Depend on the setup unit so the db exists before we connect.
    after = [ "postgresql-setup.service" ];
    requires = [ "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
      ExecStart = pkgs.writeShellScript "cognee-pg-setup" ''
        set -euo pipefail
        ${pkgs.postgresql_17}/bin/psql -v ON_ERROR_STOP=1 -d ${pgDb} <<'SQL'
        ALTER ROLE ${pgUser} WITH LOGIN PASSWORD '${pgPassword}';
        CREATE EXTENSION IF NOT EXISTS vector;
        SQL
      '';
    };
  };

  # Build the venv once dependencies are reachable. This is a oneshot so the
  # ingestion script's own service (separately owned) can depend on it.
  systemd.services.cognee-setup = {
    description = "Bootstrap the Cognee uv venv";
    after = [
      "network-online.target"
      "cognee-pg-setup.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "cognee-pg-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HF_HOME = "${cogneeStateDir}/hf";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = cogneeSetup;
      # First run resolves + installs the cognee dependency tree.
      TimeoutStartSec = "2400";
      OOMScoreAdjust = 500;
    };
  };
}
