{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  apiPort = 18310;
  webPort = 18517;
  supervisorPort = 17091;
  origin = "http://127.0.0.1:${toString webPort}";
  stateDir = "/var/lib/rakazo";
  prismaEngines =
    inputs.prisma-nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.prisma-engines_7;
  app = pkgs.callPackage ./rakazo-package.nix { inherit inputs prismaEngines; };
  appRoot = "${app}/lib/rakazo";
  node = "${pkgs.nodejs_24}/bin/node";
  tsx = "${appRoot}/node_modules/tsx/dist/cli.mjs";
  vite = "${appRoot}/node_modules/vite/bin/vite.js";
  prisma = "${appRoot}/node_modules/prisma/build/index.js";
  computerImage = "rakazo/computer:${inputs.rakazo-src.shortRev or "dirty"}";

  commonEnvironment = {
    NODE_ENV = "production";
    DATABASE_URL = "postgresql:///rakazo?host=/run/postgresql";
    DATA_DIR = stateDir;
    BETTER_AUTH_URL = origin;
    WEB_ORIGIN = origin;
    API_URL = origin;
    SIGNUPS_ENABLED = "true";
    SANDBOX_PROVIDER = "docker";
    SANDBOX_SUPERVISOR_URL = "http://127.0.0.1:${toString supervisorPort}";
    AGENT_RUNTIME = "pi";
    WAKEUP_DRIVER = "graphile";
    RAKAZO_LOCAL_MODELS = "qwen3.8-27b-nvfp4";
    RAKAZO_LOCAL_MODELS_URL = "http://127.0.0.1:18080/v1";
    RAKAZO_LOCAL_CONTEXT_WINDOW = "65536";
    RAKAZO_LOCAL_MAX_TOKENS = "32768";
    PRISMA_SCHEMA_ENGINE_BINARY = "${prismaEngines}/bin/schema-engine";
    PRISMA_QUERY_ENGINE_BINARY = "${prismaEngines}/bin/query-engine";
    PRISMA_QUERY_ENGINE_LIBRARY = "${prismaEngines}/lib/libquery_engine.node";
  };

  serviceConfig = {
    User = "rakazo";
    Group = "rakazo";
    WorkingDirectory = appRoot;
    EnvironmentFile = "${stateDir}/secrets.env";
    Restart = "on-failure";
    RestartSec = 5;
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectHome = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ stateDir ];
  };

  generateSecrets = pkgs.writeShellScript "rakazo-generate-secrets" ''
    set -euo pipefail
    secret_file=${lib.escapeShellArg "${stateDir}/secrets.env"}
    if [ -s "$secret_file" ]; then
      exit 0
    fi
    umask 0027
    temporary="$(${pkgs.coreutils}/bin/mktemp "${stateDir}/secrets.env.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$temporary"' EXIT
    {
      ${pkgs.coreutils}/bin/printf 'BETTER_AUTH_SECRET=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)"
      ${pkgs.coreutils}/bin/printf 'ENCRYPTION_KEY=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)"
      ${pkgs.coreutils}/bin/printf 'SANDBOX_SUPERVISOR_TOKEN=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)"
    } > "$temporary"
    ${pkgs.coreutils}/bin/chmod 0640 "$temporary"
    ${pkgs.coreutils}/bin/mv "$temporary" "$secret_file"
    trap - EXIT
  '';
