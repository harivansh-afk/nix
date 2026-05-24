# pierre-ssr: server-side Pierre diff renderer that the patched Forgejo
# template helper dials over a unix socket. The Forgejo `PierreDiff`
# template func POSTs a per-file unified-diff patch and gets back the
# fully rendered Pierre HTML (icon sprite, theme styles, hunk markup).
#
# Why a sidecar and not Go: Pierre's renderer is JavaScript on top of
# Shiki. Reimplementing it server-side in Go would mean reimplementing
# Pierre. A tiny Node service is the smallest correct cutover.
#
# Cache lives under /var/cache/pierre-ssr; a diff between two fixed git
# SHAs is immutable so entries never need invalidation.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.pierre-ssr;
  socketDir = "/run/pierre-ssr";
  socketPath = "${socketDir}/render.sock";
  cacheDir = "/var/cache/pierre-ssr";

  pierreSsrServer = pkgs.buildNpmPackage {
    pname = "pierre-ssr-server";
    version = "0.0.0";
    src = ./server;
    # The first build will fail with the expected hash. Replace the
    # placeholder below with the value reported by nix and rebuild.
    npmDepsHash = "sha256-6/eVnKmiVOsw+GFwKtU+EY0iaHv8TvdKexpteBnRTxI=";
    dontNpmBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/pierre-ssr
      cp -R . $out/lib/pierre-ssr/
      mkdir -p $out/bin
      cat >$out/bin/pierre-ssr <<EOF
      #!${pkgs.runtimeShell}
      exec ${pkgs.nodejs_24}/bin/node $out/lib/pierre-ssr/server.js "\$@"
      EOF
      chmod +x $out/bin/pierre-ssr
      runHook postInstall
    '';
    meta = with lib; {
      description = "Server-side Pierre diff renderer";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };
in
{
  options.services.pierre-ssr = {
    enable = lib.mkEnableOption "Pierre SSR diff renderer for Forgejo";

    user = lib.mkOption {
      type = lib.types.str;
      default = "pierre-ssr";
      description = "User the pierre-ssr service runs as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "pierre-ssr";
      description = "Primary group of the pierre-ssr user.";
    };

    socketGroup = lib.mkOption {
      type = lib.types.str;
      default = "git";
      description = ''
        Group that owns the unix socket so the Forgejo process can dial
        it. The pierre-ssr user is added to this group as well; the
        socket itself is chmod 0660 by the service at listen time.
      '';
    };

    lruMax = lib.mkOption {
      type = lib.types.int;
      default = 512;
      description = "Max number of HTML responses kept in memory LRU.";
    };

    bodyLimitBytes = lib.mkOption {
      type = lib.types.int;
      default = 8 * 1024 * 1024;
      description = "Max accepted request body in bytes.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pierreSsrServer;
      description = "The pierre-ssr server package.";
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      default = socketPath;
      description = "Unix socket path that Forgejo dials.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      extraGroups = [ cfg.socketGroup ];
      home = cacheDir;
      description = "pierre-ssr service user";
    };

    systemd.tmpfiles.rules = [
      "d ${cacheDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.pierre-ssr = {
      description = "Pierre server-side diff renderer";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        NODE_ENV = "production";
        PIERRE_SSR_SOCKET = cfg.socketPath;
        PIERRE_SSR_CACHE_DIR = cacheDir;
        PIERRE_SSR_LRU_MAX = toString cfg.lruMax;
        PIERRE_SSR_BODY_LIMIT = toString cfg.bodyLimitBytes;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/pierre-ssr";
        User = cfg.user;
        Group = cfg.group;
        RuntimeDirectory = "pierre-ssr";
        RuntimeDirectoryMode = "0750";
        CacheDirectory = "pierre-ssr";
        CacheDirectoryMode = "0750";
        Restart = "on-failure";
        RestartSec = 2;
        # Hardening. Pierre-ssr is pure JS + filesystem cache.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false;
        SystemCallArchitectures = "native";
        ReadWritePaths = [ cacheDir ];
        ProtectClock = true;
        ProtectKernelLogs = true;
        ProtectHostname = true;
      };
    };
  };
}
