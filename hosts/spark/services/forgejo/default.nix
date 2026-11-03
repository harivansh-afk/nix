{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  rootDomain = "harivan.sh";
  forgejoDomain = "git.${rootDomain}";
  backendPort = 19300;
  gitCredentialFile = "/var/lib/forgejo/.git-credentials";
  smtpPasswordFile = config.sops.secrets."forgejo-smtp-password".path;
  mirrorGithubTokenFile = config.sops.secrets."forgejo-mirror-github-token.env".path;
  oauthProviders = {
    github = "github";
    google = "gplus";
  };
  oauthSources = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: provider:
      let
        prefix = lib.toUpper name;
      in
      "${name}:${provider}:oauth-${name}:${prefix}_OAUTH_CLIENT_ID:${prefix}_OAUTH_CLIENT_SECRET"
    ) oauthProviders
  );

  forgejoDb = "/var/lib/forgejo/data/forgejo.db";
  repoUnits = "repo.code,repo.releases,repo.issues,repo.pulls,repo.wiki,repo.projects,repo.packages";
  mirrorIntervalSeconds = 15 * 60;

  normalizeMirrorSchedule = pkgs.writeShellScript "forgejo-normalize-mirror-schedule" ''
    export FORGEJO_DB=${forgejoDb}
    export MIRROR_INTERVAL_SECONDS=${toString mirrorIntervalSeconds}
    exec ${pkgs.python3}/bin/python3 ${./normalize-mirror-schedule.py}
  '';

  pierreForgejo = inputs.pierrejo.lib.mkPierreForgejo { inherit pkgs; };
  forgejoWeb = import ./web.nix {
    inherit
      forgejoDomain
      lib
      pierreForgejo
      pkgs
      ;
  };
  forgejoPackageBase = pkgs.callPackage (import "${pkgs.path}/pkgs/by-name/fo/forgejo/generic.nix" {
    version = "17.0.1";
    hash = "sha256-O12795/ydtEequagQfHfOhKTEp8QlmzsJe+RtlHC60A=";
    npmDepsHash = "sha256-5TrydMO82d30L/EaWg3GI+yaBwG6tZS4IVs+dydpKRY=";
    vendorHash = "sha256-vXjsZ08eez3oiLL2Um+uFX9YbrRnbq8q5Pj/P3mZTeY=";
    lts = false;
  }) { };
  forgejoPackage = pierreForgejo.mkForgejoWithPierre (
    forgejoPackageBase.overrideAttrs (old: {
      patches = [
        "${pkgs.path}/pkgs/by-name/fo/forgejo/static-root-path.patch"
      ];

      preCheck = (old.preCheck or "") + ''
        substituteInPlace modules/git/hook_generate.go \
          --replace-fail "#!/usr/bin/env" "#!${pkgs.lib.getExe' pkgs.coreutils "env"}"
      '';
      checkFlags = [
        "-skip=^TestPassword$|^TestCaptcha$|^TestDNSUpdate$|^TestMigrateRepository$|^TestMigrateWhiteBlocklist$|^TestURLAllowedSSH/Pushmirror_URL$|^TestBleveDeleteIssue$|^TestActivityPubMatchesList$"
      ];
    })
  );
