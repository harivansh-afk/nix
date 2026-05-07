{
  config,
  inputs,
  lib,
  loopbackVhost,
  mkSparkSecret,
  pkgs,
  ...
}:
let
  mirrorDomain = "mirror.harivan.sh";
  backendPort = 19301;
  dbPath = "/var/lib/gitea-mirror/gitea-mirror.db";
  protectedRepositories = [
    "harivansh-afk/website"
    "harivansh-afk/nix"
    "harivansh-afk/nvim-wiki"
    "harivansh-afk/computer-runtime"
    "harivansh-afk/tmux-subagents"
    "harivansh-afk/tmux-wiki"
    "harivansh-afk/deskctl"
    "harivansh-afk/gobank"
    "harivansh-afk/dungeon"
    "harivansh-afk/cozybox.nvim"
    "harivansh-afk/betterNAS"
    "harivansh-afk/pi-telegram-webhook"
    "harivansh-afk/agentikube"
    "harivansh-afk/clanker-agent"
    "harivansh-afk/einstein"
    "harivansh-afk/rpi"
    "harivansh-afk/agentcomputer-delegate"
    "harivansh-afk/dots"
    "harivansh-afk/.tmux"
    "harivansh-afk/nvim"
    "harivansh-afk/auto-review-check"
    "harivansh-afk/sep"
    "harivansh-afk/ralph-cli"
    "harivansh-afk/claude-code-vertical"
    "harivansh-afk/claude-setup"
    "harivansh-afk/eval-skill"
    "harivansh-afk/evaluclaude-harness"
    "harivansh-afk/system-design"
    "harivansh-afk/claude-continual-learning"
    "harivansh-afk/distributed-systems"
    "harivansh-afk/url-shortner"
    "harivansh-afk/React-Portfolio"
    "harivansh-afk/GymSupps"
    "harivansh-afk/asap.it"
    "harivansh-afk/RAG-ui"
    "harivansh-afk/Austens-Wedding-Guide"
    "harivansh-afk/Resume-website"
    "harivansh-afk/Habit-Tracker"
    "harivansh-afk/Saas-Teamspace-2"
    "harivansh-afk/Saas-Teamspace"
    "harivansh-afk/CryptoCurrencyPredictionLSTM"
    "harivansh-afk/delta"
    "harivansh-afk/diffkit"
    "harivansh-afk/forge.nvim"
    "harivansh-afk/sandbox-agent"
    "harivansh-afk/cp.nvim"
    "harivansh-afk/oil.nvim"
    "harivansh-afk/ds1001_final"
    "harivansh-afk/DS1001-LABS-Projects"
    "harivansh-afk/WebKit"
    "harivansh-afk/ix"
    "harivansh-afk/harivansh-afk"
    "harivansh-afk/clawd"
    "harivansh-afk/cozybox.nvim-archive-20260320-133310"
    "harivansh-afk/Solvex"
    "harivansh-afk/clank-artifacts"
    "harivansh-afk/auto-school"
    "harivansh-afk/rpi-artifacts"
    "harivansh-afk/Twylo"
    "harivansh-afk/AI-image-editor"
    "harivansh-afk/thread-view"
    "harivansh-afk/ytdlp-api"
    "harivansh-afk/clawd-stack"
    "harivansh-afk/thread-view-data"
    "harivansh-afk/X-CLI"
    "harivansh-afk/delphi-internal-dash"
    "harivansh-afk/better"
    "harivansh-afk/hari-data-pipeline"
    "harivansh-afk/The-Truman-Project"
    "harivansh-afk/EstateAI"
    "harivansh-afk/gtmark"
    "harivansh-afk/ai-scripts"
    "harivansh-afk/befreed"
    "harivansh-afk/mixwithclaude"
    "harivansh-afk/berkeley-mono-"
    "harivansh-afk/dotfiles"
    "harivansh-afk/college"
    "harivansh-afk/phinsta"
    "harivansh-afk/gmv"
    "harivansh-afk/llm-scripts"
    "harivansh-afk/config"
    "harivansh-afk/fireplexity"
    "harivansh-afk/truman-backend"
    "harivansh-afk/theburnouts"
    "harivansh-afk/twylo-backend"
    "harivansh-afk/blendify-vibes"
    "harivansh-afk/project-files"
    "harivansh-afk/interview-coder"
    "harivansh-afk/SupplMen"
    "harivansh-afk/AI-dev-framework-2.0"
    "harivansh-afk/emails"
  ];
  protectedRepositoriesJson = builtins.toJSON protectedRepositories;
  protectedRepositoryNamesSql = lib.concatMapStringsSep ", " (
    repo: "'${lib.removePrefix "harivansh-afk/" repo}'"
  ) protectedRepositories;

  protectCanonicalRepositories = pkgs.writeShellScript "gitea-mirror-protect-canonical-repositories" ''
    set -eu
    DB=${dbPath}
    [ -f "$DB" ] || exit 0
    SQLITE=${pkgs.sqlite}/bin/sqlite3

    "$SQLITE" "$DB" \
      "UPDATE repositories SET status='ignored' WHERE owner='harivansh-afk' AND name IN (${protectedRepositoryNamesSql});"
    "$SQLITE" "$DB" <<'SQL'
    UPDATE configs SET exclude='${protectedRepositoriesJson}';
    SQL

    "$SQLITE" "$DB" "
      UPDATE configs SET
        github_config = json_set(
          github_config,
          '$.includeStarred',     json('false'),
          '$.autoMirrorStarred',  json('false'),
          '$.includePublic',      json('true'),
          '$.includePrivate',     json('true')
        ),
        gitea_config = json_remove(
          json_set(
            gitea_config,
            '$.preserveVisibility', json('true'),
            '$.visibility',         'default'
          ),
          '$.mirrorInterval'
        )
      WHERE github_config IS NOT NULL AND gitea_config IS NOT NULL;
    "

    "$SQLITE" "$DB" "
      UPDATE configs SET
        schedule_config = json_set(
          schedule_config,
          '$.enabled',              json('true'),
          '$.autoImport',           json('false'),
          '$.autoMirror',           json('false'),
          '$.interval',             '3600',
          '$.batchSize',            1,
          '$.pauseBetweenBatches',  60000,
          '$.onlyMirrorUpdated',    json('true'),
          '$.skipRecentlyMirrored', json('true'),
          '$.updateInterval',       86400000,
          '$.recentThreshold',      86400000
        )
      WHERE schedule_config IS NOT NULL;
    "

    "$SQLITE" "$DB" \
      "UPDATE repositories SET status='ignored' WHERE is_starred = 1 AND owner != 'harivansh-afk';"
    "$SQLITE" "$DB" \
      "UPDATE repositories SET status='ignored' WHERE status='failed' AND (error_message LIKE '%timed out%' OR error_message LIKE '%context deadline exceeded%' OR error_message LIKE '%context canceled%');"
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

  systemd.services.gitea-mirror.environment = {
    AUTO_IMPORT_REPOS = "false";
    AUTO_MIRROR_REPOS = "false";
    SCHEDULE_AUTO_IMPORT = "false";
    SCHEDULE_AUTO_MIRROR = "false";
    SCHEDULE_BATCH_SIZE = "1";
    SCHEDULE_INTERVAL = "1h";
    SCHEDULE_ONLY_MIRROR_UPDATED = "true";
    SCHEDULE_PAUSE_BETWEEN_BATCHES = "60000";
    SCHEDULE_RECENT_THRESHOLD = "86400000";
    SCHEDULE_SKIP_RECENTLY_MIRRORED = "true";
    SCHEDULE_UPDATE_INTERVAL = "86400000";
  };

  systemd.services.gitea-mirror.serviceConfig.ExecStartPre = [
    protectCanonicalRepositories.outPath
  ];
}
