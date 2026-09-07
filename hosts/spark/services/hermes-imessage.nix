{
  config,
  lib,
  pkgs,
  ...
}:
let
  hermes = config.services.hermes-agent;
  root = "${hermes.stateDir}/.hermes";
  profileHome = "${root}/profiles/imessage";
  backup = "${hermes.stateDir}/imessage-migration-backup";
  settings = pkgs.writeText "hermes-imessage-config.yaml" (
    builtins.toJSON (lib.recursiveUpdate { terminal.cwd = hermes.workingDirectory; } hermes.settings)
  );
in
{
  services.hermes-agent = {
    extraArgs = [
      "--profile"
      "imessage"
    ];
    configFile = pkgs.writeText "hermes-default-config.yaml" (
      builtins.toJSON {
        model = hermes.settings.model;
        platform_toolsets.cli = [ ];
        plugins = {
          enabled = [ ];
          disabled = [
            "conversation"
            "knowledge-base"
          ];
        };
        skills = {
          external_dirs = [ ];
          project_discovery = false;
          creation_nudge_interval = 0;
        };
        memory = {
          memory_enabled = false;
          user_profile_enabled = false;
        };
      }
    );
    hermesHomeFiles = {
      "profiles/imessage/config.yaml" = settings;
      "profiles/imessage/SOUL.md" = ../../../dots/hermes/SOUL.md;
      "profiles/imessage/.managed" = "nixos\n";
      "profiles/imessage/.no-bundled-skills" = "Skills are selected by Nix.\n";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${profileHome} 0700 ${hermes.user} ${hermes.group} - -"
    "L+ ${profileHome}/.env - - - - ../../.env"
    "L+ ${profileHome}/plugins - - - - ../../plugins"
  ];

  systemd.services.hermes-agent = {
    environment.HERMES_HOME = lib.mkForce profileHome;
    restartTriggers = [ settings ];
    preStart = ''
      if [ ! -e ${profileHome}/.migrated-from-default ]; then
        if ${pkgs.lsof}/bin/lsof -t ${root}/state.db >/dev/null 2>&1; then
          echo "Hermes migration requires the default profile's database to be closed." >&2
          exit 1
        fi
        install -d -m 0700 ${backup}
        if [ -e ${root}/state.db ] && [ ! -e ${backup}/database-migrated ]; then
          test ! -e ${profileHome}/state.db
          ${pkgs.sqlite}/bin/sqlite3 ${root}/state.db ".backup '${backup}/state.db'"
          cp ${backup}/state.db ${profileHome}/state.db.migrating
          ${pkgs.sqlite}/bin/sqlite3 -bail ${profileHome}/state.db.migrating <<'SQL'
      BEGIN IMMEDIATE;
      UPDATE sessions SET profile_name = 'imessage' WHERE profile_name = 'default' OR profile_name IS NULL;
      UPDATE sessions SET session_key = 'agent:imessage:' || substr(session_key, 12)
        WHERE session_key LIKE 'agent:main:%';
      UPDATE sessions SET origin_json = json_set(origin_json, '$.profile', 'imessage')
        WHERE profile_name = 'imessage' AND json_valid(origin_json);
      UPDATE gateway_routing SET scope = '${profileHome}/sessions';
      UPDATE gateway_routing SET
        session_key = 'agent:imessage:' || substr(session_key, 12),
        entry_json = json_set(entry_json,
          '$.session_key', 'agent:imessage:' || substr(session_key, 12),
          '$.origin.profile', 'imessage')
        WHERE session_key LIKE 'agent:main:%';
      COMMIT;
      PRAGMA journal_mode = DELETE;
      SQL
          touch ${backup}/database-migrated
        fi
        if [ -e ${profileHome}/state.db.migrating ] && [ -e ${backup}/database-migrated ]; then
          test ! -e ${profileHome}/state.db
          mv ${profileHome}/state.db.migrating ${profileHome}/state.db
        fi
        if [ -e ${backup}/database-migrated ]; then
          if [ -e ${root}/state.db ]; then
            mv ${root}/state.db ${backup}/state.db.original
          fi
          for suffix in -wal -shm; do
            if [ -e ${root}/state.db"$suffix" ]; then
              mv ${root}/state.db"$suffix" ${backup}/state.db.original"$suffix"
            fi
          done
        fi
        for name in sessions memories cron pending_messages platforms skills; do
          if [ -e ${root}/"$name" ]; then
            if [ -e ${profileHome}/"$name" ]; then
              rmdir ${root}/"$name"
            else
              mv ${root}/"$name" ${profileHome}/"$name"
            fi
          fi
        done
        if [ -e ${profileHome}/sessions/sessions.json ]; then
          mv ${profileHome}/sessions/sessions.json ${backup}/sessions.json
        fi
        touch ${profileHome}/.migrated-from-default
      fi
      install -d -m 0700 ${profileHome}/{cron,sessions,logs,memories,skills}
    '';
  };
}