in
{
  imports = [
    ./mirror.nix
    ./runner.nix
    pierreForgejo.nixosModule
  ];

  security.acme.certs.${forgejoDomain} = {
    dnsProvider = "cloudflare";
    dnsResolver = "1.1.1.1:53";
    credentialFiles.CLOUDFLARE_DNS_API_TOKEN_FILE = config.sops.secrets."cloudflare-api-token".path;
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];

  services.caddy.virtualHosts."https://${forgejoDomain}" = {
    useACMEHost = forgejoDomain;
    extraConfig = ''
      encode zstd gzip

      @forgejoAssets path /assets/* /manifest.json /favicon.svg /favicon.png /apple-touch-icon.png
      header @forgejoAssets Cache-Control "public, max-age=21600"

      handle_path /assets/fonts/* {
        root * /srv/harivan.sh/dist/fonts
        header Cache-Control "public, max-age=31536000, immutable"
        file_server
      }

      reverse_proxy 127.0.0.1:${toString backendPort}
    '';
  };

  users.users.git = {
    isSystemUser = true;
    home = "/var/lib/forgejo";
    group = "git";
    shell = "${pkgs.bash}/bin/bash";
  };
  users.groups.git = { };

  security.pam.services.sshd.rules.session.forgejo-systemd = {
    order = config.security.pam.services.sshd.rules.session.systemd.order - 1;
    control = "[success=1 default=ignore]";
    modulePath = "${pkgs.pam}/lib/security/pam_succeed_if.so";
    args = [
      "quiet"
      "user"
      "="
      "git"
    ];
  };

  systemd.services.forgejo.restartTriggers = [
    forgejoWeb.public
    forgejoWeb.templates
  ];

  systemd.services.forgejo.preStart = lib.mkMerge [
    (lib.mkBefore ''
      if [ -f ${forgejoDb} ] && [ ! -f /var/lib/forgejo/upgrade-backups/pre-v17.db ]; then
        ${pkgs.coreutils}/bin/install -d -m 0700 /var/lib/forgejo/upgrade-backups
        ${pkgs.sqlite}/bin/sqlite3 ${forgejoDb} ".backup '/var/lib/forgejo/upgrade-backups/pre-v17.db.tmp'"
        ${pkgs.coreutils}/bin/chmod 0600 /var/lib/forgejo/upgrade-backups/pre-v17.db.tmp
        ${pkgs.coreutils}/bin/mv /var/lib/forgejo/upgrade-backups/pre-v17.db.tmp /var/lib/forgejo/upgrade-backups/pre-v17.db
      fi
    '')
    (lib.mkAfter ''
      export PATH=${
        lib.makeBinPath [
          pkgs.git
          pkgs.gawk
        ]
      }:$PATH
      export GITHUB_TOKEN_FILE=${mirrorGithubTokenFile}
      export GIT_CREDENTIAL_FILE=${gitCredentialFile}
      export FORGEJO=${config.services.forgejo.package}/bin/forgejo
      export OAUTH_SOURCES=${lib.escapeShellArg oauthSources}
      ${pkgs.bash}/bin/bash ${./pre-start.sh}
    '')
  ];

  services.forgejo = {
    enable = true;
    package = forgejoPackage;
    user = "git";
    group = "git";
    secrets.mailer.PASSWD = smtpPasswordFile;
    settings = {
      "git.timeout" = {
        MIRROR = 1800;
        MIGRATE = 1800;
      };
      server = {
        DOMAIN = forgejoDomain;
        ROOT_URL = "https://${forgejoDomain}/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = backendPort;
        SSH_DOMAIN = forgejoDomain;
        LANDING_PAGE = "/harivansh-afk";
      };
      service = {
        DISABLE_REGISTRATION = true;
        REGISTER_EMAIL_CONFIRM = true;
        SEND_NOTIFICATION_EMAIL_ON_NEW_USER = true;
      };
      repository = {
        DEFAULT_PRIVATE = "private";

        DEFAULT_REPO_UNITS = repoUnits;
        DEFAULT_FORK_REPO_UNITS = repoUnits;
        DEFAULT_MIRROR_REPO_UNITS = repoUnits;
        DEFAULT_TEMPLATE_REPO_UNITS = repoUnits;
      };
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtps";
        SMTP_ADDR = "smtp.resend.com";
        SMTP_PORT = 465;
        USER = "resend";
        FROM = "Forgejo <git@${rootDomain}>";
      };
      session.COOKIE_SECURE = true;
      database = {
        SQLITE_JOURNAL_MODE = "WAL";
        SQLITE_TIMEOUT = 10000;
      };
      mirror = {
        DEFAULT_INTERVAL = "15m";
        MIN_INTERVAL = "5m";
      };
      "queue.mirror" = {
        MAX_WORKERS = 1;
      };
      actions = {
        DEFAULT_ACTIONS_URL = "https://github.com";
      };
      "cron.cleanup_offline_runners" = {
        ENABLED = true;
        RUN_AT_START = true;
        GLOBAL_SCOPE_ONLY = false;
      };
      "git.config" = {
        "credential.helper" = "store --file ${gitCredentialFile}";
      };
      "repository.signing" = {
        FORMAT = "ssh";
        SIGNING_KEY = "/var/lib/forgejo/signing/id_ed25519.pub";
        SIGNING_NAME = "Forgejo";
        SIGNING_EMAIL = "git@${rootDomain}";
        MERGES = "always";
      };
      ui = {
        DEFAULT_THEME = "cozybox-auto";
        THEMES = "cozybox-auto,cozybox-light,cozybox-dark,forgejo-auto,forgejo-dark,forgejo-light";
      };
      picture = {
        ENABLE_FEDERATED_AVATAR = true;
      };
      oauth2_client = {
        UPDATE_AVATAR = true;
      };
      "ui.meta" = {
        AUTHOR = forgejoDomain;
        DESCRIPTION = "Personal code, experiments, and project history.";
        KEYWORDS = "git,code,harivansh,rathi,nix";
      };
      other = {
        SHOW_FOOTER_VERSION = false;
        SHOW_FOOTER_TEMPLATE_LOAD_TIME = false;
        SHOW_FOOTER_LICENSES_API = false;
        SHOW_FOOTER_POWERED_BY = false;
      };
      api = {
        ENABLE_SWAGGER = false;
      };
    };
  };

  services.pierre-ssr.enable = true;

  systemd.services.forgejo = {
    after = [ "pierre-ssr.service" ];
    wants = [ "pierre-ssr.service" ];
    environment.GIT_HTTP_LOW_SPEED_TIME = "600";
    serviceConfig.Environment = [
      "PIERRE_FILE_TREE=true"
      "PIERRE_SSR_SOCKET=${config.services.pierre-ssr.socketPath}"
    ];
  };

  systemd.services.forgejo.serviceConfig.ExecStartPre = lib.mkBefore [
    (pkgs.writeShellScript "forgejo-signing-key" ''
      if [ ! -f /var/lib/forgejo/signing/id_ed25519 ]; then
        mkdir -p /var/lib/forgejo/signing
        chmod 700 /var/lib/forgejo/signing
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" \
          -C "forgejo@${rootDomain}" -f /var/lib/forgejo/signing/id_ed25519
      fi
    '')
    normalizeMirrorSchedule
  ];
  systemd.services.forgejo.serviceConfig.LoadCredential = lib.mkAfter (
    lib.mapAttrsToList (
      name: _: "oauth-${name}:${config.sops.secrets."forgejo-${name}-oauth.env".path}"
    ) oauthProviders
  );

  systemd.tmpfiles.rules = [
    "L+ /var/lib/forgejo/.gitconfig - - - - /var/lib/forgejo/data/home/.gitconfig"

    "L+ /var/lib/forgejo/custom/public - - - - ${forgejoWeb.public}"
    "L+ /var/lib/forgejo/custom/templates - - - - ${forgejoWeb.templates}"
  ];

}
