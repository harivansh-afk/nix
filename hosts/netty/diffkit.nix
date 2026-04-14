{
  pkgs,
  username,
  ...
}:
let
  diffkitPort = "3200";
  stateDir = "/var/lib/diffkit";
  repoDir = "/home/${username}/Documents/GitHub/diffkit";
  envFile = "${stateDir}/diffkit.env";
  dbPath = "${stateDir}/diffkit.db";
  migrationsDir = "${repoDir}/apps/dashboard/drizzle";

  migrationScript = pkgs.writeShellScript "diffkit-migrate" ''
    set -euo pipefail
    DB="${dbPath}"
    MIGRATIONS="${migrationsDir}"

    ${pkgs.sqlite}/bin/sqlite3 "$DB" "SELECT 1;" > /dev/null 2>&1 || true
    ${pkgs.sqlite}/bin/sqlite3 "$DB" \
      "CREATE TABLE IF NOT EXISTS __drizzle_migrations (tag TEXT PRIMARY KEY, applied_at INTEGER NOT NULL);"

    for sql_file in "$MIGRATIONS"/[0-9]*.sql; do
      [ -f "$sql_file" ] || continue
      tag=$(basename "$sql_file" .sql)
      applied=$(${pkgs.sqlite}/bin/sqlite3 "$DB" "SELECT COUNT(*) FROM __drizzle_migrations WHERE tag='$tag';")
      if [ "$applied" = "0" ]; then
        echo "Applying migration: $tag"
        ${pkgs.gnused}/bin/sed 's/--> statement-breakpoint/;/g' "$sql_file" \
          | ${pkgs.sqlite}/bin/sqlite3 "$DB"
        ${pkgs.sqlite}/bin/sqlite3 "$DB" \
          "INSERT INTO __drizzle_migrations (tag, applied_at) VALUES ('$tag', strftime('%s','now'));"
      fi
    done
    echo "Migrations complete."
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 ${username} users -"
    "z ${envFile} 0600 ${username} users -"
  ];

  systemd.services.diffkit = {
    description = "diffkit GitHub Diff Viewer";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      NODE_ENV = "production";
      HOST = "127.0.0.1";
      PORT = diffkitPort;
      DATABASE_PATH = dbPath;
      BETTER_AUTH_URL = "https://diffs.harivan.sh";
      GITHUB_APP_PRIVATE_KEY_FILE = "${stateDir}/github-app-key.pem";
    };

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = "${repoDir}/apps/dashboard";
      ExecStartPre = migrationScript;
      ExecStart = "${pkgs.nodejs_22}/bin/node node-server.mjs";
      EnvironmentFile = "-${envFile}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