in
{
  virtualisation = {
    docker.enable = true;
    # OCI services use Podman directly; reserve the Docker-compatible socket
    # for Rakazo's Dockerode-based sandbox supervisor.
    podman.dockerCompat = lib.mkForce false;
    podman.dockerSocket.enable = lib.mkForce false;
  };

  users.groups.rakazo = { };
  users.users = {
    rakazo = {
      isSystemUser = true;
      group = "rakazo";
    };
    rakazo-sandbox = {
      isSystemUser = true;
      group = "rakazo";
      extraGroups = [ "docker" ];
    };
  };

  services.postgresql = {
    ensureDatabases = [ "rakazo" ];
    ensureUsers = [
      {
        name = "rakazo";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 rakazo rakazo -"
    "d ${stateDir}/tmp 0750 rakazo rakazo -"
  ];

  systemd.services = {
    rakazo-secrets = {
      description = "Generate stable Rakazo service secrets";
      before = [
        "rakazo-migrate.service"
        "rakazo-api.service"
        "rakazo-worker.service"
        "rakazo-web.service"
        "rakazo-sandbox-supervisor.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "rakazo";
        Group = "rakazo";
        ExecStart = generateSecrets;
        RemainAfterExit = true;
      };
    };

    rakazo-migrate = {
      description = "Apply Rakazo database migrations";
      after = [
        "postgresql.service"
        "rakazo-secrets.service"
      ];
      requires = [
        "postgresql.service"
        "rakazo-secrets.service"
      ];
      before = [
        "rakazo-api.service"
        "rakazo-worker.service"
      ];
      wantedBy = [ "multi-user.target" ];
      environment = commonEnvironment;
      serviceConfig = serviceConfig // {
        Type = "oneshot";
        ExecStart = "${node} ${prisma} migrate deploy --schema ${appRoot}/packages/db/prisma/schema.prisma";
        RemainAfterExit = true;
        Restart = "no";
      };
    };

    rakazo-sandbox-supervisor = {
      description = "Rakazo Docker computer supervisor";
      after = [
        "docker.service"
        "rakazo-secrets.service"
      ];
      requires = [
        "docker.service"
        "rakazo-secrets.service"
      ];
      wantedBy = [ "multi-user.target" ];
      environment = commonEnvironment // {
        SUPERVISOR_HOST = "127.0.0.1";
        SUPERVISOR_PORT = toString supervisorPort;
        DOCKER_SOCKET = "/var/run/docker.sock";
        RAKAZO_COMPUTER_IMAGE = computerImage;
        RAKAZO_COMPUTER_CONTEXT = "${appRoot}/infra/sandboxes/computer";
        SANDBOX_SCREEN_HOST = "127.0.0.1";
      };
      serviceConfig = serviceConfig // {
        User = "rakazo-sandbox";
        SupplementaryGroups = [ "docker" ];
        ExecStart = "${node} ${tsx} ${appRoot}/infra/sandboxes/supervisor/src/index.ts";
        ReadWritePaths = [
          stateDir
          "/var/run/docker.sock"
        ];
      };
    };

    rakazo-api = {
      description = "Rakazo API";
      after = [
        "rakazo-migrate.service"
        "rakazo-sandbox-supervisor.service"
      ];
      requires = [
        "rakazo-migrate.service"
        "rakazo-sandbox-supervisor.service"
      ];
      wantedBy = [ "multi-user.target" ];
      environment = commonEnvironment // {
        API_PORT = toString apiPort;
      };
      serviceConfig = serviceConfig // {
        ExecStart = "${node} ${tsx} ${appRoot}/apps/api/src/index.ts";
      };
    };

    rakazo-worker = {
      description = "Rakazo background worker";
      after = [
        "rakazo-migrate.service"
        "rakazo-sandbox-supervisor.service"
      ];
      requires = [
        "rakazo-migrate.service"
        "rakazo-sandbox-supervisor.service"
      ];
      wantedBy = [ "multi-user.target" ];
      environment = commonEnvironment;
      serviceConfig = serviceConfig // {
        ExecStart = "${node} ${tsx} ${appRoot}/apps/worker/src/index.ts";
      };
    };

    rakazo-web = {
      description = "Rakazo web client";
      after = [
        "rakazo-api.service"
        "rakazo-secrets.service"
      ];
      requires = [
        "rakazo-api.service"
        "rakazo-secrets.service"
      ];
      wantedBy = [ "multi-user.target" ];
      environment = commonEnvironment // {
        API_PROXY_TARGET = "http://127.0.0.1:${toString apiPort}";
        WEB_PORT = toString webPort;
        RAKAZO_HOST = "127.0.0.1";
        TMPDIR = "${stateDir}/tmp";
      };
      serviceConfig = serviceConfig // {
        ExecStart = "${node} ${vite} preview --configLoader runner --host 127.0.0.1 --port ${toString webPort}";
      };
    };
  };
}
