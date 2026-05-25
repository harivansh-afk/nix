{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.pierre-ssr;
  pierreSsrPackage = pkgs.buildNpmPackage {
    pname = "pierre-ssr";
    version = "0.0.0";
    src = ./pierre-ssr;
    npmDepsHash = "sha256-I+EWA3gZJV5lTNvZNWXIAwQvKVD9ygCiyCe/A4W4o70=";
    dontNpmBuild = true;
    nativeBuildInputs = [
      pkgs.makeWrapper
    ];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/pierre-ssr
      cp -R . $out/lib/pierre-ssr
      makeWrapper ${pkgs.nodejs}/bin/node $out/bin/pierre-ssr --add-flags $out/lib/pierre-ssr/server.js
      runHook postInstall
    '';
  };
in
{
  options.services.pierre-ssr = {
    enable = lib.mkEnableOption "Pierre SSR highlighter";
    socketPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/pierre-ssr/pierre.sock";
    };
    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/pierre-ssr";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /run/pierre-ssr 0755 git git -"
      "d ${cfg.cacheDir} 0750 git git -"
    ];

    systemd.services.pierre-ssr = {
      description = "Pierre SSR highlighter";
      wantedBy = [ "multi-user.target" ];
      before = [ "forgejo.service" ];
      serviceConfig = {
        Type = "simple";
        User = "git";
        Group = "git";
        RuntimeDirectory = "pierre-ssr";
        CacheDirectory = "pierre-ssr";
        Environment = [
          "PIERRE_SSR_SOCKET=${cfg.socketPath}"
          "PIERRE_SSR_CACHE_DIR=${cfg.cacheDir}"
        ];
        ExecStart = "${pierreSsrPackage}/bin/pierre-ssr";
        Restart = "on-failure";
        RestartSec = "2s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          "/run/pierre-ssr"
          cfg.cacheDir
        ];
      };
    };
  };
}
