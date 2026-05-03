{
  config,
  inputs,
  loopbackVhost,
  mkSparkSecret,
  pkgs,
  ...
}:
let
  mirrorDomain = "mirror.harivan.sh";
  backendPort = 19301;
  dbPath = "/var/lib/gitea-mirror/gitea-mirror.db";

  protectCanonicalNix = pkgs.writeShellScript "gitea-mirror-protect-nix" ''
    set -eu
    DB=${dbPath}
    [ -f "$DB" ] || exit 0
    SQLITE=${pkgs.sqlite}/bin/sqlite3

    "$SQLITE" "$DB" \
      "UPDATE repositories SET status='ignored' WHERE owner='harivansh-afk' AND name='nix';"
    "$SQLITE" "$DB" \
      "UPDATE configs SET exclude='[\"harivansh-afk/nix\"]' WHERE exclude='[]' OR exclude IS NULL;"

    "$SQLITE" "$DB" "
      UPDATE configs SET
        github_config = json_set(
          github_config,
          '$.includeStarred',     json('false'),
          '$.autoMirrorStarred',  json('false'),
          '$.includePublic',      json('true'),
          '$.includePrivate',     json('true')
        ),
        gitea_config = json_set(
          gitea_config,
          '$.preserveVisibility', json('true'),
          '$.visibility',         'default'
        )
      WHERE github_config IS NOT NULL AND gitea_config IS NOT NULL;
    "

    "$SQLITE" "$DB" \
      "UPDATE repositories SET status='ignored' WHERE is_starred = 1 AND owner != 'harivansh-afk';"
  '';
in
{
  imports = [ inputs.gitea-mirror.nixosModules.default ];

  services.caddy.virtualHosts."http://${mirrorDomain}" = loopbackVhost backendPort;

  sops.secrets."gitea-mirror.env" = mkSparkSecret "gitea-mirror.env" {
    owner = "gitea-mirror";
    group = "gitea-mirror";
    mode = "0400";
    restartUnits = [ "gitea-mirror.service" ];
  };

  services.gitea-mirror = {
    enable = true;
    host = "127.0.0.1";
    port = backendPort;
    betterAuthUrl = "https://${mirrorDomain}";
    betterAuthTrustedOrigins = "https://${mirrorDomain}";
    environmentFile = config.sops.secrets."gitea-mirror.env".path;
    openFirewall = false;
  };

  systemd.services.gitea-mirror.serviceConfig.ExecStartPre = [
    protectCanonicalNix.outPath
  ];
}
